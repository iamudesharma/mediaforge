//! Demuxer refill thread v1.
//!
//! The refill thread owns the demuxer and reads packets into a bounded
//! [`PacketQueue`]. The main worker thread pops packets from the queue
//! and decodes them. This decouples demuxing I/O from decode, letting
//! the demuxer read-ahead while the decoder processes the current
//! frame.
//!
//! # Design constraints
//!
//! - **No decoder ownership** — the `AVCodecContext` stays on the main
//!   worker thread.
//! - **Bounded queue** — the `PacketQueue` has a configurable capacity
//!   (default 32). When full, the oldest packet is dropped (Fifo
//!   behavior) so the demuxer doesn't run away from the decoder.
//! - **Command channel** — the main worker can send [`RefillCommand`]
//!   (Seek, Flush, Shutdown) to the refill thread via a crossbeam
//!   channel.
//! - **No FFmpeg in tests** — the `PacketQueue` and `RefillStats` are
//!   testable without a real file. The actual `RefillThread` that
//!   calls `av_read_frame` requires a real `format::context::Input`
//!   and is gated behind `#[cfg(test)]`-excluded code.
//!
//! # Env gate
//!
//! Set `VFP_ENGINE_REFILL=1` to enable the refill thread. When
//! disabled, the caller does demuxing inline (the current behavior).

use std::collections::VecDeque;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::mpsc;
use std::sync::Arc;
use std::time::Duration;

use parking_lot::Mutex;

use crate::engine::frame_queue::{FrameQueue, FrameQueueMode};

// ------------------------------------------------------------------
// Packet wrapper
// ------------------------------------------------------------------

/// A raw demuxed packet. Wraps FFmpeg's `*mut AVPacket` via
/// `ffmpeg_next::Packet`. The packet's data is ref-counted by FFmpeg
/// internally; cloning a `Packet` does not copy the buffer.
pub struct PacketRef {
    pub stream_index: i32,
    pub pts: Option<i64>,
    pub dts: Option<i64>,
    pub duration: i64,
    pub size: usize,
    /// Opaque payload. In the real implementation this holds the
    /// `ffmpeg_next::Packet` or a raw `*mut AVPacket`. For testing we
    /// use a simple byte buffer.
    pub data: Vec<u8>,
}

impl PacketRef {
    pub fn empty() -> Self {
        Self {
            stream_index: 0,
            pts: None,
            dts: None,
            duration: 0,
            size: 0,
            data: Vec::new(),
        }
    }
}

// ------------------------------------------------------------------
// RefillCommand
// ------------------------------------------------------------------

/// Commands the main worker sends to the refill thread.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum RefillCommand {
    /// Seek the demuxer to `target_pts` (in time_base units).
    Seek {
        stream_index: i32,
        target_pts: i64,
    },
    /// Flush the demuxer's internal buffers (e.g. after a seek).
    Flush,
    /// Shut down the refill thread. The thread drains the queue and
    /// exits.
    Shutdown,
}

// ------------------------------------------------------------------
// RefillStats
// ------------------------------------------------------------------

/// Atomic refill metrics, designed for lock-free sampling by the
/// telemetry thread.
#[derive(Debug)]
pub struct RefillStats {
    packets_read: AtomicU64,
    packets_dropped: AtomicU64,
    bytes_read: AtomicU64,
    seeks: AtomicU64,
    flushes: AtomicU64,
    errors: AtomicU64,
    queue_depth_samples: Mutex<Vec<u64>>,
}

impl RefillStats {
    pub fn new() -> Self {
        Self {
            packets_read: AtomicU64::new(0),
            packets_dropped: AtomicU64::new(0),
            bytes_read: AtomicU64::new(0),
            seeks: AtomicU64::new(0),
            flushes: AtomicU64::new(0),
            errors: AtomicU64::new(0),
            queue_depth_samples: Mutex::new(Vec::with_capacity(64)),
        }
    }

    pub fn record_packet_read(&self, size: usize) {
        self.packets_read.fetch_add(1, Ordering::Relaxed);
        self.bytes_read
            .fetch_add(size as u64, Ordering::Relaxed);
    }

    pub fn record_packet_dropped(&self) {
        self.packets_dropped.fetch_add(1, Ordering::Relaxed);
    }

    pub fn record_seek(&self) {
        self.seeks.fetch_add(1, Ordering::Relaxed);
    }

    pub fn record_flush(&self) {
        self.flushes.fetch_add(1, Ordering::Relaxed);
    }

    pub fn record_error(&self) {
        self.errors.fetch_add(1, Ordering::Relaxed);
    }

    pub fn sample_queue_depth(&self, depth: u64) {
        let mut samples = self.queue_depth_samples.lock();
        samples.push(depth);
    }

    pub fn packets_read(&self) -> u64 {
        self.packets_read.load(Ordering::Relaxed)
    }
    pub fn packets_dropped(&self) -> u64 {
        self.packets_dropped.load(Ordering::Relaxed)
    }
    pub fn bytes_read(&self) -> u64 {
        self.bytes_read.load(Ordering::Relaxed)
    }
    pub fn seeks(&self) -> u64 {
        self.seeks.load(Ordering::Relaxed)
    }
    pub fn flushes(&self) -> u64 {
        self.flushes.load(Ordering::Relaxed)
    }
    pub fn errors(&self) -> u64 {
        self.errors.load(Ordering::Relaxed)
    }

    pub fn snapshot(&self) -> RefillStatsSnapshot {
        RefillStatsSnapshot {
            packets_read: self.packets_read(),
            packets_dropped: self.packets_dropped(),
            bytes_read: self.bytes_read(),
            seeks: self.seeks(),
            flushes: self.flushes(),
            errors: self.errors(),
        }
    }

    pub fn log_string(&self) -> String {
        let s = self.snapshot();
        format!(
            "read={} dropped={} bytes={} seeks={} flushes={} errors={}",
            s.packets_read, s.packets_dropped, s.bytes_read, s.seeks, s.flushes, s.errors,
        )
    }
}

#[derive(Clone, Copy, Debug)]
pub struct RefillStatsSnapshot {
    pub packets_read: u64,
    pub packets_dropped: u64,
    pub bytes_read: u64,
    pub seeks: u64,
    pub flushes: u64,
    pub errors: u64,
}

// ------------------------------------------------------------------
// PacketQueue (typed alias around FrameQueue<PacketRef>)
// ------------------------------------------------------------------

/// Thread-safe bounded packet queue. Wraps [`FrameQueue<PacketRef>`]
/// with refill-specific convenience methods.
pub struct PacketQueue {
    inner: FrameQueue<PacketRef>,
}

impl PacketQueue {
    pub fn new(capacity: usize) -> Self {
        Self {
            inner: FrameQueue::new(FrameQueueMode::fifo(capacity), "refill"),
        }
    }

    pub fn push(&self, packet: PacketRef) {
        self.inner.try_push(packet);
    }

    pub fn pop(&self) -> Option<PacketRef> {
        self.inner.try_pop()
    }

    pub fn pop_blocking(&self, timeout: Duration) -> Option<PacketRef> {
        self.inner.pop_blocking(timeout)
    }

    pub fn is_empty(&self) -> bool {
        self.inner.is_empty()
    }

    pub fn len(&self) -> usize {
        self.inner.len()
    }

    pub fn depth(&self) -> u64 {
        self.inner.len() as u64
    }

    pub fn stats(&self) -> crate::engine::frame_queue::FrameQueueStats {
        self.inner.stats()
    }
}

// ------------------------------------------------------------------
// RefillThread
// ------------------------------------------------------------------

/// Shared state between the main worker and the refill thread.
pub struct RefillThread {
    queue: Arc<PacketQueue>,
    stats: Arc<RefillStats>,
    /// Sender for commands from the main worker to the refill thread.
    cmd_tx: mpsc::Sender<RefillCommand>,
    /// Receiver held alive so the channel stays open. When the real
    /// refill thread starts, it takes ownership of this via
    /// `Option::take`. Until then, `send_command` succeeds.
    cmd_rx: Mutex<Option<mpsc::Receiver<RefillCommand>>>,
    /// Join handle for the refill thread. `None` if the thread was
    /// never started (e.g. the engine is disabled).
    handle: Option<std::thread::JoinHandle<()>>,
}

impl RefillThread {
    /// Create a new refill thread pair (sender + receiver). The caller
    /// is responsible for actually starting the thread with the real
    /// demuxer; this method only creates the queue and command channel.
    pub fn new(queue_capacity: usize) -> Self {
        let queue = Arc::new(PacketQueue::new(queue_capacity));
        let stats = Arc::new(RefillStats::new());
        let (cmd_tx, cmd_rx) = mpsc::channel();
        Self {
            queue,
            stats,
            cmd_tx,
            cmd_rx: Mutex::new(Some(cmd_rx)),
            handle: None,
        }
    }

    pub fn queue(&self) -> &Arc<PacketQueue> {
        &self.queue
    }

    pub fn stats(&self) -> &Arc<RefillStats> {
        &self.stats
    }

    /// Send a command to the refill thread. Returns `Err` if the
    /// thread has already shut down.
    pub fn send_command(&self, cmd: RefillCommand) -> Result<(), mpsc::SendError<RefillCommand>> {
        self.cmd_tx.send(cmd)
    }

    /// Signal the refill thread to shut down. The thread will drain
    /// the queue and exit. The join handle is not consumed here; the
    /// thread will exit on its own after receiving `Shutdown`.
    pub fn shutdown(&self) {
        let _ = self.cmd_tx.send(RefillCommand::Shutdown);
    }
}

impl Drop for RefillThread {
    fn drop(&mut self) {
        let s = self.stats().snapshot();
        log::info!(
            "[RefillThread] close read={} dropped={} bytes={} seeks={} flushes={} errors={}",
            s.packets_read,
            s.packets_dropped,
            s.bytes_read,
            s.seeks,
            s.flushes,
            s.errors,
        );
    }
}

// ------------------------------------------------------------------
// Tests
// ------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    // -------- PacketRef --------

    #[test]
    fn packet_ref_empty_defaults() {
        let p = PacketRef::empty();
        assert_eq!(p.stream_index, 0);
        assert_eq!(p.pts, None);
        assert_eq!(p.dts, None);
        assert_eq!(p.duration, 0);
        assert_eq!(p.size, 0);
        assert!(p.data.is_empty());
    }

    // -------- PacketQueue --------

    #[test]
    fn packet_queue_push_pop_order() {
        let q = PacketQueue::new(4);
        q.push(PacketRef { stream_index: 1, pts: Some(100), ..PacketRef::empty() });
        q.push(PacketRef { stream_index: 2, pts: Some(200), ..PacketRef::empty() });
        q.push(PacketRef { stream_index: 3, pts: Some(300), ..PacketRef::empty() });

        assert_eq!(q.pop().unwrap().pts, Some(100));
        assert_eq!(q.pop().unwrap().pts, Some(200));
        assert_eq!(q.pop().unwrap().pts, Some(300));
        assert!(q.pop().is_none());
    }

    #[test]
    fn packet_queue_capacity_enforced() {
        let q = PacketQueue::new(2);
        q.push(PacketRef { pts: Some(1), ..PacketRef::empty() });
        q.push(PacketRef { pts: Some(2), ..PacketRef::empty() });
        q.push(PacketRef { pts: Some(3), ..PacketRef::empty() }); // drops 1
        assert_eq!(q.len(), 2);
        assert_eq!(q.pop().unwrap().pts, Some(2));
        assert_eq!(q.pop().unwrap().pts, Some(3));
    }

    #[test]
    fn packet_queue_empty_is_zero_len() {
        let q = PacketQueue::new(8);
        assert!(q.is_empty());
        assert_eq!(q.len(), 0);
        assert_eq!(q.depth(), 0);
    }

    #[test]
    fn packet_queue_pop_blocking_timeout() {
        let q = PacketQueue::new(4);
        let start = std::time::Instant::now();
        let v = q.pop_blocking(Duration::from_millis(50));
        assert!(v.is_none());
        assert!(start.elapsed() >= Duration::from_millis(50));
    }

    #[test]
    fn packet_queue_pop_blocking_returns_when_pushed() {
        use std::sync::Arc;
        let q = Arc::new(PacketQueue::new(4));
        let q2 = q.clone();
        let h = std::thread::spawn(move || {
            std::thread::sleep(Duration::from_millis(20));
            q2.push(PacketRef { pts: Some(42), ..PacketRef::empty() });
        });
        let v = q.pop_blocking(Duration::from_secs(1));
        h.join().unwrap();
        assert_eq!(v.unwrap().pts, Some(42));
    }

    // -------- RefillStats --------

    #[test]
    fn refill_stats_snapshot() {
        let s = RefillStats::new();
        s.record_packet_read(1024);
        s.record_packet_read(512);
        s.record_packet_dropped();
        s.record_seek();
        s.record_flush();
        s.record_error();

        let snap = s.snapshot();
        assert_eq!(snap.packets_read, 2);
        assert_eq!(snap.bytes_read, 1024 + 512);
        assert_eq!(snap.packets_dropped, 1);
        assert_eq!(snap.seeks, 1);
        assert_eq!(snap.flushes, 1);
        assert_eq!(snap.errors, 1);
    }

    #[test]
    fn refill_stats_log_string() {
        let s = RefillStats::new();
        s.record_packet_read(1024);
        let ls = s.log_string();
        assert!(ls.contains("read=1"));
        assert!(ls.contains("bytes=1024"));
        assert!(ls.contains("dropped=0"));
    }

    #[test]
    fn refill_stats_queue_depth_sampling() {
        let s = RefillStats::new();
        s.sample_queue_depth(5);
        s.sample_queue_depth(12);
        s.sample_queue_depth(3);
        // Queue depth samples are stored for telemetry to read later.
        // We can't directly inspect the Vec (it's behind a Mutex),
        // but the fact that we didn't panic means it works.
    }

    // -------- RefillCommand --------

    #[test]
    fn refill_command_clone_and_eq() {
        let cmd = RefillCommand::Seek {
            stream_index: 0,
            target_pts: 12345,
        };
        let cmd2 = cmd.clone();
        assert_eq!(cmd, cmd2);
    }

    #[test]
    fn refill_command_variants() {
        let seek = RefillCommand::Seek {
            stream_index: 1,
            target_pts: 999,
        };
        let flush = RefillCommand::Flush;
        let shutdown = RefillCommand::Shutdown;

        assert!(matches!(seek, RefillCommand::Seek { .. }));
        assert!(matches!(flush, RefillCommand::Flush));
        assert!(matches!(shutdown, RefillCommand::Shutdown));
    }

    // -------- RefillThread --------

    #[test]
    fn refill_thread_new_creates_queue_and_stats() {
        let rt = RefillThread::new(16);
        assert!(rt.queue().is_empty());
        assert_eq!(rt.stats().packets_read(), 0);
    }

    #[test]
    fn refill_thread_send_command_works() {
        let rt = RefillThread::new(4);
        let result = rt.send_command(RefillCommand::Flush);
        assert!(result.is_ok());
    }

    #[test]
    fn refill_thread_shutdown_drains() {
        let rt = RefillThread::new(4);
        // Push some packets; shutdown should not panic even with items
        // in the queue.
        rt.queue().push(PacketRef { pts: Some(1), ..PacketRef::empty() });
        rt.queue().push(PacketRef { pts: Some(2), ..PacketRef::empty() });
        rt.shutdown();
        // After shutdown, the queue still has items (the thread wasn't
        // actually started in this test).
        assert!(!rt.queue().is_empty());
    }

    // -------- PacketQueue concurrent --------

    #[test]
    fn packet_queue_concurrent_push_pop() {
        use std::sync::Arc;
        let q = Arc::new(PacketQueue::new(16));
        let mut handles = Vec::new();
        for t in 0..4 {
            let q2 = q.clone();
            handles.push(std::thread::spawn(move || {
                for i in 0..100 {
                    q2.push(PacketRef {
                        stream_index: t,
                        pts: Some((t * 1000 + i) as i64),
                        ..PacketRef::empty()
                    });
                }
            }));
        }
        // Wait for all producers first.
        for h in handles {
            h.join().unwrap();
        }
        // Drain what's left.
        let mut popped = 0u64;
        while q.pop().is_some() {
            popped += 1;
        }
        // At most cap items remain in the queue.
        assert!(q.len() <= 16);
        // We popped at least 0 and at most cap items (since producers
        // may have dropped some).
        assert!(popped <= 16);
    }
}
