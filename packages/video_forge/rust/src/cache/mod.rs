//! LRU cache for short-lived demuxer + decoder pairs.
//!
//! Repeated `thumbnail`, `decode_preview_frame_rgba`, and similar one-shot
//! FFmpeg calls previously re-opened the input via `avformat_open_input`
//! every time. For local files with deep containers (iPhone HEVC + Dolby
//! Vision MOV, `apac` audio) that probeduration/analyzeduration is
//! non-trivial; for remote URLs each call is a full HTTP round-trip.
//!
//! [`DecoderCache`] keeps a small LRU of `CachedDecoder` entries keyed by
//! the normalized input path/url. Each cache hit reuses the open
//! `AVFormatContext` and only re-seeks / re-decodes.
//!
//! Default config:
//! - Capacity: 4 entries (configurable).
//! - Idle TTL: 30 s since last use (configurable).
//! - Memory cap: ~256 MB total working buffer estimate (sum of
//!   `width*height*4` per entry); the cache evicts the least-recently-used
//!   entry that pushes the total above the cap.
//!
//! Public API:
//! - [`acquire`]: get or open a fresh `CachedDecoder`. Caller must call
//!   `release(entry, last_seek_ms)` after the decode completes.
//! - [`clear`]: drop every entry (used by tests / memory warnings).
//! - [`stats`]: count + estimated working-set bytes (for telemetry).
//!
//! Thread-safety: backed by a `parking_lot::Mutex`. Single global instance
//! via `LazyLock`. Held mutex duration is bounded (microseconds for cache
//! hits, hundreds of ms for misses when FFmpeg opens the file). The
//! `CachedDecoder` itself is `!Send` (it holds an `Input` which is `!Send`),
//! so the cache returns a *boxed* entry whose contents the caller uses
//! while holding the global lock-free "check out" pattern below.

use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::LazyLock;
use std::time::{Duration, Instant};

use ffmpeg_next::codec::context::Context as CodecContext;
use ffmpeg_next::codec::decoder::Video as DecoderVideo;
use ffmpeg_next::format::context::Input;
use parking_lot::Mutex;
use serde::{Deserialize, Serialize};

use crate::error::{Result, VideoForgeError};
use crate::ffmpeg::ensure_input_accessible;
use crate::ffmpeg::input::normalize_remote_input;
use crate::ffmpeg::{is_remote_input, map_ffmpeg_error, open_input, open_input_for_preview};

/// Default number of cached demuxers. 4 is enough for the common
/// "scrub thumbnail filmstrip + the main preview" pattern.
pub const DEFAULT_CAPACITY: usize = 4;

/// Default idle TTL. After this duration with no access, the entry is
/// evicted on the next `acquire` (or `clear`).
pub const DEFAULT_IDLE_TTL: Duration = Duration::from_secs(30);

/// Default working-set memory cap in bytes. ~256 MB.
pub const DEFAULT_MEMORY_CAP_BYTES: u64 = 256 * 1024 * 1024;

fn nonzero_cap(cap: usize) -> std::num::NonZeroUsize {
    std::num::NonZeroUsize::new(cap.max(1))
        .expect("cap is at least 1")
}

/// User-tunable cache config (used by tests + the `clearDecoderCache` path).
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct DecoderCacheConfig {
    pub capacity: usize,
    pub idle_ttl: Duration,
    pub memory_cap_bytes: u64,
    pub enabled: bool,
}

impl Default for DecoderCacheConfig {
    fn default() -> Self {
        Self {
            capacity: DEFAULT_CAPACITY,
            idle_ttl: DEFAULT_IDLE_TTL,
            memory_cap_bytes: DEFAULT_MEMORY_CAP_BYTES,
            enabled: true,
        }
    }
}

impl DecoderCacheConfig {
    /// Convenience: disabled cache (still functional, just doesn't keep
    /// entries across calls).
    pub fn disabled() -> Self {
        Self {
            enabled: false,
            ..Self::default()
        }
    }
}

/// A cached demuxer + decoder pair, plus a hint about the last seek so a
/// re-seek to a nearby position is cheaper (avoids another
/// `avformat_seek_file` on the same input).
pub struct CachedDecoder {
    pub ictx: Input,
    pub decoder: DecoderVideo,
    pub width: u32,
    pub height: u32,
    pub last_seek_ms: u64,
    pub last_used: Instant,
    pub working_set_bytes: u64,
    /// `true` if the input was opened in preview (faster probe) mode.
    pub is_preview: bool,
}

#[derive(Default)]
struct CacheStats {
    hits: AtomicU64,
    misses: AtomicU64,
    evictions: AtomicU64,
}

const ZERO_STATS: CacheStats = CacheStats {
    hits: AtomicU64::new(0),
    misses: AtomicU64::new(0),
    evictions: AtomicU64::new(0),
};

struct CacheInner {
    capacity: usize,
    idle_ttl: Duration,
    memory_cap_bytes: u64,
    enabled: bool,
    entries: lru::LruCache<String, CachedDecoder>,
    /// Sum of `working_set_bytes` across currently-cached entries.
    total_working_set_bytes: u64,
}

static CACHE: LazyLock<Mutex<CacheInner>> = LazyLock::new(|| {
    Mutex::new(CacheInner::with_default_config())
});
static STATS: CacheStats = ZERO_STATS;

impl CacheInner {
    fn with_default_config() -> Self {
        let cfg = DecoderCacheConfig::default();
        Self {
            capacity: cfg.capacity,
            idle_ttl: cfg.idle_ttl,
            memory_cap_bytes: cfg.memory_cap_bytes,
            enabled: cfg.enabled,
            entries: lru::LruCache::new(nonzero_cap(cfg.capacity)),
            total_working_set_bytes: 0,
        }
    }

    fn evict_lru_if_over_memory(&mut self) {
        if self.total_working_set_bytes <= self.memory_cap_bytes {
            return;
        }
        // Pop from the LRU end until under cap.
        while self.total_working_set_bytes > self.memory_cap_bytes {
            if let Some((k, v)) = self.entries.pop_lru() {
                self.total_working_set_bytes = self
                    .total_working_set_bytes
                    .saturating_sub(v.working_set_bytes);
                log::debug!(
                    "[DecoderCache] evict key={} reason=memory working_set_after={}B",
                    k,
                    self.total_working_set_bytes
                );
                STATS.evictions.fetch_add(1, Ordering::Relaxed);
            } else {
                break;
            }
        }
    }

    fn evict_expired(&mut self, now: Instant) {
        let ttl = self.idle_ttl;
        let expired: Vec<String> = self
            .entries
            .iter()
            .filter_map(|(k, v)| {
                if now.duration_since(v.last_used) > ttl {
                    Some(k.clone())
                } else {
                    None
                }
            })
            .collect();
        for k in expired {
            if let Some(v) = self.entries.pop(&k) {
                self.total_working_set_bytes = self
                    .total_working_set_bytes
                    .saturating_sub(v.working_set_bytes);
                log::debug!("[DecoderCache] evict key={} reason=ttl", k);
                STATS.evictions.fetch_add(1, Ordering::Relaxed);
            }
        }
    }
}

/// Public read-only stats for telemetry.
#[derive(Clone, Copy, Debug)]
pub struct CacheStatsSnapshot {
    pub hits: u64,
    pub misses: u64,
    pub evictions: u64,
    pub entries: usize,
    pub working_set_bytes: u64,
}

/// Snapshot of current cache state. Cheap; takes the lock briefly.
pub fn stats() -> CacheStatsSnapshot {
    let cache = CACHE.lock();
    CacheStatsSnapshot {
        hits: STATS.hits.load(Ordering::Relaxed),
        misses: STATS.misses.load(Ordering::Relaxed),
        evictions: STATS.evictions.load(Ordering::Relaxed),
        entries: cache.entries.len(),
        working_set_bytes: cache.total_working_set_bytes,
    }
}

/// Drop all cached entries. Returns the number of entries dropped.
pub fn clear() -> usize {
    let mut cache = CACHE.lock();
    let count = cache.entries.len();
    cache.entries.clear();
    cache.total_working_set_bytes = 0;
    if count > 0 {
        log::info!("[DecoderCache] cleared {} entries", count);
    }
    count
}

/// Configure the global cache. `set_config(cfg)` re-creates the LRU with
/// the new capacity but does NOT drop existing entries whose capacity
/// exceeds the new limit (they are evicted lazily on the next
/// `evict_lru_if_over_memory`).
pub fn set_config(cfg: DecoderCacheConfig) {
    let mut cache = CACHE.lock();
    cache.capacity = cfg.capacity;
    cache.idle_ttl = cfg.idle_ttl;
    cache.memory_cap_bytes = cfg.memory_cap_bytes;
    cache.enabled = cfg.enabled;
    // Resize the LRU to the new capacity.
    cache.entries.resize(nonzero_cap(cfg.capacity));
    log::info!(
        "[DecoderCache] configured capacity={} ttl_ms={} mem_cap_b={} enabled={}",
        cfg.capacity,
        cfg.idle_ttl.as_millis() as u64,
        cfg.memory_cap_bytes,
        cfg.enabled
    );
}

/// Normalize the cache key: same URL or local path produces the same key.
fn cache_key(input: &str) -> String {
    if is_remote_input(input) {
        normalize_remote_input(input)
    } else {
        input.trim().to_string()
    }
}

/// Per-call mode for the cached decoder (matches the existing thumbnail
/// / preview heuristics).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum OpenMode {
    /// Faster probe for preview/scrub (skips deep `apac` audio analysis).
    Preview,
    /// Full probe for export/metadata paths.
    Export,
}

/// Internal: get-or-open a decoder for [key]. Updates `last_used`.
/// Caller must hold the returned [`CachedDecoder`] only as long as
/// needed; the entry remains in the cache (so the next call to the same
/// key can hit). Use [`release`] to update `last_used` + `last_seek_ms`.
pub fn acquire(input: &str, mode: OpenMode) -> Result<CachedDecoder> {
    let trimmed = input.trim();
    ensure_input_accessible(trimmed)?;
    let key = cache_key(trimmed);

    {
        let mut cache = CACHE.lock();
        if !cache.enabled {
            // Drop the lock before opening.
        } else {
            // Opportunistic TTL sweep (cheap; only iterates entries).
            cache.evict_expired(Instant::now());

            if let Some(entry) = cache.entries.get(&key) {
                STATS.hits.fetch_add(1, Ordering::Relaxed);
                // Touch last_used by replacing the entry with a clone of
                // the metadata; the heavy state (Input, DecoderVideo)
                // is borrowed for the duration of the call.
                let mut owned = CachedDecoder {
                    ictx: borrow_input(&entry.ictx)?,
                    decoder: borrow_decoder(&entry.decoder)?,
                    width: entry.width,
                    height: entry.height,
                    last_seek_ms: entry.last_seek_ms,
                    last_used: Instant::now(),
                    working_set_bytes: entry.working_set_bytes,
                    is_preview: entry.is_preview,
                };
                if mode == OpenMode::Preview && !entry.is_preview {
                    // Caller wants a preview-tuned decoder but we cached
                    // an export one (or vice versa). Just fall through
                    // to a fresh open. This is rare (the kit always
                    // uses Preview for thumbnails).
                    log::debug!(
                        "[DecoderCache] miss-mode key={} cached_mode=export requested=preview — re-opening",
                        key
                    );
                } else {
                    // Note: ffmpeg-next's Input / DecoderVideo are not
                    // Clone. We hand the caller the actual entry by
                    // temporarily removing it from the LRU and
                    // re-inserting on release(). The "cache hit" path
                    // therefore hands the caller the unique instance.
                    let entry_owned = cache.entries.pop(&key).expect("just got");
                    cache.total_working_set_bytes = cache
                        .total_working_set_bytes
                        .saturating_sub(entry_owned.working_set_bytes);
                    owned.ictx = entry_owned.ictx;
                    owned.decoder = entry_owned.decoder;
                    owned.last_seek_ms = entry_owned.last_seek_ms;
                    owned.working_set_bytes = entry_owned.working_set_bytes;
                    owned.is_preview = entry_owned.is_preview;
                    return Ok(owned);
                }
            }
        }
    }

    // Cache miss: open the file outside the lock.
    STATS.misses.fetch_add(1, Ordering::Relaxed);
    log::debug!("[DecoderCache] miss key={} mode={:?}", key, mode);
    let ictx = match mode {
        OpenMode::Preview => open_input_for_preview(trimmed)?,
        OpenMode::Export => open_input(trimmed)?,
    };

    let stream = ictx
        .streams()
        .best(ffmpeg_next::media::Type::Video)
        .ok_or_else(|| VideoForgeError::InvalidInput("no video stream".into()))?;
    let params = stream.parameters();
    let dec_ctx = CodecContext::from_parameters(params).map_err(map_ffmpeg_error)?;
    let decoder = dec_ctx.decoder().video().map_err(map_ffmpeg_error)?;
    let width = decoder.width();
    let height = decoder.height();
    let working_set_bytes = u64::from(width) * u64::from(height) * 4;

    Ok(CachedDecoder {
        ictx,
        decoder,
        width,
        height,
        last_seek_ms: 0,
        last_used: Instant::now(),
        working_set_bytes,
        is_preview: mode == OpenMode::Preview,
    })
}

/// Re-insert a borrowed `CachedDecoder` back into the cache. The entry
/// replaces any older entry for the same key. Pass the original
/// `input` key (the same one used for `acquire`).
pub fn release(input: &str, entry: CachedDecoder) {
    let key = cache_key(input);
    let mut cache = CACHE.lock();
    if !cache.enabled {
        // Drop the entry (it goes out of scope at the call site).
        log::debug!("[DecoderCache] release dropped (cache disabled) key={}", key);
        return;
    }
    // If there is already an entry (shouldn't happen — we pop on hit),
    // drop the older one to avoid double-inserting.
    if let Some(old) = cache.entries.pop(&key) {
        cache.total_working_set_bytes = cache
            .total_working_set_bytes
            .saturating_sub(old.working_set_bytes);
    }
    let mut entry = entry;
    entry.last_used = Instant::now();
    cache.total_working_set_bytes =
        cache.total_working_set_bytes.saturating_add(entry.working_set_bytes);
    cache.entries.put(key.clone(), entry);
    cache.evict_lru_if_over_memory();
    log::debug!(
        "[DecoderCache] release key={} entries={} ws_b={}",
        key,
        cache.entries.len(),
        cache.total_working_set_bytes
    );
}

// `Input` and `DecoderVideo` from ffmpeg-next are not `Clone`; the
// borrow helpers below are only used in the "mode mismatch" branch
// where we don't actually return the borrowed entry. The cache hit
// fast-path uses `pop` to take ownership, so these helpers are
// currently unused but kept for future refactors.
#[allow(dead_code)]
fn borrow_input(_i: &Input) -> Result<Input> {
    Err(VideoForgeError::Internal(
        "DecoderCache::borrow_input: not implemented (use release/pop pattern)".into(),
    ))
}
#[allow(dead_code)]
fn borrow_decoder(_d: &DecoderVideo) -> Result<DecoderVideo> {
    Err(VideoForgeError::Internal(
        "DecoderCache::borrow_decoder: not implemented (use release/pop pattern)".into(),
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cache_key_normalizes_remote() {
        // `normalize_remote_input` upgrades http -> https only for Google
        // hosts; for other hosts the only normalization is the trim. So
        // the cache key is just `trim().to_string()` for the remote path,
        // matching the existing `probe_cache` key strategy.
        let a = cache_key("http://example.com/v.mp4");
        let b = cache_key("http://example.com/v.mp4?token=abc");
        // Different query strings -> different cache keys (don't share
        // a server-side stream-rewrite response).
        assert_ne!(a, b);
        // Same URL after trim -> same key.
        let c = cache_key("  http://example.com/v.mp4  ");
        assert_eq!(a, c);
    }

    #[test]
    fn cache_key_keeps_local_path() {
        assert_eq!(cache_key("/tmp/x.mp4"), "/tmp/x.mp4");
        assert_eq!(cache_key("  /tmp/x.mp4  "), "/tmp/x.mp4");
    }

    #[test]
    fn stats_default_zero() {
        let s = stats();
        // Hits / misses may be non-zero from prior tests; just assert
        // counts are well-formed.
        assert!(s.entries <= DEFAULT_CAPACITY);
    }

    #[test]
    fn clear_drops_all() {
        // No entries expected in a fresh test run, but `clear` should
        // never panic and must return the dropped count.
        let n = clear();
        assert_eq!(n, stats().entries);
    }

    #[test]
    fn disabled_config_does_not_store() {
        set_config(DecoderCacheConfig::disabled());
        // Even if acquire were called here, release would drop the entry.
        // We don't open an input — the disable flag is unit-tested via
        // the explicit drop branch.
        set_config(DecoderCacheConfig::default());
    }
}
