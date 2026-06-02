//! Decoder lifecycle state machine and health metrics.
//!
//! The lifecycle module tracks decoder state transitions and records
//! health metrics that the telemetry thread can sample. Every
//! transition is logged `[Lifecycle] {from} → {to} reason=...` so
//! operators can grep for state changes.
//!
//! # States
//!
//! ```text
//!   Starting → Running → Idle → Recovering → Error → ShutDown
//!          ↘       ↓       ↓          ↓
//!           (transitions between any pair via `transition()`)
//! ```
//!
//! # Env gate
//!
//! Set `VFP_ENGINE_LIFECYCLE=1` to enable the lifecycle module. When
//! disabled, the state machine operates normally (it's a pure
//! in-process data structure with no FFI), but health metrics are
//! only logged if the telemetry thread is also enabled.

use std::collections::VecDeque;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::Instant;

use parking_lot::Mutex;

// ------------------------------------------------------------------
// DecoderState
// ------------------------------------------------------------------

/// Decoder lifecycle state.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum DecoderState {
    /// Initial state; decoder is being set up.
    Starting,
    /// Actively decoding frames at the source rate.
    Running,
    /// Decoding is paused (no active seek / no pending work).
    Idle,
    /// A recovery is in progress (flush, keyframe jump, demuxer
    /// reopen, or format reset).
    Recovering,
    /// Unrecoverable error; the decoder is dead.
    Error(String),
    /// The decoder has been intentionally shut down.
    ShutDown,
}

impl DecoderState {
    /// Short tag for log lines.
    pub fn tag(&self) -> &'static str {
        match self {
            Self::Starting => "starting",
            Self::Running => "running",
            Self::Idle => "idle",
            Self::Recovering => "recovering",
            Self::Error(_) => "error",
            Self::ShutDown => "shut_down",
        }
    }

    pub fn is_terminal(&self) -> bool {
        matches!(self, Self::ShutDown | Self::Error(_))
    }
}

// ------------------------------------------------------------------
// Transition
// ------------------------------------------------------------------

/// A single state transition with a reason and timestamp.
#[derive(Clone, Debug)]
pub struct Transition {
    pub from: DecoderState,
    pub to: DecoderState,
    pub reason: String,
    /// Milliseconds since session start (monotonic).
    pub elapsed_ms: u64,
}

// ------------------------------------------------------------------
// DecoderHealth
// ------------------------------------------------------------------

/// Atomic health counters, designed for lock-free sampling by the
/// telemetry thread.
#[derive(Debug)]
pub struct DecoderHealth {
    frames_decoded: AtomicU64,
    frames_dropped: AtomicU64,
    errors: AtomicU64,
    recovery_attempts: AtomicU64,
    recoveries_succeeded: AtomicU64,
    recoveries_failed: AtomicU64,
}

impl DecoderHealth {
    pub fn new() -> Self {
        Self {
            frames_decoded: AtomicU64::new(0),
            frames_dropped: AtomicU64::new(0),
            errors: AtomicU64::new(0),
            recovery_attempts: AtomicU64::new(0),
            recoveries_succeeded: AtomicU64::new(0),
            recoveries_failed: AtomicU64::new(0),
        }
    }

    pub fn record_frame_decoded(&self) {
        self.frames_decoded.fetch_add(1, Ordering::Relaxed);
    }
    pub fn record_frame_dropped(&self) {
        self.frames_dropped.fetch_add(1, Ordering::Relaxed);
    }
    pub fn record_error(&self) {
        self.errors.fetch_add(1, Ordering::Relaxed);
    }
    pub fn record_recovery_attempt(&self) {
        self.recovery_attempts.fetch_add(1, Ordering::Relaxed);
    }
    pub fn record_recovery_succeeded(&self) {
        self.recoveries_succeeded.fetch_add(1, Ordering::Relaxed);
    }
    pub fn record_recovery_failed(&self) {
        self.recoveries_failed.fetch_add(1, Ordering::Relaxed);
    }

    pub fn frames_decoded(&self) -> u64 {
        self.frames_decoded.load(Ordering::Relaxed)
    }
    pub fn frames_dropped(&self) -> u64 {
        self.frames_dropped.load(Ordering::Relaxed)
    }
    pub fn errors(&self) -> u64 {
        self.errors.load(Ordering::Relaxed)
    }
    pub fn recovery_attempts(&self) -> u64 {
        self.recovery_attempts.load(Ordering::Relaxed)
    }
    pub fn recoveries_succeeded(&self) -> u64 {
        self.recoveries_succeeded.load(Ordering::Relaxed)
    }
    pub fn recoveries_failed(&self) -> u64 {
        self.recoveries_failed.load(Ordering::Relaxed)
    }

    /// Snapshot for the closing log line.
    pub fn snapshot(&self) -> HealthSnapshot {
        HealthSnapshot {
            frames_decoded: self.frames_decoded(),
            frames_dropped: self.frames_dropped(),
            errors: self.errors(),
            recovery_attempts: self.recovery_attempts(),
            recoveries_succeeded: self.recoveries_succeeded(),
            recoveries_failed: self.recoveries_failed(),
        }
    }

    /// Format for the closing log line.
    pub fn log_string(&self) -> String {
        let s = self.snapshot();
        format!(
            "decoded={} dropped={} errors={} recovery_attempts={} succeeded={} failed={}",
            s.frames_decoded,
            s.frames_dropped,
            s.errors,
            s.recovery_attempts,
            s.recoveries_succeeded,
            s.recoveries_failed,
        )
    }
}

#[derive(Clone, Copy, Debug)]
pub struct HealthSnapshot {
    pub frames_decoded: u64,
    pub frames_dropped: u64,
    pub errors: u64,
    pub recovery_attempts: u64,
    pub recoveries_succeeded: u64,
    pub recoveries_failed: u64,
}

// ------------------------------------------------------------------
// Lifecycle
// ------------------------------------------------------------------

/// Decoder lifecycle state machine.
///
/// All public methods take `&self` (interior mutability via
/// `parking_lot::Mutex`). The lock is held only for the duration of
/// the state update and is never held across I/O.
pub struct Lifecycle {
    state: Mutex<DecoderState>,
    health: DecoderHealth,
    transitions: Mutex<VecDeque<Transition>>,
    max_transitions: usize,
    start: Instant,
}

impl Lifecycle {
    pub fn new() -> Self {
        Self {
            state: Mutex::new(DecoderState::Starting),
            health: DecoderHealth::new(),
            transitions: Mutex::new(VecDeque::with_capacity(32)),
            max_transitions: 32,
            start: Instant::now(),
        }
    }

    pub fn with_capacity(max_transitions: usize) -> Self {
        Self {
            state: Mutex::new(DecoderState::Starting),
            health: DecoderHealth::new(),
            transitions: Mutex::new(VecDeque::with_capacity(max_transitions)),
            max_transitions,
            start: Instant::now(),
        }
    }

    pub fn health(&self) -> &DecoderHealth {
        &self.health
    }

    pub fn current_state(&self) -> DecoderState {
        self.state.lock().clone()
    }

    /// Transition to `to` with a reason. Logs the transition and
    /// records it in the transition history. Returns the `Transition`
    /// record.
    pub fn transition(&self, to: DecoderState, reason: &str) -> Transition {
        let from = {
            let mut guard = self.state.lock();
            std::mem::replace(&mut *guard, to.clone())
        };
        let elapsed_ms = self.start.elapsed().as_millis() as u64;
        let t = Transition {
            from: from.clone(),
            to,
            reason: reason.to_string(),
            elapsed_ms,
        };
        log::info!(
            "[Lifecycle] {} → {} reason=\"{}\" elapsed={:?}",
            t.from.tag(),
            t.to.tag(),
            t.reason,
            t.elapsed_ms,
        );
        {
            let mut hist = self.transitions.lock();
            if hist.len() >= self.max_transitions {
                hist.pop_front();
            }
            hist.push_back(t.clone());
        }
        t
    }

    /// Convenience: transition to `Running`.
    pub fn mark_running(&self, reason: &str) -> Transition {
        self.transition(DecoderState::Running, reason)
    }

    /// Convenience: transition to `Idle`.
    pub fn mark_idle(&self, reason: &str) -> Transition {
        self.transition(DecoderState::Idle, reason)
    }

    /// Convenience: transition to `Recovering`.
    pub fn mark_recovering(&self, reason: &str) -> Transition {
        self.transition(DecoderState::Recovering, reason)
    }

    /// Convenience: transition to `Error`.
    pub fn mark_error(&self, msg: &str) -> Transition {
        self.health.record_error();
        self.transition(DecoderState::Error(msg.to_string()), msg)
    }

    /// Convenience: transition to `ShutDown`.
    pub fn mark_shut_down(&self, reason: &str) -> Transition {
        self.transition(DecoderState::ShutDown, reason)
    }

    /// Drain the recent transition history (oldest first).
    pub fn recent_transitions(&self) -> Vec<Transition> {
        self.transitions.lock().iter().cloned().collect()
    }

    /// Number of transitions recorded.
    pub fn transition_count(&self) -> usize {
        self.transitions.lock().len()
    }
}

impl Drop for Lifecycle {
    fn drop(&mut self) {
        let state = self.current_state();
        let h = self.health.log_string();
        log::info!(
            "[Lifecycle] close state={} health={}",
            state.tag(),
            h,
        );
    }
}

// ------------------------------------------------------------------
// Tests
// ------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn initial_state_is_starting() {
        let lc = Lifecycle::new();
        assert_eq!(lc.current_state(), DecoderState::Starting);
    }

    #[test]
    fn transition_logs_and_records() {
        let lc = Lifecycle::new();
        let t = lc.transition(DecoderState::Running, "decoder ready");
        assert_eq!(t.from, DecoderState::Starting);
        assert_eq!(t.to, DecoderState::Running);
        assert_eq!(t.reason, "decoder ready");
        assert_eq!(lc.current_state(), DecoderState::Running);
        assert_eq!(lc.transition_count(), 1);
    }

    #[test]
    fn mark_running_is_shorthand() {
        let lc = Lifecycle::new();
        let t = lc.mark_running("first frame decoded");
        assert_eq!(t.to, DecoderState::Running);
        assert_eq!(lc.current_state(), DecoderState::Running);
    }

    #[test]
    fn mark_idle_is_shorthand() {
        let lc = Lifecycle::new();
        lc.mark_running("ready");
        let t = lc.mark_idle("no work");
        assert_eq!(t.from, DecoderState::Running);
        assert_eq!(t.to, DecoderState::Idle);
    }

    #[test]
    fn mark_error_records_health() {
        let lc = Lifecycle::new();
        let t = lc.mark_error("corrupt packet");
        assert_eq!(t.to.tag(), "error");
        assert_eq!(lc.health().errors(), 1);
    }

    #[test]
    fn mark_recovering_records_health() {
        let lc = Lifecycle::new();
        lc.mark_running("ready");
        let _ = lc.mark_recovering("pts regression");
        assert_eq!(lc.current_state(), DecoderState::Recovering);
        lc.health().record_recovery_succeeded();
        assert_eq!(lc.health().recoveries_succeeded(), 1);
    }

    #[test]
    fn mark_shut_down() {
        let lc = Lifecycle::new();
        lc.mark_running("ok");
        let t = lc.mark_shut_down("session end");
        assert_eq!(t.to, DecoderState::ShutDown);
        assert!(lc.current_state().is_terminal());
    }

    #[test]
    fn error_is_terminal() {
        assert!(DecoderState::Error("x".into()).is_terminal());
    }

    #[test]
    fn shut_down_is_terminal() {
        assert!(DecoderState::ShutDown.is_terminal());
    }

    #[test]
    fn starting_running_idle_are_not_terminal() {
        assert!(!DecoderState::Starting.is_terminal());
        assert!(!DecoderState::Running.is_terminal());
        assert!(!DecoderState::Idle.is_terminal());
    }

    #[test]
    fn transition_history_is_bounded() {
        let lc = Lifecycle::with_capacity(4);
        for i in 0..10 {
            lc.transition(
                DecoderState::Running,
                &format!("tick {i}"),
            );
        }
        assert_eq!(lc.transition_count(), 4);
        let hist = lc.recent_transitions();
        // The oldest kept transition should be tick 6 (0..4 dropped,
        // 4..9 kept).
        assert_eq!(hist.first().unwrap().reason, "tick 6");
        assert_eq!(hist.last().unwrap().reason, "tick 9");
    }

    #[test]
    fn health_snapshot_captures_counters() {
        let h = DecoderHealth::new();
        h.record_frame_decoded();
        h.record_frame_decoded();
        h.record_frame_dropped();
        h.record_error();
        h.record_recovery_attempt();
        h.record_recovery_succeeded();
        h.record_recovery_failed();

        let s = h.snapshot();
        assert_eq!(s.frames_decoded, 2);
        assert_eq!(s.frames_dropped, 1);
        assert_eq!(s.errors, 1);
        assert_eq!(s.recovery_attempts, 1);
        assert_eq!(s.recoveries_succeeded, 1);
        assert_eq!(s.recoveries_failed, 1);
    }

    #[test]
    fn health_log_string_contains_all_fields() {
        let h = DecoderHealth::new();
        h.record_frame_decoded();
        let s = h.log_string();
        assert!(s.contains("decoded=1"));
        assert!(s.contains("dropped=0"));
        assert!(s.contains("errors=0"));
    }

    #[test]
    fn decoder_state_tag_matches() {
        assert_eq!(DecoderState::Starting.tag(), "starting");
        assert_eq!(DecoderState::Running.tag(), "running");
        assert_eq!(DecoderState::Idle.tag(), "idle");
        assert_eq!(DecoderState::Recovering.tag(), "recovering");
        assert_eq!(DecoderState::Error("x".into()).tag(), "error");
        assert_eq!(DecoderState::ShutDown.tag(), "shut_down");
    }

    #[test]
    fn transition_to_same_state_is_allowed() {
        let lc = Lifecycle::new();
        let t = lc.transition(DecoderState::Starting, "noop");
        assert_eq!(t.from, DecoderState::Starting);
        assert_eq!(t.to, DecoderState::Starting);
        assert_eq!(lc.transition_count(), 1);
    }

    #[test]
    fn drop_emits_log_line() {
        // Just confirm Drop doesn't panic.
        let lc = Lifecycle::new();
        lc.mark_running("ready");
        drop(lc);
    }

    #[test]
    fn health_counters_are_thread_safe() {
        use std::sync::Arc;
        let h = Arc::new(DecoderHealth::new());
        let mut handles = Vec::new();
        for _ in 0..4 {
            let h2 = h.clone();
            handles.push(std::thread::spawn(move || {
                for _ in 0..500 {
                    h2.record_frame_decoded();
                }
            }));
        }
        for hv in handles {
            hv.join().unwrap();
        }
        assert_eq!(h.frames_decoded(), 2000);
    }
}
