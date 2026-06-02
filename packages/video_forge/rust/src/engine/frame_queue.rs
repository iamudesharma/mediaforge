//! Bounded `FrameQueue<T>` for decoder→consumer handoff.
//!
//! Two modes, decided at construction:
//!
//! - [`FrameQueueMode::Fifo`] — classic bounded ring buffer. When the
//!   queue is full, the *oldest* frame is dropped and the new frame is
//!   appended. This is the right mode for sequential playback (a small
//!   head-of-line burst absorbed before the consumer catches up).
//!
//! - [`FrameQueueMode::LatestWins`] — capacity 1 effectively. Every
//!   new push replaces the existing element; the previous one is
//!   counted in `dropped_full`. `try_push` always succeeds. This is
//!   the right mode for seek-scrub (the user jumped to a new position;
//!   intermediate frames in the queue are noise — only the newest
//!   preview frame matters).
//!
//! Statistics (`pushed`, `dropped_full`, `popped`, `high_water`) are
//! atomic. The `Drop` impl emits a one-line summary tagged with the
//! queue's `tag` so the closing log line is grep-friendly.
//!
//! # Thread safety
//!
//! All methods take `&self`. The internal `VecDeque` is protected by
//! a `parking_lot::Mutex`. Atomic counters are lock-free.
//!
//! # Closing log line
//!
//! ```text
//! [FrameQueue playback] close pushed=N popped=N dropped_full=N high_water=N
//! ```

use std::collections::VecDeque;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::Duration;

use parking_lot::{Mutex, MutexGuard};

/// Queue mode. Decided at construction; immutable thereafter.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum FrameQueueMode {
    /// Classic bounded ring buffer; drop-oldest on full.
    Fifo { cap: usize },
    /// Capacity 1 effectively. New push always succeeds, replaces the
    /// existing element. The replaced element is counted in
    /// `dropped_full`.
    LatestWins,
}

impl FrameQueueMode {
    pub fn fifo(cap: usize) -> Self {
        Self::Fifo { cap: cap.max(1) }
    }
}

/// Bounded `FrameQueue<T>`.
pub struct FrameQueue<T> {
    mode: FrameQueueMode,
    inner: Mutex<VecDeque<T>>,
    pushed: AtomicU64,
    dropped_full: AtomicU64,
    popped: AtomicU64,
    high_water: AtomicU64,
    tag: String,
}

impl<T> FrameQueue<T> {
    /// Build a new queue. `tag` is used for the closing log line; it
    /// should be a short, stable identifier like `"playback"` or
    /// `"seek_preview"`.
    pub fn new(mode: FrameQueueMode, tag: impl Into<String>) -> Self {
        let tag = tag.into();
        let initial_cap = match mode {
            FrameQueueMode::Fifo { cap } => cap,
            FrameQueueMode::LatestWins => 1,
        };
        Self {
            mode,
            inner: Mutex::new(VecDeque::with_capacity(initial_cap)),
            pushed: AtomicU64::new(0),
            dropped_full: AtomicU64::new(0),
            popped: AtomicU64::new(0),
            high_water: AtomicU64::new(0),
            tag,
        }
    }

    pub fn mode(&self) -> FrameQueueMode {
        self.mode
    }
    pub fn tag(&self) -> &str {
        &self.tag
    }

    /// Push a frame. On a full `Fifo` queue, drops the oldest frame
    /// and returns `Ok(())`. On a `LatestWins` queue, always returns
    /// `Ok(())` and replaces the existing element. This method never
    /// returns `Err`.
    pub fn try_push(&self, t: T) {
        let mut guard = self.inner.lock();
        match self.mode {
            FrameQueueMode::Fifo { cap } => {
                while guard.len() >= cap {
                    guard.pop_front();
                    self.dropped_full.fetch_add(1, Ordering::Relaxed);
                }
                guard.push_back(t);
            }
            FrameQueueMode::LatestWins => {
                if guard.pop_front().is_some() {
                    self.dropped_full.fetch_add(1, Ordering::Relaxed);
                }
                guard.push_back(t);
            }
        }
        self.pushed.fetch_add(1, Ordering::Relaxed);
        self.update_high_water(guard.len());
    }

    /// Pop the front element. Returns `None` if empty.
    pub fn try_pop(&self) -> Option<T> {
        let mut guard = self.inner.lock();
        let v = guard.pop_front();
        if v.is_some() {
            self.popped.fetch_add(1, Ordering::Relaxed);
        }
        v
    }

    /// Pop the front element, blocking for up to `timeout` waiting
    /// for an element. Returns `None` on timeout. The wait is a
    /// primitive busy-loop on a `Mutex`; the consumer of this method
    /// is expected to be a single dedicated worker thread.
    pub fn pop_blocking(&self, timeout: Duration) -> Option<T> {
        let start = std::time::Instant::now();
        loop {
            {
                let mut guard = self.inner.lock();
                if let Some(v) = guard.pop_front() {
                    self.popped.fetch_add(1, Ordering::Relaxed);
                    return Some(v);
                }
            }
            if start.elapsed() >= timeout {
                return None;
            }
            // 100µs granularity is fine; the consumer is the playback
            // worker, not a real-time thread.
            std::thread::sleep(Duration::from_micros(100));
        }
    }

    /// Pop the front element, but only if `predicate(&t)` returns
    /// `true`. If the front element does not match, the queue is
    /// unchanged. The predicate runs under the queue lock; keep it
    /// cheap.
    ///
    /// Typical use: "give me the most recent frame whose PTS is at
    /// or after my target". The caller walks the queue from front
    /// (oldest) to back (newest) and pops the first matching one.
    /// This drains stale frames in the process.
    pub fn pop_if<F: Fn(&T) -> bool>(&self, predicate: F) -> Option<T> {
        let mut guard = self.inner.lock();
        // Find the *front* element that matches. Pop everything older
        // (counted as `dropped_full`).
        while let Some(front) = guard.front() {
            if predicate(front) {
                let v = guard.pop_front();
                if v.is_some() {
                    self.popped.fetch_add(1, Ordering::Relaxed);
                }
                return v;
            }
            guard.pop_front();
            self.dropped_full.fetch_add(1, Ordering::Relaxed);
        }
        None
    }

    /// Drain every element into `sink`. Returns the number drained.
    /// The sink's `clear()` is *not* called; the caller controls
    /// memory.
    pub fn drain_into(&self, sink: &mut Vec<T>) -> usize {
        let mut guard = self.inner.lock();
        let n = guard.len();
        sink.extend(std::mem::take(&mut *guard));
        if n > 0 {
            self.popped.fetch_add(n as u64, Ordering::Relaxed);
        }
        n
    }

    /// Current depth. O(1).
    pub fn len(&self) -> usize {
        self.inner.lock().len()
    }

    /// `true` if the queue is empty.
    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }

    /// `true` if the queue is at capacity (`Fifo` only; `LatestWins`
    /// is never "full" in the traditional sense).
    pub fn is_full(&self) -> bool {
        let cap = match self.mode {
            FrameQueueMode::Fifo { cap } => cap,
            FrameQueueMode::LatestWins => return false,
        };
        self.len() >= cap
    }

    /// Lock the queue for iteration. The caller must drop the guard
    /// promptly; long-held guards block `try_push` / `try_pop`.
    pub fn lock(&self) -> MutexGuard<'_, VecDeque<T>> {
        self.inner.lock()
    }

    /// Snapshot of the queue stats. The returned snapshot does *not*
    /// include the current depth; use [`len`](Self::len) for that.
    pub fn stats(&self) -> FrameQueueStats {
        FrameQueueStats {
            depth: self.len() as u64,
            pushed: self.pushed.load(Ordering::Relaxed),
            dropped_full: self.dropped_full.load(Ordering::Relaxed),
            popped: self.popped.load(Ordering::Relaxed),
            high_water: self.high_water.load(Ordering::Relaxed),
        }
    }

    fn update_high_water(&self, depth: usize) {
        let cur = self.high_water.load(Ordering::Relaxed);
        let depth_u64 = depth as u64;
        if depth_u64 > cur {
            // Best-effort CAS; contention is fine because monotonic
            // writes are idempotent.
            let _ = self
                .high_water
                .compare_exchange(cur, depth_u64, Ordering::Relaxed, Ordering::Relaxed);
        }
    }
}

impl<T> Drop for FrameQueue<T> {
    fn drop(&mut self) {
        let s = self.stats();
        log::info!(
            "[FrameQueue {}] close pushed={} popped={} dropped_full={} high_water={}",
            self.tag, s.pushed, s.popped, s.dropped_full, s.high_water
        );
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct FrameQueueStats {
    pub depth: u64,
    pub pushed: u64,
    pub dropped_full: u64,
    pub popped: u64,
    pub high_water: u64,
}

impl FrameQueueStats {
    /// Format for telemetry log lines.
    pub fn log_string(&self) -> String {
        format!(
            "depth={} pushed={} popped={} dropped_full={} high_water={}",
            self.depth, self.pushed, self.popped, self.dropped_full, self.high_water
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Arc;
    use std::thread;

    // -------- Fifo mode --------

    #[test]
    fn fifo_push_pop_preserves_order() {
        let q = FrameQueue::<u32>::new(FrameQueueMode::fifo(4), "test");
        q.try_push(1);
        q.try_push(2);
        q.try_push(3);
        assert_eq!(q.try_pop(), Some(1));
        assert_eq!(q.try_pop(), Some(2));
        assert_eq!(q.try_pop(), Some(3));
        assert_eq!(q.try_pop(), None);
    }

    #[test]
    fn fifo_full_drops_oldest() {
        let q = FrameQueue::<u32>::new(FrameQueueMode::fifo(2), "test");
        q.try_push(1);
        q.try_push(2);
        q.try_push(3); // should drop 1
        q.try_push(4); // should drop 2
        let mut got = Vec::new();
        q.drain_into(&mut got);
        assert_eq!(got, vec![3, 4]);
        assert_eq!(q.stats().dropped_full, 2);
    }

    #[test]
    fn fifo_capacity_at_least_one_even_if_zero_passed() {
        let q = FrameQueue::<u32>::new(FrameQueueMode::fifo(0), "test");
        q.try_push(1);
        q.try_push(2);
        // cap is clamped to ≥1
        assert_eq!(q.len(), 1);
        assert_eq!(q.stats().dropped_full, 1);
    }

    #[test]
    fn fifo_high_water_tracks_peak() {
        let q = FrameQueue::<u32>::new(FrameQueueMode::fifo(4), "test");
        q.try_push(1);
        q.try_push(2);
        q.try_push(3);
        assert_eq!(q.stats().high_water, 3);
        let _ = q.try_pop();
        let _ = q.try_pop();
        let _ = q.try_pop();
        assert_eq!(q.stats().high_water, 3, "high_water never decreases");
    }

    // -------- LatestWins mode --------

    #[test]
    fn latest_wins_always_succeeds() {
        let q = FrameQueue::<u32>::new(FrameQueueMode::LatestWins, "test");
        for i in 0..100 {
            q.try_push(i);
        }
        assert_eq!(q.len(), 1);
        assert_eq!(q.try_pop(), Some(99));
    }

    #[test]
    fn latest_wins_counts_replacement_as_drop() {
        let q = FrameQueue::<u32>::new(FrameQueueMode::LatestWins, "test");
        q.try_push(1);
        q.try_push(2);
        q.try_push(3);
        let s = q.stats();
        assert_eq!(s.pushed, 3);
        assert_eq!(s.dropped_full, 2); // 1 and 2 replaced
        assert_eq!(s.popped, 0);
    }

    #[test]
    fn latest_wins_is_never_full() {
        let q = FrameQueue::<u32>::new(FrameQueueMode::LatestWins, "test");
        q.try_push(1);
        assert!(!q.is_full());
    }

    // -------- pop_if --------

    #[test]
    fn pop_if_returns_first_match() {
        let q = FrameQueue::<u32>::new(FrameQueueMode::fifo(4), "test");
        for v in [1u32, 2, 3, 4] {
            q.try_push(v);
        }
        // Pop the first value >= 3 — drains 1 and 2 first
        let v = q.pop_if(|&x| x >= 3);
        assert_eq!(v, Some(3));
        assert_eq!(q.stats().dropped_full, 2);
        assert_eq!(q.try_pop(), Some(4));
    }

    #[test]
    fn pop_if_no_match_returns_none() {
        let q = FrameQueue::<u32>::new(FrameQueueMode::fifo(4), "test");
        q.try_push(1);
        q.try_push(2);
        let v = q.pop_if(|&x| x >= 5);
        assert_eq!(v, None);
        // Stale frames are still drained
        assert_eq!(q.stats().dropped_full, 2);
        assert!(q.is_empty());
    }

    // -------- pop_blocking --------

    #[test]
    fn pop_blocking_times_out_on_empty() {
        let q = FrameQueue::<u32>::new(FrameQueueMode::fifo(2), "test");
        let start = std::time::Instant::now();
        let v = q.pop_blocking(Duration::from_millis(50));
        assert_eq!(v, None);
        assert!(start.elapsed() >= Duration::from_millis(50));
    }

    #[test]
    fn pop_blocking_returns_immediately_when_available() {
        let q = Arc::new(FrameQueue::<u32>::new(FrameQueueMode::fifo(2), "test"));
        let q2 = q.clone();
        let h = thread::spawn(move || {
            std::thread::sleep(Duration::from_millis(20));
            q2.try_push(42);
        });
        let v = q.pop_blocking(Duration::from_secs(1));
        h.join().unwrap();
        assert_eq!(v, Some(42));
    }

    // -------- drain --------

    #[test]
    fn drain_into_preserves_order() {
        let q = FrameQueue::<u32>::new(FrameQueueMode::fifo(8), "test");
        for v in 0..5 {
            q.try_push(v);
        }
        let mut sink = Vec::new();
        let n = q.drain_into(&mut sink);
        assert_eq!(n, 5);
        assert_eq!(sink, vec![0, 1, 2, 3, 4]);
        assert!(q.is_empty());
    }

    #[test]
    fn drain_into_empty_returns_zero() {
        let q = FrameQueue::<u32>::new(FrameQueueMode::fifo(2), "test");
        let mut sink = Vec::new();
        let n = q.drain_into(&mut sink);
        assert_eq!(n, 0);
        assert!(sink.is_empty());
    }

    #[test]
    fn drain_into_appends_to_existing_sink() {
        let q = FrameQueue::<u32>::new(FrameQueueMode::fifo(4), "test");
        q.try_push(1);
        q.try_push(2);
        let mut sink = vec![10, 20];
        let n = q.drain_into(&mut sink);
        assert_eq!(n, 2);
        assert_eq!(sink, vec![10, 20, 1, 2]);
    }

    // -------- stats --------

    #[test]
    fn stats_counters_increment_correctly() {
        let q = FrameQueue::<u32>::new(FrameQueueMode::fifo(3), "test");
        q.try_push(1);
        q.try_push(2);
        q.try_push(3);
        q.try_push(4); // drop 1
        let _ = q.try_pop();
        let s = q.stats();
        assert_eq!(s.pushed, 4);
        assert_eq!(s.popped, 1);
        assert_eq!(s.dropped_full, 1);
        assert_eq!(s.depth, 2);
        assert_eq!(s.high_water, 3);
    }

    #[test]
    fn stats_log_string_contains_all_counters() {
        let s = FrameQueueStats {
            depth: 1,
            pushed: 10,
            dropped_full: 2,
            popped: 8,
            high_water: 4,
        };
        let s = s.log_string();
        assert!(s.contains("depth=1"));
        assert!(s.contains("pushed=10"));
        assert!(s.contains("popped=8"));
        assert!(s.contains("dropped_full=2"));
        assert!(s.contains("high_water=4"));
    }

    // -------- concurrent --------

    #[test]
    fn concurrent_push_pop_does_not_panic() {
        let q = Arc::new(FrameQueue::<u32>::new(FrameQueueMode::fifo(8), "test"));
        let mut handles = Vec::new();
        for t in 0..4 {
            let q2 = q.clone();
            handles.push(thread::spawn(move || {
                for i in 0..200 {
                    q2.try_push(t * 1000 + i);
                }
            }));
        }
        // Wait for all producers to finish first.
        for h in handles.drain(..) {
            h.join().unwrap();
        }
        // Now drain what's left (at most `cap` items).
        let mut got = 0u64;
        while let Some(_) = q.try_pop() {
            got += 1;
        }
        assert!(got <= 8);
        assert!(q.len() <= 8);
    }

    // -------- mode accessors --------

    #[test]
    fn mode_accessor_returns_constructor_value() {
        let q = FrameQueue::<u32>::new(FrameQueueMode::fifo(4), "test");
        assert_eq!(q.mode(), FrameQueueMode::Fifo { cap: 4 });
        let q = FrameQueue::<u32>::new(FrameQueueMode::LatestWins, "test");
        assert_eq!(q.mode(), FrameQueueMode::LatestWins);
    }

    #[test]
    fn tag_accessor_returns_constructor_value() {
        let q = FrameQueue::<u32>::new(FrameQueueMode::fifo(2), "playback");
        assert_eq!(q.tag(), "playback");
    }

    // -------- lock --------

    #[test]
    fn lock_provides_read_access() {
        let q = FrameQueue::<u32>::new(FrameQueueMode::fifo(2), "test");
        q.try_push(1);
        q.try_push(2);
        let g = q.lock();
        let v: Vec<u32> = g.iter().copied().collect();
        assert_eq!(v, vec![1, 2]);
    }
}
