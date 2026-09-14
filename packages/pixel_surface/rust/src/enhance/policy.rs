//! Deadline-aware mode selection.
//!
//! Playback stability outranks picture quality: if the enhancement pass cannot
//! keep up with the source frame interval it steps down, and it never
//! oscillates back and forth. The policy is pure state — the caller feeds it
//! `(now, frame_ms, deadline_ms)` and acts on the returned action.
//!
//! Hysteresis rules:
//!
//! * a *soft miss* is a frame that used more than 75 % of the deadline;
//! * a *hard miss* used the whole deadline or more;
//! * `DOWNGRADE_STRIKES` soft misses in a row, or one hard miss while already
//!   above 90 % of the deadline, step the mode down one level;
//! * at most one step down per [`DOWNGRADE_COOLDOWN`];
//! * stepping back up needs [`RECOVERY_STABLE`] of clean frames, and each
//!   recovery needs its own clean window — so a mode that keeps missing
//!   settles down instead of flapping;
//! * once the ladder reaches `Off`, the policy latches `deadline_miss` and
//!   stops trying. Only a new user request (or a resolution change) re-arms it.

use std::time::Duration;

use super::EnhancementMode;

/// Fraction of the frame deadline a frame may use before it counts as a miss.
pub const SOFT_MISS_RATIO: f32 = 0.75;

/// Consecutive soft misses that trigger a downgrade.
pub const DOWNGRADE_STRIKES: u32 = 3;

/// Minimum time between two automatic downgrades.
pub const DOWNGRADE_COOLDOWN: Duration = Duration::from_millis(1000);

/// Continuous clean time required to step back up one level.
pub const RECOVERY_STABLE: Duration = Duration::from_secs(20);

/// Upper bound on automatic downgrades before the policy stays put.
pub const MAX_DOWNGRADES: u32 = 3;

/// What the caller should do after observing a frame.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PolicyAction {
    /// Keep the current effective mode.
    Hold,
    /// Switch to the given mode (always a step down).
    Downgrade(EnhancementMode),
    /// Enhancement is now off; bypass and keep playing untouched.
    Bypass,
    /// Step back up one level after a long clean window.
    Recover(EnhancementMode),
}

/// Rolling enhancement performance state.
#[derive(Debug, Clone)]
pub struct EnhancementPolicy {
    requested: EnhancementMode,
    effective: EnhancementMode,
    consecutive_misses: u32,
    ema_frame_ms: f32,
    ema_deadline_ms: f32,
    last_frame_ms: f32,
    frames_observed: u64,
    misses: u64,
    hard_misses: u64,
    downgrades: u32,
    last_downgrade_at: Option<Duration>,
    clean_since: Option<Duration>,
    fallback_reason: Option<String>,
}

impl Default for EnhancementPolicy {
    fn default() -> Self {
        Self::new()
    }
}

impl EnhancementPolicy {
    pub fn new() -> Self {
        Self {
            requested: EnhancementMode::Off,
            effective: EnhancementMode::Off,
            consecutive_misses: 0,
            ema_frame_ms: 0.0,
            ema_deadline_ms: 0.0,
            last_frame_ms: 0.0,
            frames_observed: 0,
            misses: 0,
            hard_misses: 0,
            downgrades: 0,
            last_downgrade_at: None,
            clean_since: None,
            fallback_reason: None,
        }
    }

    /// User-requested mode (what the app asked for).
    pub fn requested(&self) -> EnhancementMode {
        self.requested
    }

    /// Mode the pipeline is actually allowed to run.
    pub fn effective(&self) -> EnhancementMode {
        self.effective
    }

    /// Set (or re-set) the requested mode. Re-arms the ladder and clears any
    /// latched fallback: an explicit user choice always wins over a previous
    /// automatic downgrade.
    pub fn request(&mut self, mode: EnhancementMode) {
        self.requested = mode;
        self.effective = mode;
        self.consecutive_misses = 0;
        self.downgrades = 0;
        self.last_downgrade_at = None;
        self.clean_since = None;
        self.fallback_reason = None;
    }

    /// Clamp the effective mode to what the device supports.
    pub fn clamp_to(&mut self, supported: &[EnhancementMode]) {
        if supported.contains(&self.effective) {
            return;
        }
        // Fall back to the highest supported mode at or below the request.
        let mut candidate = self.effective;
        while candidate.is_active() {
            candidate = candidate.step_down();
            if supported.contains(&candidate) {
                break;
            }
        }
        self.effective = candidate;
        self.requested = candidate;
        if candidate == EnhancementMode::Off {
            self.fallback_reason = Some("mode_not_supported".to_string());
        }
    }

    /// Forget the current resolution's history — used when the decoder output
    /// size changes, which invalidates both the timing profile and the plan.
    pub fn on_resolution_change(&mut self) {
        self.consecutive_misses = 0;
        self.clean_since = None;
        self.ema_frame_ms = 0.0;
        self.ema_deadline_ms = 0.0;
    }

    pub fn last_frame_ms(&self) -> f32 {
        self.last_frame_ms
    }

    pub fn average_frame_ms(&self) -> f32 {
        self.ema_frame_ms
    }

    pub fn deadline_ms(&self) -> f32 {
        self.ema_deadline_ms
    }

    pub fn last_frame_used_deadline_fraction(&self) -> f32 {
        if self.ema_deadline_ms <= 0.0 {
            return 0.0;
        }
        self.last_frame_ms / self.ema_deadline_ms
    }

    pub fn deadline_misses(&self) -> u64 {
        self.misses
    }

    pub fn hard_deadline_misses(&self) -> u64 {
        self.hard_misses
    }

    pub fn frames_observed(&self) -> u64 {
        self.frames_observed
    }

    pub fn downgrade_count(&self) -> u32 {
        self.downgrades
    }

    pub fn fallback_reason(&self) -> Option<&str> {
        self.fallback_reason.as_deref()
    }

    /// Latch an external fallback (backend failure, unsupported device).
    pub fn latch_fallback(&mut self, reason: impl Into<String>) {
        let reason = reason.into();
        if self.effective.is_active() {
            self.effective = EnhancementMode::Off;
        }
        if self.fallback_reason.is_none() {
            self.fallback_reason = Some(reason);
        }
    }

    /// Record one processed frame.
    pub fn observe(&mut self, now: Duration, frame_ms: f32, deadline_ms: f32) -> PolicyAction {
        self.frames_observed += 1;
        self.last_frame_ms = frame_ms;

        if self.ema_frame_ms <= 0.0 {
            self.ema_frame_ms = frame_ms;
        } else {
            // 0.1 EMA: ~10-frame memory, enough to smooth a single jitter spike.
            self.ema_frame_ms = self.ema_frame_ms * 0.9 + frame_ms * 0.1;
        }
        if deadline_ms > 0.0 {
            if self.ema_deadline_ms <= 0.0 {
                self.ema_deadline_ms = deadline_ms;
            } else {
                self.ema_deadline_ms = self.ema_deadline_ms * 0.9 + deadline_ms * 0.1;
            }
        }

        if !self.effective.is_active() {
            return PolicyAction::Hold;
        }

        let deadline = if deadline_ms > 0.0 { deadline_ms } else { 33.0 };
        let soft = deadline * SOFT_MISS_RATIO;
        let over_deadline = frame_ms > deadline;
        let soft_miss = frame_ms > soft;
        if soft_miss {
            self.misses += 1;
        }
        if over_deadline {
            self.hard_misses += 1;
        }

        if self.downgrades >= MAX_DOWNGRADES {
            return PolicyAction::Hold;
        }

        if soft_miss {
            self.consecutive_misses += 1;
            self.clean_since = None;
            // A single hard miss is enough once we are already close to the
            // limit; three soft misses in a row are enough otherwise.
            let decisive = over_deadline || self.consecutive_misses >= DOWNGRADE_STRIKES;
            if !decisive {
                return PolicyAction::Hold;
            }
            if let Some(last) = self.last_downgrade_at {
                if now.saturating_sub(last) < DOWNGRADE_COOLDOWN {
                    return PolicyAction::Hold;
                }
            }
            return self.step_down(now, if over_deadline { "deadline_exceeded" } else { "deadline_pressure" });
        }

        // Clean frame: consider recovery once, and only after a long stable
        // window, so a mode that keeps missing cannot flap.
        self.consecutive_misses = 0;
        if self.downgrades == 0 {
            return PolicyAction::Hold;
        }
        let started = *self.clean_since.get_or_insert(now);
        if now.saturating_sub(started) < RECOVERY_STABLE {
            return PolicyAction::Hold;
        }
        // One step up per full clean window.
        self.clean_since = Some(now);
        let next = self.effective.step_up();
        if next == self.effective || next > self.requested {
            return PolicyAction::Hold;
        }
        self.effective = next;
        self.downgrades = self.downgrades.saturating_sub(1);
        PolicyAction::Recover(next)
    }

    fn step_down(&mut self, now: Duration, reason: &str) -> PolicyAction {
        let next = self.effective.step_down();
        self.effective = next;
        self.consecutive_misses = 0;
        self.downgrades += 1;
        self.last_downgrade_at = Some(now);
        self.clean_since = None;
        if next == EnhancementMode::Off {
            self.latch_fallback(reason);
            return PolicyAction::Bypass;
        }
        PolicyAction::Downgrade(next)
    }

    /// Format a compact status line for the `[VideoEnhance]` log tag.
    pub fn summary(&self) -> String {
        format!(
            "requested={} effective={} frame={:.2}ms avg={:.2}ms deadline={:.2}ms \
             misses={} hard={} downgrades={}",
            self.requested,
            self.effective,
            self.last_frame_ms,
            self.ema_frame_ms,
            self.ema_deadline_ms,
            self.misses,
            self.hard_misses,
            self.downgrades
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ms(v: u64) -> Duration {
        Duration::from_millis(v)
    }

    #[test]
    fn starts_off_and_requests_are_immediate() {
        let mut p = EnhancementPolicy::new();
        assert_eq!(p.effective(), EnhancementMode::Off);
        p.request(EnhancementMode::HighQuality);
        assert_eq!(p.requested(), EnhancementMode::HighQuality);
        assert_eq!(p.effective(), EnhancementMode::HighQuality);
        assert!(p.fallback_reason().is_none());
    }

    #[test]
    fn a_single_soft_miss_does_not_downgrade() {
        let mut p = EnhancementPolicy::new();
        p.request(EnhancementMode::HighQuality);
        assert_eq!(p.observe(ms(0), 30.0, 33.0), PolicyAction::Hold);
        assert_eq!(p.effective(), EnhancementMode::HighQuality);
    }

    #[test]
    fn three_consecutive_soft_misses_downgrade_one_step() {
        let mut p = EnhancementPolicy::new();
        p.request(EnhancementMode::HighQuality);
        let mut now = ms(0);
        let mut action = PolicyAction::Hold;
        for _ in 0..3 {
            now += ms(33);
            action = p.observe(now, 30.0, 33.0);
        }
        assert_eq!(action, PolicyAction::Downgrade(EnhancementMode::Enhanced));
        assert_eq!(p.effective(), EnhancementMode::Enhanced);
    }

    #[test]
    fn one_hard_miss_downgrades_immediately() {
        let mut p = EnhancementPolicy::new();
        p.request(EnhancementMode::Enhanced);
        let a = p.observe(ms(0), 40.0, 33.0);
        assert_eq!(a, PolicyAction::Downgrade(EnhancementMode::Sharp));
    }

    #[test]
    fn a_clean_frame_resets_the_strike_streak() {
        let mut p = EnhancementPolicy::new();
        p.request(EnhancementMode::HighQuality);
        p.observe(ms(0), 30.0, 33.0);
        p.observe(ms(33), 30.0, 33.0);
        p.observe(ms(66), 10.0, 33.0); // clean
        assert_eq!(p.observe(ms(99), 30.0, 33.0), PolicyAction::Hold);
        assert_eq!(p.effective(), EnhancementMode::HighQuality);
    }

    #[test]
    fn cooldown_limits_downgrade_rate() {
        let mut p = EnhancementPolicy::new();
        p.request(EnhancementMode::HighQuality);
        assert!(matches!(
            p.observe(ms(0), 100.0, 33.0),
            PolicyAction::Downgrade(_)
        ));
        // Immediately hard-missing again must not chain a second downgrade.
        assert_eq!(p.observe(ms(10), 100.0, 33.0), PolicyAction::Hold);
        assert!(matches!(
            p.observe(ms(1500), 100.0, 33.0),
            PolicyAction::Downgrade(_)
        ));
    }

    #[test]
    fn ladder_reaches_off_and_latches_a_reason() {
        let mut p = EnhancementPolicy::new();
        p.request(EnhancementMode::Sharp);
        let a = p.observe(ms(0), 100.0, 33.0);
        assert_eq!(a, PolicyAction::Bypass);
        assert_eq!(p.effective(), EnhancementMode::Off);
        assert_eq!(p.fallback_reason(), Some("deadline_exceeded"));
    }

    #[test]
    fn a_new_user_request_rearms_after_a_fallback() {
        let mut p = EnhancementPolicy::new();
        p.request(EnhancementMode::Sharp);
        p.observe(ms(0), 100.0, 33.0);
        assert_eq!(p.effective(), EnhancementMode::Off);
        p.request(EnhancementMode::Enhanced);
        assert_eq!(p.effective(), EnhancementMode::Enhanced);
        assert!(p.fallback_reason().is_none());
        assert_eq!(p.downgrade_count(), 0);
    }

    #[test]
    fn recovery_needs_a_long_clean_window_and_never_overshoots_the_request() {
        let mut p = EnhancementPolicy::new();
        p.request(EnhancementMode::Enhanced);
        p.observe(ms(0), 100.0, 33.0); // → Sharp
        assert_eq!(p.effective(), EnhancementMode::Sharp);

        // Clean frames for ~19 s after the downgrade: still holding.
        let mut now = ms(1000);
        for _ in 0..10 {
            now += ms(1900);
            p.observe(now, 4.0, 33.0);
        }
        assert_eq!(p.effective(), EnhancementMode::Sharp);

        // The clean window starts at the first clean frame, not at the
        // downgrade itself.
        let window_start = ms(1000) + ms(1900);
        assert!(now.saturating_sub(window_start) < RECOVERY_STABLE);

        // Past the stable window → one step back up, never above the request.
        now = window_start + RECOVERY_STABLE + ms(500);
        let a = p.observe(now, 4.0, 33.0);
        assert_eq!(a, PolicyAction::Recover(EnhancementMode::Enhanced));
        assert_eq!(p.effective(), EnhancementMode::Enhanced);

        // A second full clean window must not exceed the requested mode.
        now += RECOVERY_STABLE + ms(1000);
        assert_eq!(p.observe(now, 4.0, 33.0), PolicyAction::Hold);
        assert_eq!(p.effective(), EnhancementMode::Enhanced);
    }

    #[test]
    fn no_recovery_without_a_prior_downgrade() {
        let mut p = EnhancementPolicy::new();
        p.request(EnhancementMode::Sharp);
        let mut now = ms(0);
        for _ in 0..100 {
            now += ms(33);
            assert_eq!(p.observe(now, 2.0, 33.0), PolicyAction::Hold);
        }
    }

    #[test]
    fn max_downgrades_stops_the_ladder() {
        let mut p = EnhancementPolicy::new();
        p.request(EnhancementMode::HighQuality);
        let mut now = ms(0);
        for _ in 0..4 {
            now += ms(2000);
            p.observe(now, 100.0, 33.0);
        }
        assert_eq!(p.effective(), EnhancementMode::Off);
        assert!(p.downgrade_count() >= MAX_DOWNGRADES);
        // Further misses change nothing.
        now += ms(2000);
        assert_eq!(p.observe(now, 100.0, 33.0), PolicyAction::Hold);
    }

    #[test]
    fn unsupported_modes_clamp_to_the_best_supported_one() {
        let mut p = EnhancementPolicy::new();
        p.request(EnhancementMode::HighQuality);
        p.clamp_to(&[EnhancementMode::Off, EnhancementMode::Sharp]);
        assert_eq!(p.effective(), EnhancementMode::Sharp);

        p.request(EnhancementMode::Enhanced);
        p.clamp_to(&[EnhancementMode::Off]);
        assert_eq!(p.effective(), EnhancementMode::Off);
        assert_eq!(p.fallback_reason(), Some("mode_not_supported"));
    }

    #[test]
    fn resolution_change_clears_timing_history() {
        let mut p = EnhancementPolicy::new();
        p.request(EnhancementMode::Enhanced);
        p.observe(ms(0), 30.0, 33.0);
        p.observe(ms(33), 30.0, 33.0);
        p.on_resolution_change();
        assert_eq!(p.observe(ms(66), 30.0, 33.0), PolicyAction::Hold);
        assert_eq!(p.effective(), EnhancementMode::Enhanced);
    }

    #[test]
    fn dormant_policy_observes_without_acting() {
        let mut p = EnhancementPolicy::new();
        assert_eq!(p.observe(ms(0), 500.0, 33.0), PolicyAction::Hold);
        assert_eq!(p.frames_observed(), 1);
    }
}
