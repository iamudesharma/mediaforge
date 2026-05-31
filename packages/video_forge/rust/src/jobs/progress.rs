use std::time::{Duration, Instant};

use crate::frb_generated::StreamSink;

use crate::types::{ProcessingPhase, ProgressEvent};

const MIN_INTERVAL: Duration = Duration::from_millis(250);

pub struct ProgressReporter {
    job_id: String,
    sink: Option<StreamSink<ProgressEvent>>,
    last_emit: Instant,
    last_percent: f32,
}

impl ProgressReporter {
    pub fn new(job_id: String, sink: StreamSink<ProgressEvent>) -> Self {
        Self {
            job_id,
            sink: Some(sink),
            last_emit: Instant::now() - MIN_INTERVAL,
            last_percent: -1.0,
        }
    }

    /// Progress reporting without a Dart stream (CLI / tests).
    pub fn noop(job_id: impl Into<String>) -> Self {
        Self {
            job_id: job_id.into(),
            sink: None,
            last_emit: Instant::now() - MIN_INTERVAL,
            last_percent: -1.0,
        }
    }

    pub fn emit(
        &mut self,
        phase: ProcessingPhase,
        percent: f32,
        frame: u64,
        fps: f32,
        eta_ms: u64,
        force: bool,
    ) {
        let now = Instant::now();
        let percent_clamped = percent.clamp(0.0, 1.0);
        let should_emit = force
            || now.duration_since(self.last_emit) >= MIN_INTERVAL
            || (percent_clamped - self.last_percent).abs() >= 0.05
            || matches!(
                phase,
                ProcessingPhase::Done | ProcessingPhase::Cancelled | ProcessingPhase::Failed
            );

        if !should_emit {
            return;
        }

        self.last_emit = now;
        self.last_percent = percent_clamped;
        if let Some(sink) = &self.sink {
            let _ = sink.add(ProgressEvent {
                job_id: self.job_id.clone(),
                phase,
                percent: percent_clamped,
                frame,
                fps,
                eta_ms,
            });
        }
    }

    pub fn done(&mut self) {
        self.emit(ProcessingPhase::Done, 1.0, 0, 0.0, 0, true);
    }

    pub fn cancelled(&mut self) {
        self.emit(ProcessingPhase::Cancelled, 0.0, 0, 0.0, 0, true);
    }

    pub fn failed(&mut self) {
        self.emit(ProcessingPhase::Failed, 0.0, 0, 0.0, 0, true);
    }
}
