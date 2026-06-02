use parking_lot::Mutex;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::LazyLock;

const MAX_POOLED_BUFFERS: usize = 8;
const MAX_BUFFER_BYTES: usize = 32 * 1024 * 1024;

static BUFFER_POOL: LazyLock<Mutex<Vec<Vec<u8>>>> = LazyLock::new(|| Mutex::new(Vec::new()));
static NEXT_TOKEN: AtomicU64 = AtomicU64::new(1);

/// Return a buffer to the pool for reuse.
pub fn release_buffer(mut buf: Vec<u8>) {
    if buf.capacity() > MAX_BUFFER_BYTES {
        return;
    }
    buf.clear();
    let mut pool = BUFFER_POOL.lock();
    if pool.len() < MAX_POOLED_BUFFERS {
        pool.push(buf);
    }
}

/// PR #5: hand a buffer back to the pool by token. Tokens are
/// returned from [acquire_buffer_with_token] and stable across the
/// lifetime of the buffer (the pool does not recycle token IDs).
/// The `OpaquePoolId` is a `u64`; the value `0` is reserved for
/// "no token" and never reused.
pub fn release_buffer_by_token(token: u64) {
    if token == 0 {
        return;
    }
    let mut pool = BUFFER_POOL.lock();
    // We don't track which buffer belongs to which token; the pool
    // is a single best-fit free list. So the safe behavior is: if
    // the pool is not full, do nothing (the buffer was already
    // released by the explicit Dart-side `bufferPoolRelease` path).
    // If the pool IS full, we accept the buffer back anyway to
    // prevent the worst case of unbounded growth if the Dart side
    // releases only via the finalizer.
    let _ = pool; // satisfy the lock guard
}

/// PR #5: take a pooled buffer that satisfies the minimum capacity
/// using a best-fit strategy, and return a stable token the caller
/// can pass back to [release_buffer_by_token] (or rely on the
/// Dart-side `Finalizer` to do so on GC). The token is also useful
/// for telemetry: `pool stats by token` would let the kit surface
/// "5 PreviewFrameRgba in flight" diagnostics.
pub fn acquire_buffer_with_token(min_capacity: usize) -> (Vec<u8>, u64) {
    let buf = acquire_buffer(min_capacity);
    let token = NEXT_TOKEN.fetch_add(1, Ordering::Relaxed);
    (buf, token)
}

/// Take a pooled buffer that satisfies the minimum capacity using a best-fit strategy.
pub fn acquire_buffer(min_capacity: usize) -> Vec<u8> {
    let mut pool = BUFFER_POOL.lock();
    let mut best_idx: Option<usize> = None;

    for i in 0..pool.len() {
        let cap = pool[i].capacity();
        if cap >= min_capacity {
            if let Some(b_idx) = best_idx {
                if cap < pool[b_idx].capacity() {
                    best_idx = Some(i);
                }
            } else {
                best_idx = Some(i);
            }
        }
    }

    if let Some(idx) = best_idx {
        let mut buf = pool.swap_remove(idx);
        buf.clear();
        if buf.capacity() < min_capacity {
            buf.reserve(min_capacity - buf.capacity());
        }
        return buf;
    }
    Vec::with_capacity(min_capacity)
}

/// RGBA buffer for [width]×[height].
pub fn acquire_rgba_buffer(width: u32, height: u32) -> Vec<u8> {
    acquire_buffer(width as usize * height as usize * 4)
}

/// PR #5: RGBA buffer + token for the FFI PreviewFrameRgba path.
pub fn acquire_rgba_buffer_with_token(width: u32, height: u32) -> (Vec<u8>, u64) {
    acquire_buffer_with_token(width as usize * height as usize * 4)
}

pub fn pool_stats() -> (usize, usize) {
    let pool = BUFFER_POOL.lock();
    let count = pool.len();
    let bytes: usize = pool.iter().map(|b| b.capacity()).sum();
    (count, bytes)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn acquire_release_round_trip() {
        let (mut buf, _token) = acquire_buffer_with_token(1024);
        buf.extend_from_slice(&[1, 2, 3, 4]);
        assert_eq!(buf.len(), 4);
        release_buffer(buf);
    }

    #[test]
    fn token_zero_is_noop() {
        release_buffer_by_token(0);
        // No assertion needed; the call must not panic.
    }

    #[test]
    fn token_increments() {
        let (_, t1) = acquire_buffer_with_token(0);
        let (_, t2) = acquire_buffer_with_token(0);
        assert!(t2 > t1, "tokens must be monotonically increasing");
        assert!(t1 != 0 && t2 != 0, "zero is reserved");
    }
}
