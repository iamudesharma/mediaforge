//! Seek recovery: classifier + cooldown/backoff budget.
//!
//! # Why this exists
//!
//! The pre-engine code path in `pipeline::preview` reacts to decode
//! errors with a single strategy: re-open the demuxer, drop the HW
//! decoder, build a software decoder. That works but it's a sledgehammer —
//! most failures are transient (one bad packet, a small seek mismatch)
//! and would have been fixed by a much cheaper action. It's also not
//! bounded: a flapping input could trigger an unbounded cascade of
//! demuxer reopens.
//!
//! `SeekRecovery` introduces a four-step ladder:
//!
//! 1. `Flush` — drop decoder-internal buffers, re-seek to the prior
//!    keyframe. Cheapest; covers "I missed a packet".
//! 2. `KeyframeJump` — `avformat_seek_file(..., AVSEEK_FLAG_BACKWARD)`
//!    to the nearest keyframe + decode forward. Covers "I overshot".
//! 3. `DemuxerReopen` — close the demuxer, reopen the input, build a
//!    new decoder. Covers "the demuxer got into a bad state".
//! 4. `FormatReset` — close everything, re-probe, re-build from
//!    scratch. The "I have no idea" escape hatch.
//!
//! Each step has a `BudgetSlot` (max invocations per session) and a
//! cooldown with exponential backoff so the same step can't fire
//! twice in quick succession.
//!
//! # Wiring
//!
//! `SeekRecovery` is pure logic. The caller (e.g. `VideoPreviewSession`)
//! owns the FFmpeg state. The flow is:
//!
//! ```ignore
//! let strategy = SeekRecovery::classify(signal);
//! match budget.can_fire(strategy, now_ms) {
//!     Ok(()) => {
//!         let result = session.execute(strategy);  // session-owned method
//!         match result {
//!             Ok(()) => budget.record_success(strategy, now_ms),
//!             Err(_) => budget.record_failure(strategy, now_ms),
//!         }
//!     }
//!     Err(VideoForgeError::CooldownActive(_, remaining)) => {
//!         // escalate to the next strategy or skip
//!     }
//!     Err(VideoForgeError::RecoveryBudgetExhausted(_)) => {
//!         // give up; treat the session as unrecoverable for this failure
//!     }
//!     Err(other) => return Err(other),
//! }
//! ```
//!
//! # Stats
//!
//! `Drop` on the budget emits `[SeekRecovery] close flush=N jump=N reopen=N reset=N cooldown_skips=N`
//! for grep-friendly observability.

use std::sync::atomic::{AtomicU32, AtomicU64, Ordering};

use crate::engine::env_flags::{
    int_flag, str_flag, RECOVERY_BUDGET, RECOVERY_COOLDOWN_BACKOFF_SHIFT, RECOVERY_COOLDOWN_MAX_MS,
    RECOVERY_COOLDOWN_MS,
};
use crate::error::VideoForgeError;

/// Recovery strategies, ordered from cheapest to heaviest.
///
/// The order is significant: a classifier may return a strategy, but
/// the caller may *escalate* to a heavier one when the first attempt
/// hits a cooldown or fails.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum RecoveryStrategy {
    /// Drop decoder-internal buffers, re-seek to the prior keyframe.
    /// Cheapest. Covers "I missed a packet" / "decoder was confused".
    Flush,
    /// `avformat_seek_file(..., AVSEEK_FLAG_BACKWARD)` to the nearest
    /// keyframe + decode forward. Covers "I overshot the target PTS".
    KeyframeJump,
    /// Close the demuxer, reopen the input, build a new decoder.
    /// Covers "the demuxer got into a bad state".
    DemuxerReopen,
    /// Close everything, re-probe, re-build from scratch. The "I have
    /// no idea" escape hatch.
    FormatReset,
}

impl RecoveryStrategy {
    /// All strategies in order of escalation.
    pub const ALL: [RecoveryStrategy; 4] = [
        Self::Flush,
        Self::KeyframeJump,
        Self::DemuxerReopen,
        Self::FormatReset,
    ];

    /// The next-heavier strategy. Returns `None` for `FormatReset`.
    pub fn escalate(self) -> Option<Self> {
        match self {
            Self::Flush => Some(Self::KeyframeJump),
            Self::KeyframeJump => Some(Self::DemuxerReopen),
            Self::DemuxerReopen => Some(Self::FormatReset),
            Self::FormatReset => None,
        }
    }

    /// Short tag used in env var parsing and log lines.
    pub fn tag(self) -> &'static str {
        match self {
            Self::Flush => "flush",
            Self::KeyframeJump => "jump",
            Self::DemuxerReopen => "reopen",
            Self::FormatReset => "reset",
        }
    }

    /// Parse the short tag back into a strategy. Returns `None` for
    /// unknown tags.
    pub fn from_tag(tag: &str) -> Option<Self> {
        match tag {
            "flush" => Some(Self::Flush),
            "jump" | "keyframe" | "keyframe_jump" => Some(Self::KeyframeJump),
            "reopen" | "demuxer" | "demuxer_reopen" => Some(Self::DemuxerReopen),
            "reset" | "format" | "format_reset" => Some(Self::FormatReset),
            _ => None,
        }
    }
}

/// Signal categories that the classifier consumes. The caller maps
/// from their concrete error type (FFmpeg, our own, anything else) into
/// one of these variants. Keeping the classifier decoupled from FFmpeg
/// makes it unit-testable.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum RecoverySignal {
    /// `avcodec_receive_frame` returned `EAGAIN` — needs more packets.
    /// Almost always: keep going. Classifier returns `Flush` so the
    /// caller at least has a chance to fix a stuck decoder.
    NeedsMorePackets,
    /// Demuxer ran out of packets at EOF. Classifier returns
    /// `KeyframeJump` (the caller may want to seek to a known
    /// position to keep decoding).
    EndOfStream,
    /// Corrupt / unreadable packet data. Classifier returns `Flush`
    /// (cheap; resets decoder state) unless it persists.
    BadData,
    /// Frame PTS went backwards by more than `delta_ms` — strong
    /// signal that the demuxer's internal position is wrong. Goes
    /// straight to `KeyframeJump` because the demuxer is "ahead" of
    /// the decoder's view of the timeline.
    PtsRegression { delta_ms: i64 },
    /// Format / codec doesn't match what was probed. The decoder
    /// context is wrong. Classifier returns `DemuxerReopen`.
    FormatMismatch,
    /// Unrecognized failure. Default to `KeyframeJump` (safer than
    /// `Flush`; will land on a keyframe at least).
    Unknown,
}

/// Map a `RecoverySignal` to the cheapest strategy likely to fix it.
pub fn classify(signal: RecoverySignal) -> RecoveryStrategy {
    match signal {
        RecoverySignal::NeedsMorePackets => RecoveryStrategy::Flush,
        RecoverySignal::EndOfStream => RecoveryStrategy::KeyframeJump,
        RecoverySignal::BadData => RecoveryStrategy::Flush,
        RecoverySignal::PtsRegression { delta_ms } => {
            // A small regression is normal for B-frames; a large one
            // (negative >1s) is a demuxer/decoder disagreement.
            if delta_ms < -1000 {
                RecoveryStrategy::KeyframeJump
            } else {
                RecoveryStrategy::Flush
            }
        }
        RecoverySignal::FormatMismatch => RecoveryStrategy::DemuxerReopen,
        RecoverySignal::Unknown => RecoveryStrategy::KeyframeJump,
    }
}

/// Per-strategy accounting.
#[derive(Debug)]
pub struct BudgetSlot {
    /// Maximum invocations allowed in the lifetime of the budget.
    pub max: u32,
    /// Counter of invocations consumed (success or failure).
    used: AtomicU32,
    /// Monotonic timestamp (ms since the budget was created) of the
    /// last invocation. `u64::MAX` means "never fired".
    last_fired_ms: AtomicU64,
    /// Consecutive failures since the last success. Resets to 0 on
    /// success; drives the exponential backoff multiplier.
    consecutive_failures: AtomicU32,
}

impl BudgetSlot {
    pub const fn new(max: u32) -> Self {
        Self {
            max,
            used: AtomicU32::new(0),
            last_fired_ms: AtomicU64::new(u64::MAX),
            consecutive_failures: AtomicU32::new(0),
        }
    }

    pub fn used(&self) -> u32 {
        self.used.load(Ordering::Relaxed)
    }
    pub fn last_fired_ms(&self) -> u64 {
        self.last_fired_ms.load(Ordering::Relaxed)
    }
    pub fn consecutive_failures(&self) -> u32 {
        self.consecutive_failures.load(Ordering::Relaxed)
    }

    fn record_fire(&self, now_ms: u64) {
        self.used.fetch_add(1, Ordering::Relaxed);
        self.last_fired_ms.store(now_ms, Ordering::Relaxed);
    }

    fn record_success(&self) {
        self.consecutive_failures.store(0, Ordering::Relaxed);
    }

    fn record_failure(&self) {
        self.consecutive_failures.fetch_add(1, Ordering::Relaxed);
    }
}

/// The full recovery budget: one slot per strategy plus the cooldown
/// parameters shared across all strategies.
#[derive(Debug)]
pub struct RecoveryBudget {
    pub flush: BudgetSlot,
    pub jump: BudgetSlot,
    pub reopen: BudgetSlot,
    pub reset: BudgetSlot,

    /// Base cooldown (ms) between consecutive fires of the *same*
    /// strategy. Default 200.
    pub base_cooldown_ms: u64,
    /// Maximum cooldown (ms) after exponential backoff. Default 2000.
    pub max_cooldown_ms: u64,
    /// `2^shift` cap on the backoff multiplier. Default 4 (16× base).
    pub backoff_shift: u32,

    /// Counter of cooldown-skipped invocations across all strategies.
    /// Exposed in the closing log line.
    pub cooldown_skips: AtomicU64,
}

impl Default for RecoveryBudget {
    fn default() -> Self {
        Self::from_env()
    }
}

impl RecoveryBudget {
    /// Read the `VFP_RECOVERY_*` env flags and build a budget.
    pub fn from_env() -> Self {
        let base = int_flag(RECOVERY_COOLDOWN_MS, 200);
        let max = int_flag(RECOVERY_COOLDOWN_MAX_MS, 2000);
        let shift = int_flag(RECOVERY_COOLDOWN_BACKOFF_SHIFT, 4) as u32;
        let raw = str_flag(RECOVERY_BUDGET, "4,2,2,1");
        let parsed = parse_budget_spec(&raw).unwrap_or([4, 2, 2, 1]);
        log::info!(
            "[SeekRecovery] init budget=flush:{}/jump:{}/reopen:{}/reset:{} cooldown={}ms max={}ms shift={}",
            parsed[0], parsed[1], parsed[2], parsed[3], base, max, shift
        );
        Self {
            flush: BudgetSlot::new(parsed[0]),
            jump: BudgetSlot::new(parsed[1]),
            reopen: BudgetSlot::new(parsed[2]),
            reset: BudgetSlot::new(parsed[3]),
            base_cooldown_ms: base,
            max_cooldown_ms: max,
            backoff_shift: shift,
            cooldown_skips: AtomicU64::new(0),
        }
    }

    /// Build a budget with explicit values (used by tests).
    pub fn new(
        max_flush: u32,
        max_jump: u32,
        max_reopen: u32,
        max_reset: u32,
        base_cooldown_ms: u64,
        max_cooldown_ms: u64,
        backoff_shift: u32,
    ) -> Self {
        Self {
            flush: BudgetSlot::new(max_flush),
            jump: BudgetSlot::new(max_jump),
            reopen: BudgetSlot::new(max_reopen),
            reset: BudgetSlot::new(max_reset),
            base_cooldown_ms,
            max_cooldown_ms,
            backoff_shift,
            cooldown_skips: AtomicU64::new(0),
        }
    }

    fn slot(&self, strategy: RecoveryStrategy) -> &BudgetSlot {
        match strategy {
            RecoveryStrategy::Flush => &self.flush,
            RecoveryStrategy::KeyframeJump => &self.jump,
            RecoveryStrategy::DemuxerReopen => &self.reopen,
            RecoveryStrategy::FormatReset => &self.reset,
        }
    }

    /// Current cooldown (ms) for `strategy` based on its consecutive
    /// failure count. Exponential backoff capped at `max_cooldown_ms`.
    pub fn cooldown_ms(&self, strategy: RecoveryStrategy) -> u64 {
        let slot = self.slot(strategy);
        let failures = slot.consecutive_failures().min(self.backoff_shift);
        let multiplier = 1u64.checked_shl(failures).unwrap_or(u64::MAX);
        (self.base_cooldown_ms.saturating_mul(multiplier)).min(self.max_cooldown_ms)
    }

    /// How long until `strategy` can fire again. Returns 0 if it can
    /// fire immediately (no prior fire, or past cooldown).
    pub fn cooldown_remaining_ms(&self, strategy: RecoveryStrategy, now_ms: u64) -> u64 {
        let slot = self.slot(strategy);
        let last = slot.last_fired_ms();
        if last == u64::MAX {
            return 0;
        }
        let cooldown = self.cooldown_ms(strategy);
        let elapsed = now_ms.saturating_sub(last);
        cooldown.saturating_sub(elapsed)
    }

    /// Check whether `strategy` can fire right now.
    ///
    /// Returns:
    /// - `Ok(())` if the strategy is within budget and past its
    ///   cooldown. The caller should run it, then call
    ///   [`record_success`](Self::record_success) or
    ///   [`record_failure`](Self::record_failure).
    /// - `Err(CooldownActive(strategy, remaining_ms))` if the strategy
    ///   was fired recently and is still cooling down. The caller may
    ///   *escalate* to a heavier strategy.
    /// - `Err(RecoveryBudgetExhausted(strategy))` if the per-strategy
    ///   budget is fully consumed. The caller should treat the session
    ///   as unrecoverable for this failure.
    pub fn can_fire(&self, strategy: RecoveryStrategy, now_ms: u64) -> Result<(), VideoForgeError> {
        let slot = self.slot(strategy);
        if slot.used() >= slot.max {
            return Err(VideoForgeError::RecoveryBudgetExhausted(strategy.tag().to_string()));
        }
        let remaining = self.cooldown_remaining_ms(strategy, now_ms);
        if remaining > 0 {
            self.cooldown_skips.fetch_add(1, Ordering::Relaxed);
            return Err(VideoForgeError::CooldownActive(
                strategy.tag().to_string(),
                remaining,
            ));
        }
        Ok(())
    }

    /// Convenience: run `op`, record success or failure based on the
    /// result, and return the result. Useful for one-liner call sites.
    pub fn fire<F, T>(
        &self,
        strategy: RecoveryStrategy,
        now_ms: u64,
        op: F,
    ) -> Result<T, VideoForgeError>
    where
        F: FnOnce() -> Result<T, VideoForgeError>,
    {
        self.can_fire(strategy, now_ms)?;
        let slot = self.slot(strategy);
        slot.record_fire(now_ms);
        match op() {
            Ok(v) => {
                slot.record_success();
                Ok(v)
            }
            Err(e) => {
                slot.record_failure();
                Err(e)
            }
        }
    }

    /// Manually record a success (when the caller chose not to use
    /// `fire`).
    pub fn record_success(&self, strategy: RecoveryStrategy, now_ms: u64) {
        let slot = self.slot(strategy);
        slot.record_fire(now_ms);
        slot.record_success();
    }

    /// Manually record a failure.
    pub fn record_failure(&self, strategy: RecoveryStrategy, now_ms: u64) {
        let slot = self.slot(strategy);
        slot.record_fire(now_ms);
        slot.record_failure();
    }

    /// Snapshot of the budget state for the closing log line.
    pub fn stats(&self) -> RecoveryBudgetStats {
        RecoveryBudgetStats {
            flush_used: self.flush.used(),
            flush_max: self.flush.max,
            jump_used: self.jump.used(),
            jump_max: self.jump.max,
            reopen_used: self.reopen.used(),
            reopen_max: self.reopen.max,
            reset_used: self.reset.used(),
            reset_max: self.reset.max,
            cooldown_skips: self.cooldown_skips.load(Ordering::Relaxed),
        }
    }
}

impl Drop for RecoveryBudget {
    fn drop(&mut self) {
        let s = self.stats();
        log::info!(
            "[SeekRecovery] close flush={}/{} jump={}/{} reopen={}/{} reset={}/{} cooldown_skips={}",
            s.flush_used, s.flush_max,
            s.jump_used, s.jump_max,
            s.reopen_used, s.reopen_max,
            s.reset_used, s.reset_max,
            s.cooldown_skips,
        );
    }
}

#[derive(Clone, Copy, Debug)]
pub struct RecoveryBudgetStats {
    pub flush_used: u32,
    pub flush_max: u32,
    pub jump_used: u32,
    pub jump_max: u32,
    pub reopen_used: u32,
    pub reopen_max: u32,
    pub reset_used: u32,
    pub reset_max: u32,
    pub cooldown_skips: u64,
}

/// Parse a comma-separated budget spec like `"4,2,2,1"`. An empty or
/// whitespace-only spec returns `None` (so `from_env` can substitute
/// its default). Trailing elements default to 1 if absent. Returns
/// `None` if any non-empty element fails to parse.
pub fn parse_budget_spec(spec: &str) -> Option<[u32; 4]> {
    let trimmed = spec.trim();
    if trimmed.is_empty() {
        return None;
    }
    let parts: Vec<&str> = trimmed.split(',').map(str::trim).collect();
    if parts.len() > 4 {
        return None;
    }
    let mut out = [1u32, 1, 1, 1];
    for (i, p) in parts.iter().enumerate() {
        if p.is_empty() {
            continue;
        }
        out[i] = p.parse::<u32>().ok()?;
    }
    Some(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    // -------- classifier --------

    #[test]
    fn classify_eagain_and_bad_data_both_choose_flush() {
        assert_eq!(
            classify(RecoverySignal::NeedsMorePackets),
            RecoveryStrategy::Flush
        );
        assert_eq!(classify(RecoverySignal::BadData), RecoveryStrategy::Flush);
    }

    #[test]
    fn classify_eof_and_unknown_choose_keyframe_jump() {
        assert_eq!(
            classify(RecoverySignal::EndOfStream),
            RecoveryStrategy::KeyframeJump
        );
        assert_eq!(
            classify(RecoverySignal::Unknown),
            RecoveryStrategy::KeyframeJump
        );
    }

    #[test]
    fn classify_format_mismatch_chooses_demuxer_reopen() {
        assert_eq!(
            classify(RecoverySignal::FormatMismatch),
            RecoveryStrategy::DemuxerReopen
        );
    }

    #[test]
    fn classify_large_pts_regression_chooses_jump() {
        assert_eq!(
            classify(RecoverySignal::PtsRegression { delta_ms: -5_000 }),
            RecoveryStrategy::KeyframeJump
        );
    }

    #[test]
    fn classify_small_pts_regression_chooses_flush() {
        assert_eq!(
            classify(RecoverySignal::PtsRegression { delta_ms: -200 }),
            RecoveryStrategy::Flush
        );
        // -1000 is the strict threshold: > -1000 (i.e. less negative) → Flush
        assert_eq!(
            classify(RecoverySignal::PtsRegression { delta_ms: -999 }),
            RecoveryStrategy::Flush
        );
        // < -1000 (more negative) → KeyframeJump
        assert_eq!(
            classify(RecoverySignal::PtsRegression { delta_ms: -1_001 }),
            RecoveryStrategy::KeyframeJump
        );
    }

    // -------- strategy helpers --------

    #[test]
    fn escalate_walks_to_heavier_strategies() {
        assert_eq!(
            RecoveryStrategy::Flush.escalate(),
            Some(RecoveryStrategy::KeyframeJump)
        );
        assert_eq!(
            RecoveryStrategy::KeyframeJump.escalate(),
            Some(RecoveryStrategy::DemuxerReopen)
        );
        assert_eq!(
            RecoveryStrategy::DemuxerReopen.escalate(),
            Some(RecoveryStrategy::FormatReset)
        );
        assert_eq!(RecoveryStrategy::FormatReset.escalate(), None);
    }

    #[test]
    fn tag_round_trip() {
        for s in RecoveryStrategy::ALL {
            let t = s.tag();
            assert_eq!(RecoveryStrategy::from_tag(t), Some(s));
        }
    }

    #[test]
    fn from_tag_aliases_work() {
        assert_eq!(
            RecoveryStrategy::from_tag("keyframe"),
            Some(RecoveryStrategy::KeyframeJump)
        );
        assert_eq!(
            RecoveryStrategy::from_tag("demuxer"),
            Some(RecoveryStrategy::DemuxerReopen)
        );
        assert_eq!(
            RecoveryStrategy::from_tag("format"),
            Some(RecoveryStrategy::FormatReset)
        );
        assert_eq!(RecoveryStrategy::from_tag("nonsense"), None);
    }

    // -------- budget slot --------

    #[test]
    fn budget_slot_starts_unfired() {
        let s = BudgetSlot::new(4);
        assert_eq!(s.used(), 0);
        assert_eq!(s.last_fired_ms(), u64::MAX);
        assert_eq!(s.consecutive_failures(), 0);
    }

    #[test]
    fn budget_slot_records_fire_and_resets_on_success() {
        let s = BudgetSlot::new(4);
        s.record_fire(100);
        s.record_failure();
        s.record_fire(200);
        s.record_failure();
        assert_eq!(s.used(), 2);
        assert_eq!(s.consecutive_failures(), 2);
        s.record_fire(300);
        s.record_success();
        assert_eq!(s.used(), 3);
        assert_eq!(s.consecutive_failures(), 0);
    }

    // -------- cooldown --------

    #[test]
    fn can_fire_initially_is_ok() {
        let b = RecoveryBudget::new(1, 1, 1, 1, 200, 2000, 4);
        assert!(b.can_fire(RecoveryStrategy::Flush, 0).is_ok());
    }

    #[test]
    fn can_fire_blocks_within_cooldown() {
        // max=2 so the first record_success leaves budget for one more
        let b = RecoveryBudget::new(2, 2, 2, 2, 200, 2000, 4);
        b.record_success(RecoveryStrategy::Flush, 1_000);
        let err = b.can_fire(RecoveryStrategy::Flush, 1_100).unwrap_err();
        match err {
            VideoForgeError::CooldownActive(tag, remaining) => {
                assert_eq!(tag, "flush");
                assert_eq!(remaining, 100); // 200 cooldown - 100 elapsed
            }
            other => panic!("expected CooldownActive, got {other:?}"),
        }
        assert!(b.can_fire(RecoveryStrategy::Flush, 1_200).is_ok());
    }

    #[test]
    fn backoff_doubles_on_consecutive_failures() {
        let b = RecoveryBudget::new(1, 1, 1, 1, 100, 5_000, 4);
        // 0 failures → 100ms base
        assert_eq!(b.cooldown_ms(RecoveryStrategy::Flush), 100);
        b.record_failure(RecoveryStrategy::Flush, 0);
        // 1 failure → 200ms
        assert_eq!(b.cooldown_ms(RecoveryStrategy::Flush), 200);
        b.record_failure(RecoveryStrategy::Flush, 0);
        // 2 failures → 400ms
        assert_eq!(b.cooldown_ms(RecoveryStrategy::Flush), 400);
        b.record_failure(RecoveryStrategy::Flush, 0);
        // 3 failures → 800ms
        assert_eq!(b.cooldown_ms(RecoveryStrategy::Flush), 800);
        b.record_failure(RecoveryStrategy::Flush, 0);
        // 4 failures → 1600ms (capped by shift=4 → 2^4 = 16×)
        assert_eq!(b.cooldown_ms(RecoveryStrategy::Flush), 1_600);
        b.record_failure(RecoveryStrategy::Flush, 0);
        // 5 failures → still 1600ms (multiplier capped at shift)
        assert_eq!(b.cooldown_ms(RecoveryStrategy::Flush), 1_600);
        b.record_failure(RecoveryStrategy::Flush, 0);
        // 6 failures → still capped at 1600ms
        assert_eq!(b.cooldown_ms(RecoveryStrategy::Flush), 1_600);
    }

    #[test]
    fn backoff_caps_at_shift() {
        // shift=2 means max multiplier is 4×base
        let b = RecoveryBudget::new(1, 1, 1, 1, 100, 100_000, 2);
        b.record_failure(RecoveryStrategy::Flush, 0);
        b.record_failure(RecoveryStrategy::Flush, 0);
        // 2 failures → 4×base = 400ms
        assert_eq!(b.cooldown_ms(RecoveryStrategy::Flush), 400);
        b.record_failure(RecoveryStrategy::Flush, 0);
        // 3 failures → 8×base, but shift=2 caps at 4×base
        assert_eq!(b.cooldown_ms(RecoveryStrategy::Flush), 400);
    }

    #[test]
    fn success_resets_consecutive_failures() {
        let b = RecoveryBudget::new(1, 1, 1, 1, 100, 5_000, 4);
        b.record_failure(RecoveryStrategy::Flush, 0);
        b.record_failure(RecoveryStrategy::Flush, 0);
        assert_eq!(b.flush.consecutive_failures(), 2);
        b.record_success(RecoveryStrategy::Flush, 0);
        assert_eq!(b.flush.consecutive_failures(), 0);
        assert_eq!(b.cooldown_ms(RecoveryStrategy::Flush), 100);
    }

    #[test]
    fn budget_exhaustion_returns_err() {
        let b = RecoveryBudget::new(1, 1, 1, 1, 0, 0, 0);
        b.record_success(RecoveryStrategy::Flush, 0);
        let err = b.can_fire(RecoveryStrategy::Flush, 1_000).unwrap_err();
        assert!(matches!(
            err,
            VideoForgeError::RecoveryBudgetExhausted(ref t) if t == "flush"
        ));
    }

    #[test]
    fn can_fire_for_different_strategies_is_independent() {
        let b = RecoveryBudget::new(2, 2, 2, 2, 200, 2000, 4);
        b.record_success(RecoveryStrategy::Flush, 1_000);
        // Flush is in cooldown, but Jump is not
        assert!(b.can_fire(RecoveryStrategy::Flush, 1_100).is_err());
        assert!(b.can_fire(RecoveryStrategy::KeyframeJump, 1_100).is_ok());
    }

    #[test]
    fn fire_runs_op_and_records_outcome() {
        let b = RecoveryBudget::new(2, 2, 2, 2, 0, 0, 0);
        // Success path
        let r = b.fire(RecoveryStrategy::Flush, 100, || Ok(42));
        assert_eq!(r.unwrap(), 42);
        assert_eq!(b.flush.used(), 1);
        assert_eq!(b.flush.consecutive_failures(), 0);

        // Failure path
        let r: Result<(), VideoForgeError> = b.fire(
            RecoveryStrategy::Flush,
            200,
            || Err(VideoForgeError::Internal("nope".into())),
        );
        assert!(r.is_err());
        assert_eq!(b.flush.used(), 2);
        assert_eq!(b.flush.consecutive_failures(), 1);
    }

    #[test]
    fn fire_propagates_cooldown_error() {
        let b = RecoveryBudget::new(2, 2, 2, 2, 200, 2000, 4);
        b.record_success(RecoveryStrategy::Flush, 1_000);
        let r = b.fire(RecoveryStrategy::Flush, 1_050, || Ok::<_, VideoForgeError>(1));
        match r.unwrap_err() {
            VideoForgeError::CooldownActive(_, remaining) => assert_eq!(remaining, 150),
            other => panic!("expected CooldownActive, got {other:?}"),
        }
    }

    #[test]
    fn fire_propagates_exhaustion_error() {
        let b = RecoveryBudget::new(1, 1, 1, 1, 0, 0, 0);
        b.record_success(RecoveryStrategy::Flush, 0);
        let r = b.fire(RecoveryStrategy::Flush, 1_000, || Ok::<_, VideoForgeError>(1));
        assert!(matches!(
            r.unwrap_err(),
            VideoForgeError::RecoveryBudgetExhausted(_)
        ));
    }

    #[test]
    fn cooldown_skips_counter_increments_on_cooldown_block() {
        let b = RecoveryBudget::new(2, 2, 2, 2, 200, 2000, 4);
        b.record_success(RecoveryStrategy::Flush, 1_000);
        assert_eq!(b.cooldown_skips.load(Ordering::Relaxed), 0);
        let _ = b.can_fire(RecoveryStrategy::Flush, 1_050);
        let _ = b.can_fire(RecoveryStrategy::Flush, 1_100);
        assert_eq!(b.cooldown_skips.load(Ordering::Relaxed), 2);
    }

    // -------- env parser --------

    #[test]
    fn parse_budget_spec_basic() {
        assert_eq!(parse_budget_spec("4,2,2,1"), Some([4, 2, 2, 1]));
    }

    #[test]
    fn parse_budget_spec_with_spaces() {
        assert_eq!(parse_budget_spec(" 4 , 2 , 2 , 1 "), Some([4, 2, 2, 1]));
    }

    #[test]
    fn parse_budget_spec_short_pads_with_one() {
        assert_eq!(parse_budget_spec("3"), Some([3, 1, 1, 1]));
        assert_eq!(parse_budget_spec("3,2"), Some([3, 2, 1, 1]));
    }

    #[test]
    fn parse_budget_spec_too_long_returns_none() {
        assert_eq!(parse_budget_spec("1,2,3,4,5"), None);
    }

    #[test]
    fn parse_budget_spec_invalid_int_returns_none() {
        assert_eq!(parse_budget_spec("1,2,3,nope"), None);
    }

    #[test]
    fn parse_budget_spec_empty_returns_none() {
        assert_eq!(parse_budget_spec(""), None);
    }

    #[test]
    fn parse_budget_spec_with_holes_uses_default() {
        // Trailing empty entries should keep the default of 1
        assert_eq!(parse_budget_spec("3,,"), Some([3, 1, 1, 1]));
    }

    // -------- budget stats --------

    #[test]
    fn stats_snapshot_reflects_counters() {
        let b = RecoveryBudget::new(4, 2, 2, 1, 200, 2000, 4);
        b.record_success(RecoveryStrategy::Flush, 0);
        b.record_failure(RecoveryStrategy::Flush, 0);
        b.record_success(RecoveryStrategy::KeyframeJump, 0);
        let s = b.stats();
        assert_eq!(s.flush_used, 2);
        assert_eq!(s.flush_max, 4);
        assert_eq!(s.jump_used, 1);
        assert_eq!(s.jump_max, 2);
        assert_eq!(s.reopen_used, 0);
        assert_eq!(s.reset_used, 0);
        assert_eq!(s.cooldown_skips, 0);
    }
}
