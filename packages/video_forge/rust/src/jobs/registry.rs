use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, OnceLock};
use std::time::{Duration, Instant};

use flutter_rust_bridge::frb;
use parking_lot::Mutex;
use tokio::sync::{OwnedSemaphorePermit, Semaphore};
use uuid::Uuid;

use crate::error::{Result, VideoProcessorError};
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
    result: Mutex<Option<std::result::Result<JobResult, VideoProcessorError>>>,
    started_at: Instant,
}

pub struct JobRegistry {
    jobs: Mutex<HashMap<String, JobRecord>>,
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
    ) -> std::result::Result<OwnedSemaphorePermit, VideoProcessorError> {
        self.semaphore
            .clone()
            .acquire_owned()
            .await
            .map_err(|_| VideoProcessorError::Internal("job queue closed".into()))
    }

    pub fn register(&self) -> (String, CancellationToken) {
        let id = Uuid::new_v4().to_string();
        let token = CancellationToken::new();
        self.jobs.lock().insert(
            id.clone(),
            JobRecord {
                token: token.clone(),
                result: Mutex::new(None),
                started_at: Instant::now(),
            },
        );
        (id, token)
    }

    pub fn complete(
        &self,
        job_id: &str,
        result: std::result::Result<JobResult, VideoProcessorError>,
    ) {
        if let Some(record) = self.jobs.lock().get(job_id) {
            *record.result.lock() = Some(result);
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
        loop {
            {
                let jobs = self.jobs.lock();
                if let Some(record) = jobs.get(job_id) {
                    if let Some(result) = record.result.lock().take() {
                        return result;
                    }
                } else {
                    return Err(VideoProcessorError::JobNotFound(job_id.to_string()));
                }
            }
            if Instant::now() >= deadline {
                return Err(VideoProcessorError::Internal("job wait timeout".into()));
            }
            std::thread::sleep(Duration::from_millis(50));
        }
    }

    pub fn cleanup(&self, job_id: &str) {
        self.jobs.lock().remove(job_id);
    }

    pub fn active_count(&self) -> usize {
        self.jobs.lock().len()
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
