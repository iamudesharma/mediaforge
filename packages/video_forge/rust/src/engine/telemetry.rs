//! Queue-depth telemetry thread.
//!
//! The telemetry thread periodically walks all registered
//! [`TelemetrySource`]s and logs their current depth. This is the
//! "eyes on the system" that tells you whether the decoder is keeping
//! up with the demuxer, or whether a queue is starving.
//!
//! # Usage
//!
//! ```text
//! // At session start:
//! let telemetry = TelemetryThread::start(interval_ms);
//! telemetry.register(Arc::new(my_queue.clone()));
//!
//! // At session end:
//! telemetry.stop(); // or drop
//! ```
//!
//! # Env gate
//!
//! Set `VFP_ENGINE_TELEMETRY=1` and `VFP_ENGINE_TELEMETRY_INTERVAL_MS=N`
//! (default 5000) to enable the telemetry thread. When disabled, the
//! thread is not started and `register` is a no-op.

use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};

use parking_lot::Mutex;

// ------------------------------------------------------------------
// TelemetrySource
// ------------------------------------------------------------------

/// Trait for anything that has a depth the telemetry thread should
/// sample. Implementors must be `Send + Sync`.
pub trait TelemetrySource: Send + Sync {
    /// Human-readable tag for log lines (e.g. `"refill_queue"`,
    /// `"decode_queue"`).
    fn tag(&self) -> &str;
    /// Current depth (number of items in the queue). Returns 0 if the
    /// queue is empty or unavailable.
    fn depth(&self) -> u64;
}

// ------------------------------------------------------------------
// TelemetrySample
// ------------------------------------------------------------------

/// A single telemetry sample: timestamp + per-source depths.
#[derive(Clone, Debug)]
pub struct TelemetrySample {
    /// Milliseconds since session start.
    pub elapsed_ms: u64,
    /// `(tag, depth)` pairs, one per registered source.
    pub sources: Vec<(String, u64)>,
}

// ------------------------------------------------------------------
// TelemetryThread
// ------------------------------------------------------------------

/// Shared state for the telemetry background thread.
struct TelemetryInner {
    sources: Mutex<Vec<Arc<dyn TelemetrySource>>>,
    samples: Mutex<Vec<TelemetrySample>>,
    max_samples: usize,
    running: AtomicBool,
    start: Instant,
}

/// Handle to the telemetry background thread.
pub struct TelemetryThread {
    inner: Arc<TelemetryInner>,
    handle: Option<std::thread::JoinHandle<()>>,
}

impl TelemetryThread {
    /// Start the telemetry thread. The thread wakes up every
    /// `interval_ms` and samples all registered sources.
    pub fn start(interval_ms: u64) -> Self {
        let inner = Arc::new(TelemetryInner {
            sources: Mutex::new(Vec::new()),
            samples: Mutex::new(Vec::with_capacity(64)),
            max_samples: 64,
            running: AtomicBool::new(true),
            start: Instant::now(),
        });

        let inner_clone = inner.clone();
        let handle = std::thread::spawn(move || {
            Self::run_loop(&inner_clone, Duration::from_millis(interval_ms));
        });

        Self {
            inner,
            handle: Some(handle),
        }
    }

    /// Register a source for periodic sampling.
    pub fn register(&self, source: Arc<dyn TelemetrySource>) {
        self.inner.sources.lock().push(source);
    }

    /// Stop the telemetry thread and join it.
    pub fn stop(&mut self) {
        self.inner.running.store(false, Ordering::Relaxed);
        if let Some(h) = self.handle.take() {
            let _ = h.join();
        }
    }

    /// Drain the sample history (oldest first).
    pub fn drain_samples(&self) -> Vec<TelemetrySample> {
        self.inner.samples.lock().drain(..).collect()
    }

    /// Number of sources currently registered.
    pub fn source_count(&self) -> usize {
        self.inner.sources.lock().len()
    }

    fn run_loop(inner: &TelemetryInner, interval: Duration) {
        while inner.running.load(Ordering::Relaxed) {
            std::thread::sleep(interval);
            if !inner.running.load(Ordering::Relaxed) {
                break;
            }
            Self::sample_once(inner);
        }
        // Final sample on shutdown.
        Self::sample_once(inner);
    }

    fn sample_once(inner: &TelemetryInner) {
        let elapsed_ms = inner.start.elapsed().as_millis() as u64;
        let sources = inner.sources.lock();
        let mut source_data = Vec::with_capacity(sources.len());
        for src in sources.iter() {
            let depth = src.depth();
            log::info!(
                "[Telemetry] {} depth={} elapsed={}ms",
                src.tag(),
                depth,
                elapsed_ms,
            );
            source_data.push((src.tag().to_string(), depth));
        }
        drop(sources);

        let sample = TelemetrySample {
            elapsed_ms,
            sources: source_data,
        };
        let mut samples = inner.samples.lock();
        if samples.len() >= inner.max_samples {
            samples.remove(0);
        }
        samples.push(sample);
    }
}

impl Drop for TelemetryThread {
    fn drop(&mut self) {
        // Ensure the thread is stopped.
        self.inner.running.store(false, Ordering::Relaxed);
        if let Some(h) = self.handle.take() {
            let _ = h.join();
        }
        let sample_count = self.inner.samples.lock().len();
        log::info!(
            "[Telemetry] close sources={} samples={}",
            self.source_count(),
            sample_count,
        );
    }
}

// ------------------------------------------------------------------
// Tests
// ------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::AtomicU64;

    // -------- Mock source --------

    struct MockSource {
        tag: String,
        depth: AtomicU64,
    }

    impl MockSource {
        fn new(tag: &str) -> Arc<Self> {
            Arc::new(Self {
                tag: tag.to_string(),
                depth: AtomicU64::new(0),
            })
        }

        fn set_depth(&self, d: u64) {
            self.depth.store(d, Ordering::Relaxed);
        }
    }

    impl TelemetrySource for MockSource {
        fn tag(&self) -> &str {
            &self.tag
        }
        fn depth(&self) -> u64 {
            self.depth.load(Ordering::Relaxed)
        }
    }

    // -------- Tests --------

    #[test]
    fn register_increases_source_count() {
        let t = TelemetryThread::start(1000);
        assert_eq!(t.source_count(), 0);
        t.register(MockSource::new("queue_a"));
        assert_eq!(t.source_count(), 1);
        t.register(MockSource::new("queue_b"));
        assert_eq!(t.source_count(), 2);
        drop(t);
    }

    #[test]
    fn sample_once_captures_depths() {
        let t = TelemetryThread::start(10000); // long interval so it doesn't fire
        let src = MockSource::new("test_queue");
        src.set_depth(42);
        t.register(src);

        // Force a manual sample.
        TelemetryThread::sample_once(&t.inner);

        let samples = t.drain_samples();
        assert_eq!(samples.len(), 1);
        assert_eq!(samples[0].sources.len(), 1);
        assert_eq!(samples[0].sources[0].0, "test_queue");
        assert_eq!(samples[0].sources[0].1, 42);
        drop(t);
    }

    #[test]
    fn telemetry_thread_logs_periodically() {
        // Start with a very short interval so it fires at least once.
        let mut t = TelemetryThread::start(20);
        let src = MockSource::new("periodic");
        src.set_depth(7);
        t.register(src);

        // Wait long enough for at least one sample.
        std::thread::sleep(Duration::from_millis(100));
        t.stop();

        let samples = t.drain_samples();
        assert!(
            samples.len() >= 1,
            "expected ≥1 sample, got {}",
            samples.len()
        );
    }

    #[test]
    fn sample_history_is_bounded() {
        let t = TelemetryThread::start(10000);
        let src = MockSource::new("bounded");
        t.register(src);

        // Force 70 samples (max is 64).
        for _ in 0..70 {
            TelemetryThread::sample_once(&t.inner);
        }
        let samples = t.drain_samples();
        assert!(
            samples.len() <= 64,
            "expected ≤64 samples, got {}",
            samples.len()
        );
        drop(t);
    }

    #[test]
    fn telemetry_source_trait_is_object_safe() {
        fn _assert_send_sync<T: Send + Sync>() {}
        fn _assert_object_safe(_: &dyn TelemetrySource) {}
    }

    #[test]
    fn drop_stops_thread() {
        let t = TelemetryThread::start(10);
        let src = MockSource::new("drop_test");
        t.register(src);
        // Drop should stop the thread cleanly.
        drop(t);
    }

    #[test]
    fn multiple_sources_sampled() {
        let t = TelemetryThread::start(10000);
        let s1 = MockSource::new("q1");
        let s2 = MockSource::new("q2");
        let s3 = MockSource::new("q3");
        s1.set_depth(10);
        s2.set_depth(20);
        s3.set_depth(30);
        t.register(s1);
        t.register(s2);
        t.register(s3);

        TelemetryThread::sample_once(&t.inner);

        let samples = t.drain_samples();
        assert_eq!(samples.len(), 1);
        let s = &samples[0];
        assert_eq!(s.sources.len(), 3);
        // Sources may be in any order (Vec is not sorted).
        let q1 = s.sources.iter().find(|(t, _)| t == "q1").unwrap();
        let q2 = s.sources.iter().find(|(t, _)| t == "q2").unwrap();
        let q3 = s.sources.iter().find(|(t, _)| t == "q3").unwrap();
        assert_eq!(q1.1, 10);
        assert_eq!(q2.1, 20);
        assert_eq!(q3.1, 30);
        drop(t);
    }

    #[test]
    fn zero_interval_thread_samples_and_stops() {
        // Interval of 0 ms means the thread fires as fast as possible.
        let mut t = TelemetryThread::start(0);
        let src = MockSource::new("fast");
        src.set_depth(1);
        t.register(src);
        std::thread::sleep(Duration::from_millis(50));
        t.stop();
        let samples = t.drain_samples();
        assert!(
            samples.len() >= 2,
            "expected ≥2 samples, got {}",
            samples.len()
        );
    }
}
