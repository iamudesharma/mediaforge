use parking_lot::Mutex;
use std::sync::LazyLock;

const MAX_POOLED_BUFFERS: usize = 8;
const MAX_BUFFER_BYTES: usize = 32 * 1024 * 1024;

static BUFFER_POOL: LazyLock<Mutex<Vec<Vec<u8>>>> = LazyLock::new(|| Mutex::new(Vec::new()));

/// Return a buffer to the pool for reuse when pooling is enabled.
pub fn release_buffer(mut buf: Vec<u8>) {
    if !crate::runtime::pool_enabled() {
        return;
    }
    if buf.capacity() > MAX_BUFFER_BYTES {
        return;
    }
    buf.clear();
    let mut pool = BUFFER_POOL.lock();
    if pool.len() < MAX_POOLED_BUFFERS {
        pool.push(buf);
    }
}

/// Take a pooled buffer that satisfies the minimum capacity using a best-fit strategy.
pub fn acquire_buffer(min_capacity: usize) -> Vec<u8> {
    if !crate::runtime::pool_enabled() {
        return Vec::with_capacity(min_capacity);
    }

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

/// RGBA buffer for [width]×[height], reusing the pool when enabled.
#[allow(dead_code)]
pub fn acquire_rgba_buffer(width: u32, height: u32) -> Vec<u8> {
    acquire_buffer(width as usize * height as usize * 4)
}

pub fn pool_stats() -> (usize, usize) {
    if !crate::runtime::pool_enabled() {
        return (0, 0);
    }
    let pool = BUFFER_POOL.lock();
    let count = pool.len();
    let bytes: usize = pool.iter().map(|b| b.capacity()).sum();
    (count, bytes)
}
