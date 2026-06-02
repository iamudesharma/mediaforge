use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, OnceLock};
use std::time::{Duration, Instant};

use flutter_rust_bridge::frb;
use parking_lot::{Condvar, Mutex};
use tokio::sync::{OwnedSemaphorePermit, Semaphore};
use uuid::Uuid;

use crate::error::{Result, VideoForgeError};
use crate::types::{JobResult, ProgressEvent, ProcessingPhase};

#[derive(Clone)]
pub struct CancellationToken {
    inner: Arc<AtomicBool>,
}

impl CancellationToken {
    pub fn new() -> Self {
        Self {
            inner: Arc::new(AtomicBool::new(false)),
        }
    }

    pub fn cancel(&self) {
        self.inner.store(true, Ordering::SeqCst);
    }

    pub fn is_cancelled(&self) -> bool {
        self.inner.load(Ordering::SeqCst)
    }
}

struct JobRecord {
    token: CancellationToken,
    result: Mutex<Option<std::result::Result<JobResult, VideoForgeError>>>,
    /// Signalled by [JobRegistry::complete]. Paired with [JobRecord::result]
    /// so a waiter blocked in [JobRegistry::wait_result] wakes up
    /// immediately rather than polling every 50 ms.
    ready: Condvar,
}

pub struct JobRegistry {
    jobs: Mutex<HashMap<String, Arc<JobRecord>>>,
    semaphore: Arc<Semaphore>,
}

impl JobRegistry {
    pub fn new(max_concurrent: usize) -> Self {
        Self {
            jobs: Mutex::new(HashMap::new()),
            semaphore: Arc::new(Semaphore::new(max_concurrent)),
        }
    }

    pub fn max_concurrent_default() -> usize {
        if cfg!(any(target_os = "android", target_os = "ios")) {
            2
        } else {
            4
        }
    }

    pub async fn acquire_permit(
        &self,
    ) -> std::result::Result<OwnedSemaphorePermit, VideoForgeError> {
        self.semaphore
            .clone()
            .acquire_owned()
            .await
            .map_err(|_| VideoForgeError::Internal("job queue closed".into()))
    }

    pub fn register(&self) -> (String, CancellationToken) {
        let id = Uuid::new_v4().to_string();
        let token = CancellationToken::new();
        let record = Arc::new(JobRecord {
            token: token.clone(),
            result: Mutex::new(None),
            ready: Condvar::new(),
        });
        self.jobs.lock().insert(id.clone(), record);
        (id, token)
    }

    pub fn complete(
        &self,
        job_id: &str,
        result: std::result::Result<JobResult, VideoForgeError>,
    ) {
        let jobs = self.jobs.lock();
        if let Some(record) = jobs.get(job_id) {
            *record.result.lock() = Some(result);
            // Wake every thread blocked in `wait_result` for this job.
            // (Multiple waiters are rare but allowed: callers may share
            // a job_id across multiple Dart isolates — see
            // `video_forge_kit` for the pattern.)
            record.ready.notify_all();
        }
    }

    pub fn cancel(&self, job_id: &str) -> bool {
        if let Some(record) = self.jobs.lock().get(job_id) {
            record.token.cancel();
            true
        } else {
            false
        }
    }

    pub fn token(&self, job_id: &str) -> Option<CancellationToken> {
        self.jobs.lock().get(job_id).map(|r| r.token.clone())
    }

    pub fn wait_result(&self, job_id: &str, timeout: Duration) -> Result<JobResult> {
        let deadline = Instant::now() + timeout;
        // First check: avoid taking the condvar wait if the result is
        // already present (e.g. caller polls after completion).
        {
            let jobs = self.jobs.lock();
            if let Some(record) = jobs.get(job_id) {
                if let Some(result) = record.result.lock().take() {
                    return result;
                }
            } else {
                return Err(VideoForgeError::JobNotFound(job_id.to_string()));
            }
        }

        // Wait path: we need a stable reference to the JobRecord that
        // survives any concurrent `cleanup()` call (which removes the
        // record from the map and drops the Arc).
        let record = {
            let jobs = self.jobs.lock();
            match jobs.get(job_id) {
                Some(r) => r.clone(),
                None => return Err(VideoForgeError::JobNotFound(job_id.to_string())),
            }
        };

        // Wait on the per-record condvar. The condvar is paired with
        // `record.result`, but we only need to wake on `complete()`, so
        // we lock `record.result` briefly to be a valid
        // `Condvar::wait_while` guard.
        let mut result_guard = record.result.lock();
        loop {
            if let Some(result) = result_guard.take() {
                return result;
            }
            let now = Instant::now();
            if now >= deadline {
                return Err(VideoForgeError::Internal("job wait timeout".into()));
            }
            let remaining = deadline.saturating_duration_since(now);
            // `wait_for` returns `WaitTimeoutResult`: `Timeout` means
            // the timeout fired, `(_) => ...` means signalled. Either
            // way, the loop re-checks the result + deadline.
            let _ = record.ready.wait_for(&mut result_guard, remaining);
            // Re-check above; the timeout branch is caught by the
            // `now >= deadline` check.
            if Instant::now() >= deadline {
                return Err(VideoForgeError::Internal("job wait timeout".into()));
            }
        }
    }

    pub fn cleanup(&self, job_id: &str) {
        self.jobs.lock().remove(job_id);
    }

    pub fn active_count(&self) -> usize {
        self.jobs
            .lock()
            .values()
            .filter(|r| r.result.lock().is_none())
            .count()
    }
}

static REGISTRY: OnceLock<JobRegistry> = OnceLock::new();

pub fn global_registry() -> &'static JobRegistry {
    REGISTRY.get_or_init(|| JobRegistry::new(JobRegistry::max_concurrent_default()))
}

pub fn registry() -> &'static JobRegistry {
    global_registry()
}

#[frb(ignore)]
pub fn make_cancelled_event(job_id: &str) -> ProgressEvent {
    ProgressEvent {
        job_id: job_id.to_string(),
        phase: ProcessingPhase::Cancelled,
        percent: 0.0,
        frame: 0,
        fps: 0.0,
        eta_ms: 0,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::types::JobResult;
    use std::sync::Arc;
    use std::thread;
    use std::time::Duration;

    /// Build a registry-backed job and assert that a waiter wakes up
    /// promptly when `complete` is signalled. The previous
    /// `std::thread::sleep(50ms)` polling would have added at least
    /// 50 ms of latency; the condvar path should wake in single-digit ms.
    #[test]
    fn wait_result_wakes_immediately_on_complete() {
        // Use a fresh registry (not the global one) to avoid leaking
        // test jobs into a long-lived process.
        let reg = Arc::new(JobRegistry::new(2));
        let (job_id, _token) = reg.register();

        let reg_wait = reg.clone();
        let job_id_wait = job_id.clone();
        let waiter = thread::spawn(move || {
            let start = Instant::now();
            let r = reg_wait.wait_result(&job_id_wait, Duration::from_secs(2));
            (r, start.elapsed())
        });

        // Give the waiter a head start so it is definitely parked on
        // the condvar before we signal.
        thread::sleep(Duration::from_millis(20));
        reg.complete(&job_id, Ok(JobResult::Empty));

        let (result, waited) = waiter.join().expect("waiter thread");
        assert!(result.is_ok(), "expected Ok, got {:?}", result);
        // Old polling implementation waited 50 ms minimum; the condvar
        // path wakes in single-digit ms. Allow a generous 100 ms budget
        // for CI noise / scheduling jitter — the important guarantee
        // is that it does NOT depend on the 50 ms poll cadence.
        assert!(
            waited < Duration::from_millis(100),
            "wait_result took {:?}, expected < 100 ms (condvar path)",
            waited
        );
    }

    #[test]
    fn wait_result_returns_job_not_found() {
        let reg = JobRegistry::new(1);
        let err = reg
            .wait_result("nonexistent", Duration::from_millis(50))
            .unwrap_err();
        assert!(matches!(err, VideoForgeError::JobNotFound(_)));
    }

    #[test]
    fn wait_result_returns_timeout() {
        let reg = JobRegistry::new(1);
        let (job_id, _t) = reg.register();
        // Never call complete. The condvar should fire the timeout.
        let err = reg
            .wait_result(&job_id, Duration::from_millis(30))
            .unwrap_err();
        assert!(matches!(err, VideoForgeError::Internal(_)));
    }

    #[test]
    fn active_count_zero_after_cleanup() {
        let reg = JobRegistry::new(2);
        let (id, _t) = reg.register();
        assert_eq!(reg.active_count(), 1);
        reg.cleanup(&id);
        assert_eq!(reg.active_count(), 0);
    }
}
