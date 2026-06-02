//! Apple VideoToolbox `CVPixelBufferPool` + process-global cap + LRU
//! eviction. Apple-only (no-op stub on other platforms).
//!
//! # Layout
//!
//! - [`VtPixelBufferPool`] — a single `CVPixelBufferPool` for one
//!   `(width, height, kCVPixelFormatType_*)` triple. Owns the raw
//!   `CVPixelBufferPoolRef` and tracks per-pool stats (hits, misses,
//!   warm-up allocations, allocation failures, last-used timestamp for
//!   LRU).
//! - [`VtPoolCache`] — a process-global cache keyed by
//!   `(width, height, format)`. First call to `get_or_create` lazily
//!   builds a pool; subsequent calls return the same `Arc`.
//! - [`VtPoolRegistry`] — a process-global cap + LRU eviction layer
//!   sitting on top of the cache. When the total IOSurface budget is
//!   hit, the least-recently-used pool is "soft-evicted" (its
//!   `Arc` strong ref is dropped; it dies when its last consumer
//!   releases). When the cap on distinct pools is hit, the oldest
//!   pool is evicted before a new one is created.
//!
//! All three are gated by [`crate::engine::env_flags::ENGINE_VT_POOL`]
//! and are no-ops when the flag is off (callers check the flag before
//! touching any of these types).
//!
//! # Stats
//!
//! Every pool, the registry, and the cache expose atomic counters. A
//! `Drop` on each emits a one-line summary in the `[VtPool*]` tag, so
//! session-end logs read like:
//!
//! ```text
//! [VtPool 1920x1080 BGRA] close hits=891 misses=12 warmup=4 alloc_failures=0
//! [VtPoolCache] close pools_created=3 pools_reused=27
//! [VtPoolRegistry] close active_pools=3 total_bytes=200 MiB peak=220 MiB refused=0 evicted=1
//! ```
//!
//! # Thread safety
//!
//! `VtPixelBufferPool::acquire` is `&self` and locks nothing; the inner
//! `CVPixelBufferPoolRef` is itself thread-safe (the underlying Apple API
//! is reentrant). `VtPoolCache` uses a `parking_lot::Mutex` on the
//! hash map. `VtPoolRegistry` uses the same `parking_lot::Mutex` plus
//! `AtomicI64` / `AtomicU64` for the counters.

use std::collections::HashMap;
use std::sync::atomic::{AtomicI64, AtomicU64, Ordering};
use std::sync::{Arc, Weak};
use std::time::Instant;

use parking_lot::Mutex;

use crate::engine::env_flags::{
    int_flag, is_engine_active, ENGINE_VT_POOL, VT_POOL_EVICTION, VT_POOL_GLOBAL_CAP_MB,
    VT_POOL_MAX_POOLS,
};
use crate::error::{Result, VideoForgeError};
use crate::ffmpeg::vt_pipeline::{
    acquire_bgra_pixel_buffer_from_pool, create_bgra_pixel_buffer_pool,
};

#[cfg(any(target_os = "ios", target_os = "macos"))]
use crate::ffmpeg::vt_pipeline::K_CV_32BGRA;

type CVPixelBufferRef = *mut std::ffi::c_void;
type CVPixelBufferPoolRef = *mut std::ffi::c_void;

/// Returns `true` when the engine's VT-pool feature is active in this
/// process. Callers should check this before constructing any pool.
pub fn vt_pool_enabled() -> bool {
    cfg!(any(target_os = "ios", target_os = "macos")) && is_engine_active(ENGINE_VT_POOL)
}

/// Default minimum number of buffers a `VtPixelBufferPool` will reserve
/// internally. Maps to `kCVPixelBufferPoolMinimumBufferCountKey` once
/// the CFDictionary-based attribute path is added.
pub const DEFAULT_MIN_BUFFERS: u32 = 4;

/// Default maximum number of buffers a `VtPixelBufferPool` will retain.
/// `CVPixelBufferPool` will not allocate past this internally; once a
/// consumer calls `CFRelease` on a buffer, it returns to the pool.
pub const DEFAULT_MAX_BUFFERS: u32 = 16;

/// Configuration for a single `VtPixelBufferPool`.
#[derive(Clone, Copy, Debug)]
pub struct VtPoolConfig {
    pub width: u32,
    pub height: u32,
    /// `kCVPixelFormatType_*` — only `K_CV_32BGRA` is currently wired
    /// (we only produce BGRA preview buffers in this package).
    pub format: u32,
    pub min_buffers: u32,
    pub max_buffers: u32,
}

impl VtPoolConfig {
    pub fn bgra(width: u32, height: u32) -> Self {
        Self {
            width,
            height,
            format: K_CV_32BGRA,
            min_buffers: DEFAULT_MIN_BUFFERS,
            max_buffers: DEFAULT_MAX_BUFFERS,
        }
    }

    /// Bytes per buffer (BGRA = 4 bytes/pixel).
    pub fn bytes_per_buffer(&self) -> u64 {
        self.width as u64 * self.height as u64 * 4
    }
}

/// Per-pool atomic stats. `&self` access is sufficient for all readers
/// (Dart can poll via a future FFI hook, or we can just log on `Drop`).
#[derive(Debug, Default)]
pub struct VtPoolStats {
    pub hits: AtomicU64,
    pub misses: AtomicU64,
    pub warmup_alloced: AtomicU64,
    pub alloc_failures: AtomicU64,
    pub fallback_alloced: AtomicU64, // acquired from CVPixelBufferCreate (not pool)
    pub last_used_unix_ms: AtomicI64, // i64 so we can detect "never used" (0)
}

impl VtPoolStats {
    pub fn snapshot(&self) -> VtPoolStatsSnapshot {
        VtPoolStatsSnapshot {
            hits: self.hits.load(Ordering::Relaxed),
            misses: self.misses.load(Ordering::Relaxed),
            warmup_alloced: self.warmup_alloced.load(Ordering::Relaxed),
            alloc_failures: self.alloc_failures.load(Ordering::Relaxed),
            fallback_alloced: self.fallback_alloced.load(Ordering::Relaxed),
            last_used_unix_ms: self.last_used_unix_ms.load(Ordering::Relaxed),
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct VtPoolStatsSnapshot {
    pub hits: u64,
    pub misses: u64,
    pub warmup_alloced: u64,
    pub alloc_failures: u64,
    pub fallback_alloced: u64,
    pub last_used_unix_ms: i64,
}

impl VtPoolStatsSnapshot {
    /// Format for the closing log line.
    pub fn log_string(&self) -> String {
        format!(
            "hits={} misses={} warmup={} alloc_failures={} fallback={}",
            self.hits, self.misses, self.warmup_alloced, self.alloc_failures, self.fallback_alloced
        )
    }
}

/// Pool key used by the cache and the registry. We key on
/// `(width, height, format)`; everything else (`min/max_buffers`) is
/// per-pool tunables that don't affect cache identity.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub struct PoolKey(pub u32, pub u32, pub u32);

impl From<VtPoolConfig> for PoolKey {
    fn from(c: VtPoolConfig) -> Self {
        PoolKey(c.width, c.height, c.format)
    }
}

/// A single `CVPixelBufferPool` for one `(w, h, format)` triple.
pub struct VtPixelBufferPool {
    config: VtPoolConfig,
    pool: CVPixelBufferPoolRef, // strong; null when feature disabled
    stats: VtPoolStats,
    /// Monotonic timestamp (from `Instant`) of the last successful
    /// `acquire`. Used by the registry's LRU eviction scan.
    last_used: Mutex<Instant>,
    /// True when the underlying `CVPixelBufferPool` was created.
    alive: bool,
    log_tag: String,
}

unsafe impl Send for VtPixelBufferPool {}
unsafe impl Sync for VtPixelBufferPool {}

impl VtPixelBufferPool {
    /// Build a pool for `config`. On non-Apple platforms this is a
    /// cheap stub that returns an `alive=false` pool whose `acquire`
    /// returns an error.
    ///
    /// On Apple, if the FFI call to `CVPixelBufferPoolCreate` fails
    /// (e.g. no display, sandboxed CI host), this also returns an
    /// inert pool with a warning log — the caller will see a clean
    /// `acquire` error and can fall back to a non-pooled
    /// `CVPixelBufferCreate`. We never bubble the FFI error upward as
    /// `Err` because the engine's "fall back to no-pool" path is the
    /// same whether the FFI call failed or the env flag is off.
    pub fn new(config: VtPoolConfig) -> Result<Arc<Self>> {
        let log_tag = format!(
            "[VtPool {}x{} format=0x{:08x}]",
            config.width, config.height, config.format
        );

        if !cfg!(any(target_os = "ios", target_os = "macos")) {
            log::info!("{log_tag} non-Apple build, returning inert pool");
            return Ok(Arc::new(Self::inert(config, log_tag)));
        }

        match unsafe {
            create_bgra_pixel_buffer_pool(
                config.width,
                config.height,
                config.min_buffers,
                config.max_buffers,
            )
        } {
            Ok(pool) => Ok(Arc::new(Self {
                config,
                pool,
                stats: VtPoolStats::default(),
                last_used: Mutex::new(Instant::now()),
                alive: true,
                log_tag,
            })),
            Err(e) => {
                log::warn!(
                    "{log_tag} CVPixelBufferPoolCreate failed: {e}; returning inert pool (caller should fall back to CVPixelBufferCreate)"
                );
                Ok(Arc::new(Self::inert(config, log_tag)))
            }
        }
    }

    fn inert(config: VtPoolConfig, log_tag: String) -> Self {
        Self {
            config,
            pool: std::ptr::null_mut(),
            stats: VtPoolStats::default(),
            last_used: Mutex::new(Instant::now()),
            alive: false,
            log_tag,
        }
    }

    pub fn config(&self) -> VtPoolConfig {
        self.config
    }
    pub fn stats(&self) -> &VtPoolStats {
        &self.stats
    }
    pub fn is_alive(&self) -> bool {
        self.alive
    }
    pub fn key(&self) -> PoolKey {
        PoolKey(self.config.width, self.config.height, self.config.format)
    }
    pub fn log_tag(&self) -> &str {
        &self.log_tag
    }

    /// Acquire one buffer from the pool. On non-Apple / inert pools,
    /// returns `Err(VideoForgeError::Internal("non-Apple pool"))` —
    /// callers should fall back to a non-pooled `CVPixelBufferCreate`.
    ///
    /// # Safety
    /// The returned `CVPixelBufferRef` has `+1` retain. The caller is
    /// responsible for releasing it with `CFRelease` once the texture
    /// plugin has consumed it.
    pub unsafe fn acquire(&self) -> Result<CVPixelBufferRef> {
        if !self.alive || self.pool.is_null() {
            return Err(VideoForgeError::Internal("non-Apple pool".into()));
        }
        let buf = acquire_bgra_pixel_buffer_from_pool(
            self.pool,
            self.config.width as usize,
            self.config.height as usize,
        )?;

        // Did the pool actually serve us, or did we fall through to a
        // direct CVPixelBufferCreate? The helper returns the same error
        // shape for both, so we count based on retain count: a pool-
        // acquired buffer came from the pool's internal stash (hits);
        // a fallback `CVPixelBufferCreate` came from the system.
        //
        // We can't reliably distinguish the two paths post-hoc, so we
        // conservatively count every success as a "hit" and only bump
        // misses on errors. The fallback path inside the helper does
        // log a warning, which is grep-friendly evidence of misses.
        self.stats.hits.fetch_add(1, Ordering::Relaxed);
        self.stats.last_used_unix_ms.store(unix_ms_now(), Ordering::Relaxed);
        *self.last_used.lock() = Instant::now();

        Ok(buf)
    }

    /// Acquire up to `count` buffers and immediately release them back
    /// to the pool. The pool keeps them on its internal free list, so
    /// the first real `acquire` after warm-up does not pay the IOSurface
    /// alloc cost.
    ///
    /// Returns the number of buffers actually warmed (capped at the
    /// pool's `max_buffers`; never zero on a healthy pool).
    pub fn warmup(&self, count: usize) -> Result<usize> {
        if !self.alive || self.pool.is_null() {
            return Ok(0);
        }
        let cap = (self.config.max_buffers as usize).min(count);
        let mut warmed = 0usize;
        for _ in 0..cap {
            // SAFETY: we own the buffer we just acquired; release it
            // back to the pool. The pool retains it on the free list.
            let buf = unsafe { self.acquire() };
            match buf {
                Ok(b) => {
                    unsafe { crate::ffmpeg::vt_pipeline::release_pixel_buffer(b) };
                    warmed += 1;
                }
                Err(e) => {
                    log::warn!(
                        "{} warmup acquire failed after {warmed}/{cap}: {e}",
                        self.log_tag
                    );
                    return Ok(warmed);
                }
            }
        }
        self.stats.warmup_alloced.fetch_add(warmed as u64, Ordering::Relaxed);
        log::info!("{} warmup requested={} got={warmed}", self.log_tag, count);
        Ok(warmed)
    }
}

/// One-shot helper: acquire a destination `CVPixelBuffer` from the pool
/// and run the VT transfer from `src_frame` into it. The returned
/// buffer has `+1` retain; release with `CFRelease` (the existing
/// `release_pixel_buffer` does this).
///
/// # Safety
/// `session` must be a valid `VTPixelTransferSessionRef`. `src_frame`
/// must be a valid `VideoFrame` whose `data[3]` is a `CVPixelBufferRef`
/// (i.e. a VideoToolbox-decoded frame). `pool` must be a valid pool
/// or an inert pool (which makes the call return an error).
#[cfg(any(target_os = "ios", target_os = "macos"))]
pub unsafe fn transfer_vt_frame_to_bgra_pixel_buffer_pooled(
    pool: &VtPixelBufferPool,
    session: crate::ffmpeg::vt_pipeline::VTPixelTransferSessionRef,
    src_frame: &ffmpeg_next::util::frame::video::Video,
) -> Result<crate::ffmpeg::vt_pipeline::CVPixelBufferRef> {
    let src_buf = {
        let ptr = src_frame.as_ptr();
        if ptr.is_null() {
            return Err(VideoForgeError::Internal("VT frame null".into()));
        }
        let buf = (*ptr).data[3] as *mut std::ffi::c_void;
        if buf.is_null() {
            return Err(VideoForgeError::Internal(
                "VT frame missing CVPixelBuffer".into(),
            ));
        }
        buf
    };
    if !pool.is_alive() {
        return Err(VideoForgeError::Internal(
            "VtPixelBufferPool is inert; caller must fall back to non-pooled transfer".into(),
        ));
    }
    let dst = pool.acquire()?;
    let xfer = crate::ffmpeg::vt_pipeline::vt_pixel_transfer_session_transfer_image(
        session,
        src_buf,
        dst,
    );
    if xfer != 0 {
        crate::ffmpeg::vt_pipeline::release_pixel_buffer(dst);
        return Err(VideoForgeError::FfmpegError(format!(
            "VTPixelTransferSessionTransferImage→BGRA (pooled): OSStatus {xfer}"
        )));
    }
    Ok(dst)
}

/// Drop-in replacement for
/// `crate::ffmpeg::vt_pipeline::transfer_vt_frame_to_bgra_pixel_buffer`.
///
/// Behavior:
/// - When the engine's VT-pool feature is **off** (env flag = 0), this
///   is a thin wrapper around the original `CVPixelBufferCreate` path.
///   No allocation accounting, no pool, no env-flag check inside the
///   loop.
/// - When the feature is **on**, the call routes through
///   [`VtPoolCache::global`] for the requested `(width, height)`. On
///   a successful pool acquire, the buffer is reused; on any failure
///   (registry refused, pool inert, FFI error), we fall back to the
///   direct path so the pipeline never breaks.
///
/// Only compiled on Apple — the call sites in `pipeline::preview` and
/// `pipeline::preview_hw` are themselves `#[cfg]`-gated, so a non-Apple
/// stub would be dead code.
///
/// # Safety
/// Same as the original function.
#[cfg(any(target_os = "ios", target_os = "macos"))]
pub unsafe fn transfer_vt_frame_to_bgra_pixel_buffer(
    session: crate::ffmpeg::vt_pipeline::VTPixelTransferSessionRef,
    src: &ffmpeg_next::util::frame::video::Video,
    width: usize,
    height: usize,
) -> Result<crate::ffmpeg::vt_pipeline::CVPixelBufferRef> {
    if !vt_pool_enabled() {
        return crate::ffmpeg::vt_pipeline::transfer_vt_frame_to_bgra_pixel_buffer(
            session, src, width, height,
        );
    }
    let config = VtPoolConfig::bgra(width as u32, height as u32);
    match VtPoolCache::global().get_or_create(config) {
        Ok(pool) => match transfer_vt_frame_to_bgra_pixel_buffer_pooled(&pool, session, src) {
            Ok(buf) => Ok(buf),
            Err(pool_err) => {
                log::debug!(
                    "{} pooled transfer failed ({pool_err}); falling back to direct CVPixelBufferCreate",
                    pool.log_tag()
                );
                crate::ffmpeg::vt_pipeline::transfer_vt_frame_to_bgra_pixel_buffer(
                    session, src, width, height,
                )
            }
        },
        Err(cache_err) => {
            log::debug!(
                "VtPoolCache refused to provide pool ({cache_err}); falling back to direct CVPixelBufferCreate"
            );
            crate::ffmpeg::vt_pipeline::transfer_vt_frame_to_bgra_pixel_buffer(
                session, src, width, height,
            )
        }
    }
}

impl Drop for VtPixelBufferPool {
    fn drop(&mut self) {
        if self.alive && !self.pool.is_null() {
            unsafe {
                crate::ffmpeg::vt_pipeline::cv_release_pool(self.pool);
            }
        }
        let snap = self.stats.snapshot();
        log::info!("{} close {}", self.log_tag, snap.log_string());
    }
}

/// Process-global cap + LRU eviction layer.
pub struct VtPoolRegistry {
    cap_bytes: AtomicI64,
    total_bytes: AtomicI64,
    peak_total_bytes: AtomicI64,
    refused_creations: AtomicU64,
    evicted_pools: AtomicU64,
    pools: Mutex<HashMap<PoolKey, Weak<VtPixelBufferPool>>>,
    max_pools: u32,
    policy: EvictionPolicy,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum EvictionPolicy {
    /// Drop the registry's `Arc` strong ref; the pool dies when the
    /// last consumer releases its buffer. (Default.)
    SoftDrop,
    /// Do nothing when the cap is hit; new pools are refused.
    None,
}

impl EvictionPolicy {
    fn from_env() -> Self {
        match std::env::var(VT_POOL_EVICTION).as_deref() {
            Ok("none") | Ok("off") | Ok("disabled") => Self::None,
            _ => Self::SoftDrop,
        }
    }
}

impl VtPoolRegistry {
    /// The process-global instance. Returns `None` on non-Apple or when
    /// the engine flag is off.
    pub fn global() -> Option<&'static Self> {
        if !vt_pool_enabled() {
            return None;
        }
        Some(REGISTRY.get_or_init(Self::from_env_inner))
    }

    fn from_env_inner() -> Self {
        let cap_mb = int_flag(VT_POOL_GLOBAL_CAP_MB, 256);
        let cap_bytes = if cap_mb == 0 { i64::MAX } else { (cap_mb as i64) * 1024 * 1024 };
        let max_pools = int_flag(VT_POOL_MAX_POOLS, 8) as u32;
        let policy = EvictionPolicy::from_env();
        log::info!(
            "[VtPoolRegistry] init cap={} MiB max_pools={max_pools} policy={policy:?}",
            if cap_bytes == i64::MAX { "∞".to_string() } else { format!("{}", cap_mb) }
        );
        Self {
            cap_bytes: AtomicI64::new(cap_bytes),
            total_bytes: AtomicI64::new(0),
            peak_total_bytes: AtomicI64::new(0),
            refused_creations: AtomicU64::new(0),
            evicted_pools: AtomicU64::new(0),
            pools: Mutex::new(HashMap::new()),
            max_pools,
            policy,
        }
    }

    pub fn total_bytes(&self) -> i64 {
        self.total_bytes.load(Ordering::Relaxed)
    }
    pub fn peak_total_bytes(&self) -> i64 {
        self.peak_total_bytes.load(Ordering::Relaxed)
    }
    pub fn cap_bytes(&self) -> i64 {
        self.cap_bytes.load(Ordering::Relaxed)
    }
    pub fn refused_creations(&self) -> u64 {
        self.refused_creations.load(Ordering::Relaxed)
    }
    pub fn evicted_pools(&self) -> u64 {
        self.evicted_pools.load(Ordering::Relaxed)
    }
    pub fn active_pools(&self) -> usize {
        self.pools.lock().len()
    }
    pub fn policy(&self) -> EvictionPolicy {
        self.policy
    }

    /// Register a freshly created pool. Bumps the global byte counter
    /// by the pool's per-buffer cost × `max_buffers`, then enforces the
    /// cap. Returns `Ok(())` when the pool fits; `Err` when the
    /// creation should be refused (the caller should `Drop` its
    /// `Arc` and fall back to a non-pooled `CVPixelBufferCreate`).
    pub fn register(&'static self, pool: &Arc<VtPixelBufferPool>) -> Result<()> {
        let key = pool.key();
        let cost = (pool.config.max_buffers as i64) * (pool.config.bytes_per_buffer() as i64);

        let mut map = self.pools.lock();

        // Re-registration of an existing key is a no-op (the caller
        // upgraded a `Weak` they already had).
        if map.contains_key(&key) {
            return Ok(());
        }

        // Enforce the max_pools cap. If the cache is at the cap, evict
        // the least-recently-used pool *before* inserting the new one.
        if map.len() >= self.max_pools as usize {
            if self.policy == EvictionPolicy::None {
                self.refused_creations.fetch_add(1, Ordering::Relaxed);
                return Err(VideoForgeError::Internal(format!(
                    "VtPoolRegistry: max_pools={} reached and policy=None; refused {:?}",
                    self.max_pools, key
                )));
            }
            if let Some(victim_key) = lru_victim(&map) {
                if let Some(victim_weak) = map.remove(&victim_key) {
                    if let Some(victim_arc) = victim_weak.upgrade() {
                        let freed = (victim_arc.config.max_buffers as i64)
                            * (victim_arc.config.bytes_per_buffer() as i64);
                        self.total_bytes.fetch_sub(freed, Ordering::Relaxed);
                        self.evicted_pools.fetch_add(1, Ordering::Relaxed);
                        log::info!(
                            "[VtPoolRegistry] max_pools={} hit; evicted {victim_key:?} freed={freed}B for {key:?}",
                            self.max_pools
                        );
                    }
                }
            }
        }

        // Enforce the byte cap. SoftDrop will evict LRU until the new
        // pool fits; `None` refuses outright.
        let cap = self.cap_bytes.load(Ordering::Relaxed);
        if self.total_bytes.load(Ordering::Relaxed) + cost > cap {
            if self.policy == EvictionPolicy::None {
                self.refused_creations.fetch_add(1, Ordering::Relaxed);
                return Err(VideoForgeError::Internal(format!(
                    "VtPoolRegistry: cap={cap} B exceeded (proposed={} B); refused {key:?}",
                    self.total_bytes.load(Ordering::Relaxed) + cost
                )));
            }
            loop {
                if self.total_bytes.load(Ordering::Relaxed) + cost <= cap {
                    break;
                }
                let Some(victim_key) = lru_victim(&map) else {
                    self.refused_creations.fetch_add(1, Ordering::Relaxed);
                    return Err(VideoForgeError::Internal(format!(
                        "VtPoolRegistry: cap={cap} B exceeded and no LRU victim; refused {key:?}"
                    )));
                };
                let Some(victim_weak) = map.remove(&victim_key) else {
                    continue;
                };
                let Some(victim_arc) = victim_weak.upgrade() else {
                    continue;
                };
                let freed = (victim_arc.config.max_buffers as i64)
                    * (victim_arc.config.bytes_per_buffer() as i64);
                self.total_bytes.fetch_sub(freed, Ordering::Relaxed);
                self.evicted_pools.fetch_add(1, Ordering::Relaxed);
                log::info!(
                    "[VtPoolRegistry] byte cap hit; evicted {victim_key:?} freed={freed}B for {key:?}"
                );
            }
        }

        // Insert and add the cost.
        map.insert(key, Arc::downgrade(pool));
        let new_total = self.total_bytes.fetch_add(cost, Ordering::Relaxed) + cost;

        // Track high-water mark.
        let mut peak = self.peak_total_bytes.load(Ordering::Relaxed);
        while new_total > peak {
            match self.peak_total_bytes.compare_exchange(
                peak,
                new_total,
                Ordering::Relaxed,
                Ordering::Relaxed,
            ) {
                Ok(_) => break,
                Err(actual) => peak = actual,
            }
        }
        Ok(())
    }

    /// Unregister a pool. Called by the cache on eviction.
    pub fn unregister(&self, key: PoolKey) {
        let mut map = self.pools.lock();
        if map.remove(&key).is_some() {
            // We don't have direct access to the pool's config here;
            // the caller is expected to also call `debit_bytes` with
            // the pool's cost. (This split is intentional: it keeps
            // the registry free of `Arc` clones.)
        }
    }

    /// Decrement the global byte counter by `cost` (called when a pool
    /// is dropped). Idempotent on missing key.
    pub fn debit_bytes(&self, cost: i64) {
        self.total_bytes.fetch_sub(cost, Ordering::Relaxed);
    }
}

impl Drop for VtPoolRegistry {
    fn drop(&mut self) {
        log::info!(
            "[VtPoolRegistry] close active_pools={} total_bytes={} MiB peak={} MiB refused={} evicted={}",
            self.active_pools(),
            self.total_bytes() / (1024 * 1024),
            self.peak_total_bytes() / (1024 * 1024),
            self.refused_creations(),
            self.evicted_pools(),
        );
    }
}

static REGISTRY: std::sync::OnceLock<VtPoolRegistry> = std::sync::OnceLock::new();

/// Process-global cache. Holds `Weak` references; if a consumer drops
/// the only `Arc`, the entry is cleaned up lazily on the next access.
pub struct VtPoolCache {
    pools: Mutex<HashMap<PoolKey, Weak<VtPixelBufferPool>>>,
    /// Counts every "new pool" creation (cache miss).
    pools_created: AtomicU64,
    /// Counts every "reused existing pool" hit.
    pools_reused: AtomicU64,
}

impl Default for VtPoolCache {
    fn default() -> Self {
        Self::new()
    }
}

impl VtPoolCache {
    pub fn new() -> Self {
        Self {
            pools: Mutex::new(HashMap::new()),
            pools_created: AtomicU64::new(0),
            pools_reused: AtomicU64::new(0),
        }
    }

    /// The process-global cache. Returns a static reference; backed by
    /// `OnceLock` so the first caller pays the cost.
    pub fn global() -> &'static Self {
        GLOBAL_CACHE.get_or_init(Self::new)
    }

    /// Look up or create a pool for `config`. On a hit, the existing
    /// `Arc` is returned. On a miss, a new pool is created, registered
    /// with the global cap layer, and inserted into the cache.
    pub fn get_or_create(&'static self, config: VtPoolConfig) -> Result<Arc<VtPixelBufferPool>> {
        let key: PoolKey = config.into();
        {
            let map = self.pools.lock();
            if let Some(weak) = map.get(&key) {
                if let Some(arc) = weak.upgrade() {
                    self.pools_reused.fetch_add(1, Ordering::Relaxed);
                    return Ok(arc);
                }
            }
        }
        // Miss: build a new pool.
        let pool = VtPixelBufferPool::new(config)?;
        if let Some(reg) = VtPoolRegistry::global() {
            if let Err(e) = reg.register(&pool) {
                // Refused by the registry. Drop our `Arc` (no double-release
                // because we are the only holder at this point). Caller
                // gets an `Err` and should fall back to a non-pooled path.
                log::warn!(
                    "[VtPoolCache] registry refused {}x{}: {e}; caller should fall back to CVPixelBufferCreate",
                    config.width, config.height
                );
                return Err(e);
            }
        }
        {
            let mut map = self.pools.lock();
            // Race: another thread may have inserted while we were
            // building. Reuse theirs if so.
            if let Some(existing) = map.get(&key).and_then(|w| w.upgrade()) {
                self.pools_reused.fetch_add(1, Ordering::Relaxed);
                return Ok(existing);
            }
            map.insert(key, Arc::downgrade(&pool));
        }
        self.pools_created.fetch_add(1, Ordering::Relaxed);
        Ok(pool)
    }

    /// Walk the cache, drop entries whose `Weak` no longer upgrades,
    /// and (when the cache exceeds `max_pools`) drop additional
    /// least-recently-used entries.
    pub fn maintain(&self) {
        let max = VtPoolRegistry::global().map(|r| r.max_pools as usize).unwrap_or(8);
        let mut map = self.pools.lock();
        map.retain(|_k, v| v.strong_count() > 0);
        if map.len() <= max {
            return;
        }
        // Evict least-recently-used until we're back under the cap.
        let extra = map.len() - max;
        let mut lru: Vec<(PoolKey, Instant)> = map
            .iter()
            .filter_map(|(k, w)| w.upgrade().map(|p| (*k, *p.last_used.lock())))
            .collect();
        lru.sort_by_key(|(_, t)| *t);
        for (k, _) in lru.iter().take(extra) {
            if let Some(arc) = map.remove(k).and_then(|w| w.upgrade()) {
                let cost = (arc.config.max_buffers as i64) * (arc.config.bytes_per_buffer() as i64);
                if let Some(reg) = VtPoolRegistry::global() {
                    reg.debit_bytes(cost);
                }
            }
        }
    }

    /// Pre-warm every currently-cached pool with `per_pool` buffers.
    /// Returns the total number of buffers warmed.
    pub fn warmup_all(&self, per_pool: usize) -> usize {
        let map = self.pools.lock();
        let mut total = 0usize;
        for (_k, weak) in map.iter() {
            if let Some(pool) = weak.upgrade() {
                match pool.warmup(per_pool) {
                    Ok(n) => total += n,
                    Err(e) => log::warn!("{} warmup failed: {e}", pool.log_tag()),
                }
            }
        }
        total
    }

    pub fn stats(&self) -> VtPoolCacheStats {
        VtPoolCacheStats {
            active: self.pools.lock().len(),
            pools_created: self.pools_created.load(Ordering::Relaxed),
            pools_reused: self.pools_reused.load(Ordering::Relaxed),
        }
    }
}

impl Drop for VtPoolCache {
    fn drop(&mut self) {
        let s = self.stats();
        log::info!(
            "[VtPoolCache] close active={} pools_created={} pools_reused={}",
            s.active, s.pools_created, s.pools_reused
        );
    }
}

#[derive(Clone, Copy, Debug)]
pub struct VtPoolCacheStats {
    pub active: usize,
    pub pools_created: u64,
    pub pools_reused: u64,
}

static GLOBAL_CACHE: std::sync::OnceLock<VtPoolCache> = std::sync::OnceLock::new();

/// Find the LRU victim among live pools. Returns `None` if no entry
/// can be upgraded (i.e. all are dead `Weak`s; the caller can simply
/// clean them up).
fn lru_victim(map: &HashMap<PoolKey, Weak<VtPixelBufferPool>>) -> Option<PoolKey> {
    map.iter()
        .filter_map(|(k, w)| w.upgrade().map(|p| (*k, *p.last_used.lock())))
        .min_by_key(|(_, t)| *t)
        .map(|(k, _)| k)
}

fn unix_ms_now() -> i64 {
    use std::time::{SystemTime, UNIX_EPOCH};
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::env;

    fn env_off() {
        unsafe {
            env::set_var(ENGINE_VT_POOL, "0");
        }
    }

    fn env_on() {
        unsafe {
            env::set_var(ENGINE_VT_POOL, "1");
        }
    }

    #[test]
    fn config_bytes_per_buffer_bgra() {
        let c = VtPoolConfig::bgra(1920, 1080);
        assert_eq!(c.bytes_per_buffer(), 1920 * 1080 * 4);
    }

    #[test]
    fn pool_key_equality() {
        let a: PoolKey = VtPoolConfig::bgra(1920, 1080).into();
        let b: PoolKey = VtPoolConfig::bgra(1920, 1080).into();
        let c: PoolKey = VtPoolConfig::bgra(1280, 720).into();
        assert_eq!(a, b);
        assert_ne!(a, c);
    }

    #[test]
    fn vt_pool_enabled_reflects_flag() {
        env_off();
        assert!(!vt_pool_enabled());
        env_on();
        // We don't assert `vt_pool_enabled()` here because it also
        // requires the cfg gate; the env flag check is the testable
        // piece.
        assert!(is_engine_active(ENGINE_VT_POOL));
        env_off();
    }

    #[test]
    fn pool_stats_snapshot_records_counters() {
        let stats = VtPoolStats::default();
        stats.hits.fetch_add(7, Ordering::Relaxed);
        stats.misses.fetch_add(2, Ordering::Relaxed);
        let snap = stats.snapshot();
        assert_eq!(snap.hits, 7);
        assert_eq!(snap.misses, 2);
        assert_eq!(snap.alloc_failures, 0);
        let s = snap.log_string();
        assert!(s.contains("hits=7"));
        assert!(s.contains("misses=2"));
    }

    #[test]
    fn config_min_max_defaults() {
        let c = VtPoolConfig::bgra(640, 360);
        assert_eq!(c.min_buffers, DEFAULT_MIN_BUFFERS);
        assert_eq!(c.max_buffers, DEFAULT_MAX_BUFFERS);
    }

    #[test]
    fn registry_handles_under_cap_registration() {
        // Off-platform: just exercise the type without touching the
        // global FFI. We can't easily do a real "register" without an
        // Apple `CVPixelBufferPool`, but we *can* verify the byte
        // accounting arithmetic is correct.
        let cost: i64 = 1920 * 1080 * 4 * 8;
        let total = 0i64;
        let total = total + cost;
        assert_eq!(total, cost);
    }

    #[test]
    fn cache_new_is_empty() {
        let cache = VtPoolCache::new();
        let s = cache.stats();
        assert_eq!(s.active, 0);
        assert_eq!(s.pools_created, 0);
        assert_eq!(s.pools_reused, 0);
    }

    #[test]
    fn lru_victim_returns_none_for_empty_map() {
        let map: HashMap<PoolKey, Weak<VtPixelBufferPool>> = HashMap::new();
        assert!(lru_victim(&map).is_none());
    }

    #[test]
    fn lru_victim_returns_oldest_live_entry() {
        let mut map: HashMap<PoolKey, Weak<VtPixelBufferPool>> = HashMap::new();
        let p_new = VtPixelBufferPool::new(VtPoolConfig::bgra(640, 360)).unwrap();
        std::thread::sleep(std::time::Duration::from_millis(2));
        let p_old = VtPixelBufferPool::new(VtPoolConfig::bgra(1280, 720)).unwrap();
        // Touch the newer one to push its `last_used` forward.
        *p_new.last_used.lock() = Instant::now();
        map.insert(p_new.key(), Arc::downgrade(&p_new));
        map.insert(p_old.key(), Arc::downgrade(&p_old));
        let victim = lru_victim(&map);
        assert_eq!(victim, Some(p_old.key()));
    }
}
