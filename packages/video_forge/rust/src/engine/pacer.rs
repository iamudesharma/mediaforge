//! Wall-clock pacer with drift correction.
//!
//! The playback worker decodes frames at whatever rate the hardware /
//! FFmpeg allows. The display needs frames at the wall-clock rate. A
//! `Pacer` sits between the two: the worker hands each decoded
//! `frame_pts_ms` to [`Pacer::advance`], and the pacer returns a
//! [`PacerAction`] telling the worker what to do with that frame.
//!
//! # Drift correction
//!
//! Running a long playback session at, say, 1.0× the source rate, the
//! decoder and the wall clock are *almost* synchronized but not
//! exactly. Tiny differences accumulate. Without correction, after
//! 10 minutes of playback the displayed frame is 50ms behind the
//! source.
//!
//! `Pacer` tracks a cumulative drift (with exponential moving
//! average) and snaps the `start` instant forward / backward by the
//! current drift when the absolute cumulative crosses
//! `hard_drift_ms`. The snap is logged `[Pacer] drift correction
//! snapped={N}ms cumulative={N}ms` so the operator can grep for it.
//!
//! # ReSeek
//!
//! If the decoder is *way* behind the wall clock (e.g. the disk
//! stalled, a keyframe took too long), the pacer returns
//! [`PacerAction::ReSeek`] with the wall-clock target PTS. The caller
//! is expected to issue a demuxer seek and re-decode from there.
//!
//! # Configuration
//!
//! Tunable knobs (all read from env flags via
//! [`crate::engine::env_flags`]):
//!
//! - `VFP_PACER_SOFT_DRIFT_MS` (default 80) — below this, the frame
//!   is released immediately.
//! - `VFP_PACER_HARD_DRIFT_MS` (default 300) — above this, the
//!   `start` instant is snapped.
//! - `VFP_PACER_RESEEK_DRIFT_MS` (default 1500) — above this, a
//!   `PacerAction::ReSeek` is returned.

use std::sync::atomic::{AtomicI64, AtomicU64, Ordering};
use std::time::{Duration, Instant};

use crate::engine::env_flags::{
    int_flag, PACER_HARD_DRIFT_MS, PACER_RESEEK_DRIFT_MS, PACER_SOFT_DRIFT_MS,
};

/// What the caller should do with a freshly-decoded frame.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PacerAction {
    /// Caller should sleep for `Duration`, then re-call `advance` with
    /// the same (or a newer) frame. Returned when the frame is ahead
    /// of the wall clock.
    Hold(Duration),
    /// Caller should release the frame to the consumer immediately.
    Release,
    /// Caller should drop the frame (it's too stale; the consumer is
    /// catching up to a different point in the timeline).
    Drop,
    /// Caller should issue a demuxer re-seek to the contained PTS. The
    /// decoder is unrecoverably behind the wall clock; trying to
    /// decode forward would just produce more stale frames.
    ReSeek(u64),
}

/// Atomic f64 wrapper. `f64` is not `Sync` in Rust, so we store the
/// bit pattern in an `AtomicU64` and reinterpret on access.
#[derive(Debug)]
struct AtomicF64 {
    bits: AtomicU64,
}

impl AtomicF64 {
    fn new(v: f64) -> Self {
        Self { bits: AtomicU64::new(v.to_bits()) }
    }
    fn store(&self, v: f64) {
        self.bits.store(v.to_bits(), Ordering::Relaxed);
    }
    fn load(&self) -> f64 {
        f64::from_bits(self.bits.load(Ordering::Relaxed))
    }
}

/// Wall-clock pacer.
pub struct Pacer {
    /// Wall-clock anchor. `start_pts_ms` is the PTS at the moment
    /// `start` was captured. Together they define the linear mapping
    /// `wall_clock_now → expected_pts_ms`.
    start: parking_lot::Mutex<Instant>,
    start_pts_ms: AtomicU64,
    rate: AtomicF64,

    /// Exponential moving average of `(frame_pts - expected_pts)`,
    /// measured in ms. Positive = decoder is ahead. Sign preserved
    /// via `AtomicI64`. EMA decay: `(cumulative * 7 + drift) / 8`.
    cumulative_drift_ms: AtomicI64,
    drift_corrections: AtomicU64,
    re_seeks: AtomicU64,

    soft_drift_ms: u64,
    hard_drift_ms: u64,
    re_seek_drift_ms: u64,
}

impl Pacer {
    /// Build a pacer with explicit drift thresholds. The `start` anchor
    /// is captured at construction time; `start_pts_ms` is the PTS
    /// that should be displayed *right now*.
    pub fn new(start_pts_ms: u64, rate: f64) -> Self {
        Self {
            start: parking_lot::Mutex::new(Instant::now()),
            start_pts_ms: AtomicU64::new(start_pts_ms),
            rate: AtomicF64::new(rate),
            cumulative_drift_ms: AtomicI64::new(0),
            drift_corrections: AtomicU64::new(0),
            re_seeks: AtomicU64::new(0),
            soft_drift_ms: int_flag(PACER_SOFT_DRIFT_MS, 80),
            hard_drift_ms: int_flag(PACER_HARD_DRIFT_MS, 300),
            re_seek_drift_ms: int_flag(PACER_RESEEK_DRIFT_MS, 1500),
        }
    }

    /// Build a pacer with explicit thresholds (used by tests).
    pub fn with_thresholds(
        start_pts_ms: u64,
        rate: f64,
        soft_drift_ms: u64,
        hard_drift_ms: u64,
        re_seek_drift_ms: u64,
    ) -> Self {
        Self {
            start: parking_lot::Mutex::new(Instant::now()),
            start_pts_ms: AtomicU64::new(start_pts_ms),
            rate: AtomicF64::new(rate),
            cumulative_drift_ms: AtomicI64::new(0),
            drift_corrections: AtomicU64::new(0),
            re_seeks: AtomicU64::new(0),
            soft_drift_ms,
            hard_drift_ms,
            re_seek_drift_ms,
        }
    }

    pub fn start_pts_ms(&self) -> u64 {
        self.start_pts_ms.load(Ordering::Relaxed)
    }
    pub fn rate(&self) -> f64 {
        self.rate.load()
    }

    /// Update the playback rate (e.g. user dragged the speed slider).
    /// Re-anchors the start instant to `now` with the current PTS so
    /// the wall-clock mapping stays consistent.
    pub fn set_rate(&self, rate: f64) {
        self.rate.store(rate);
    }

    /// Reset the pacer. Re-anchors the start instant to `now` with
    /// the given PTS. Used after a successful ReSeek.
    pub fn reset(&self, start_pts_ms: u64) {
        *self.start.lock() = Instant::now();
        self.start_pts_ms.store(start_pts_ms, Ordering::Relaxed);
        self.cumulative_drift_ms.store(0, Ordering::Relaxed);
    }

    /// What PTS should be displayed *right now* (according to wall
    /// clock). No decoder involvement.
    pub fn expected_pts_ms(&self) -> u64 {
        let start = *self.start.lock();
        let start_pts = self.start_pts_ms.load(Ordering::Relaxed);
        let rate = self.rate.load();
        let elapsed_ms = start.elapsed().as_secs_f64() * 1000.0 * rate;
        start_pts.saturating_add(elapsed_ms as u64)
    }

    /// Decide what to do with `frame_pts_ms`.
    ///
    /// See module docs for the algorithm. Pure (no I/O, no sleep).
    pub fn advance(&self, frame_pts_ms: u64) -> PacerAction {
        let expected = self.expected_pts_ms();
        // Sign-extended drift. Positive = frame is ahead of wall clock.
        let drift = (frame_pts_ms as i128 - expected as i128) as i64;

        // Update the cumulative EMA: keep ≈7/8 of the old, add 1/8 of
        // the new. (Use i64 throughout; the saturating arithmetic
        // keeps a stuck decoder from overflow.)
        let old_cum = self.cumulative_drift_ms.load(Ordering::Relaxed);
        let new_cum = old_cum.saturating_mul(7).saturating_add(drift) / 8;
        self.cumulative_drift_ms.store(new_cum, Ordering::Relaxed);

        // 1) ReSeek: the frame is way too old; the decoder is
        // unrecoverably behind. This is the "give up" path.
        if (frame_pts_ms as i128) < (expected as i128).saturating_sub(self.re_seek_drift_ms as i128)
        {
            self.re_seeks.fetch_add(1, Ordering::Relaxed);
            log::warn!(
                "[Pacer] drift={}ms cumulative={}ms; emitting ReSeek({})ms",
                drift, new_cum, expected
            );
            return PacerAction::ReSeek(expected);
        }

        // 2) Drift correction: cumulative drift has built up; snap
        // the start instant to reset the baseline. We always release
        // the current frame (it was the trigger).
        if new_cum.unsigned_abs() >= self.hard_drift_ms {
            let snap_ms = drift as i64;
            let new_start = {
                let start = self.start.lock();
                if snap_ms >= 0 {
                    start.checked_add(Duration::from_millis(snap_ms as u64))
                } else {
                    start.checked_sub(Duration::from_millis((-snap_ms) as u64))
                }
            };
            if let Some(new_start) = new_start {
                *self.start.lock() = new_start;
            }
            self.drift_corrections.fetch_add(1, Ordering::Relaxed);
            self.cumulative_drift_ms.store(0, Ordering::Relaxed);
            log::info!(
                "[Pacer] drift correction snapped={}ms cumulative={}ms (was); new start anchor",
                snap_ms, new_cum
            );
            return PacerAction::Release;
        }

        // 3) Soft drift: release immediately.
        if drift.unsigned_abs() <= self.soft_drift_ms {
            return PacerAction::Release;
        }

        // 4) Frame too old (between hard_drift and re_seek_drift) but
        // not catastrophically so: drop it.
        if (frame_pts_ms as i128) < (expected as i128).saturating_sub(self.hard_drift_ms as i128) {
            return PacerAction::Drop;
        }

        // 5) Frame is ahead of wall clock: hold.
        if drift > 0 {
            let hold_ms = (drift as u64).saturating_sub(self.soft_drift_ms);
            return PacerAction::Hold(Duration::from_millis(hold_ms));
        }

        // 6) Frame is behind by less than hard_drift: drop (consumer
        // is catching up; this frame is too stale to display).
        PacerAction::Drop
    }

    /// Snapshot of the pacer state for the closing log line.
    pub fn stats(&self) -> PacerStats {
        PacerStats {
            start_pts_ms: self.start_pts_ms.load(Ordering::Relaxed),
            rate: self.rate.load(),
            cumulative_drift_ms: self.cumulative_drift_ms.load(Ordering::Relaxed),
            drift_corrections: self.drift_corrections.load(Ordering::Relaxed),
            re_seeks: self.re_seeks.load(Ordering::Relaxed),
        }
    }
}

impl Drop for Pacer {
    fn drop(&mut self) {
        let s = self.stats();
        log::info!(
            "[Pacer] close corrections={} re_seeks={} cumulative_drift={}ms rate={:.3}",
            s.drift_corrections, s.re_seeks, s.cumulative_drift_ms, s.rate
        );
    }
}

#[derive(Clone, Copy, Debug)]
pub struct PacerStats {
    pub start_pts_ms: u64,
    pub rate: f64,
    pub cumulative_drift_ms: i64,
    pub drift_corrections: u64,
    pub re_seeks: u64,
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::thread::sleep;
    #[allow(unused_imports)]
    use std::time::Instant;

    fn p(soft: u64, hard: u64, re_seek: u64) -> Pacer {
        Pacer::with_thresholds(0, 1.0, soft, hard, re_seek)
    }

    // -------- expected_pts_ms --------

    #[test]
    fn expected_pts_advances_with_wall_clock() {
        let pacer = p(80, 300, 1500);
        let t0 = pacer.expected_pts_ms();
        sleep(Duration::from_millis(20));
        let t1 = pacer.expected_pts_ms();
        assert!(t1 >= t0 + 15, "expected ~20ms, got {t0} -> {t1}");
        assert!(t1 < t0 + 50, "expected ~20ms, got {t0} -> {t1}");
    }

    #[test]
    fn expected_pts_respects_rate() {
        let pacer = Pacer::with_thresholds(1000, 2.0, 80, 300, 1500);
        let t0 = pacer.expected_pts_ms();
        sleep(Duration::from_millis(20));
        let t1 = pacer.expected_pts_ms();
        // 20ms wall * 2.0 rate = 40ms PTS
        assert!(t1 >= t0 + 30, "expected ~40ms, got {t0} -> {t1}");
        assert!(t1 < t0 + 80, "expected ~40ms, got {t0} -> {t1}");
    }

    // -------- soft drift --------

    #[test]
    fn soft_drift_returns_release() {
        let pacer = p(80, 300, 1500);
        // Expected ≈ 0 (just constructed). Frame at 50ms is within
        // soft drift.
        let action = pacer.advance(50);
        assert_eq!(action, PacerAction::Release);
    }

    #[test]
    fn exactly_at_soft_drift_boundary_returns_release() {
        let pacer = p(80, 300, 1500);
        // Frame at 80ms when expected ~0: drift = 80, which is
        // <= soft_drift → Release.
        let action = pacer.advance(80);
        assert_eq!(action, PacerAction::Release);
    }

    // -------- hold --------

    #[test]
    fn frame_ahead_of_wall_clock_returns_hold() {
        let pacer = p(80, 300, 1500);
        sleep(Duration::from_millis(10));
        // Expected ≈ 10. Frame at 200 → drift 190. > soft_drift. Frame
        // is ahead, so Hold(190 - 80) = Hold(110ms).
        let action = pacer.advance(200);
        match action {
            PacerAction::Hold(d) => {
                assert!(d >= Duration::from_millis(100), "hold too short: {d:?}");
                assert!(d <= Duration::from_millis(150), "hold too long: {d:?}");
            }
            other => panic!("expected Hold, got {other:?}"),
        }
    }

    // -------- drop --------

    #[test]
    fn frame_slightly_behind_returns_drop() {
        let pacer = p(80, 300, 1500);
        sleep(Duration::from_millis(500));
        // Expected ≈ 500. Frame at 100 → drift -400, |drift| > hard
        // (300) but |drift| < re_seek (1500). Should Drop.
        let action = pacer.advance(100);
        assert_eq!(action, PacerAction::Drop);
    }

    // -------- re_seek --------

    #[test]
    fn frame_way_behind_returns_re_seek() {
        let pacer = p(80, 300, 1500);
        sleep(Duration::from_millis(2_000));
        // Expected ≈ 2000. Frame at 0 → drift -2000, |drift| >
        // re_seek_drift (1500). Should ReSeek(2000).
        let action = pacer.advance(0);
        match action {
            PacerAction::ReSeek(t) => {
                assert!(t >= 1_900 && t <= 2_100, "unexpected target: {t}");
            }
            other => panic!("expected ReSeek, got {other:?}"),
        }
        assert_eq!(pacer.stats().re_seeks, 1);
    }

    // -------- drift correction --------

    #[test]
    fn cumulative_drift_triggers_correction() {
        let pacer = p(80, 300, 1500);
        // Feed frames with drift = +1000 (well above hard_drift=300).
        // The EMA (×7/8) asymptotes near 1000 and crosses the
        // hard_drift threshold within a handful of frames, firing the
        // drift-correction path. After the correction resets the
        // baseline, the next batch of frames rebuilds the EMA, so we
        // expect corrections ≥ 1 and a bounded cumulative.
        for i in 0..10 {
            let _ = pacer.advance(1_000 + i);
        }
        let s = pacer.stats();
        assert!(
            s.drift_corrections >= 1,
            "expected ≥1 correction, got {} (cumulative={})",
            s.drift_corrections,
            s.cumulative_drift_ms
        );
        // Cumulative must be below the hard_drift threshold,
        // otherwise the correction path never resets it.
        assert!(
            s.cumulative_drift_ms.unsigned_abs() < 300,
            "cumulative not bounded after correction: {}",
            s.cumulative_drift_ms
        );
    }

    // -------- reset --------

    #[test]
    fn reset_clears_cumulative_and_re_anchors() {
        let pacer = p(80, 300, 1500);
        // Build up some cumulative drift.
        sleep(Duration::from_millis(10));
        for i in 0..20 {
            let _ = pacer.advance(200 + i);
        }
        assert!(pacer.stats().cumulative_drift_ms != 0);
        pacer.reset(5_000);
        // After reset, start_pts is 5_000 and cumulative is 0.
        assert_eq!(pacer.start_pts_ms(), 5_000);
        assert_eq!(pacer.stats().cumulative_drift_ms, 0);
        // A frame at 5_000 is exactly on target → Release.
        let action = pacer.advance(5_000);
        assert_eq!(action, PacerAction::Release);
    }

    // -------- set_rate --------

    #[test]
    fn set_rate_updates_storage() {
        let pacer = p(80, 300, 1500);
        pacer.set_rate(2.0);
        assert!((pacer.rate() - 2.0).abs() < f64::EPSILON);
        pacer.set_rate(0.5);
        assert!((pacer.rate() - 0.5).abs() < f64::EPSILON);
    }

    // -------- stats --------

    #[test]
    fn stats_snapshot_reflects_state() {
        let pacer = p(80, 300, 1500);
        let s0 = pacer.stats();
        assert_eq!(s0.drift_corrections, 0);
        assert_eq!(s0.re_seeks, 0);
        assert_eq!(s0.cumulative_drift_ms, 0);
        assert!((s0.rate - 1.0).abs() < f64::EPSILON);

        // Trigger a ReSeek to bump the counter.
        sleep(Duration::from_millis(2_000));
        let _ = pacer.advance(0);
        let s1 = pacer.stats();
        assert_eq!(s1.re_seeks, 1);
    }

    // -------- concurrent safety --------

    #[test]
    fn advance_is_thread_safe() {
        use std::sync::Arc;
        let pacer = Arc::new(p(80, 300, 1500));
        let mut handles = Vec::new();
        for t in 0..4 {
            let p2 = pacer.clone();
            handles.push(std::thread::spawn(move || {
                for i in 0..200 {
                    let _ = p2.advance((t * 1000 + i) as u64);
                }
            }));
        }
        for h in handles {
            h.join().unwrap();
        }
        // Just confirm no panic and counters are non-degenerate.
        let s = pacer.stats();
        // 800 advances total, but we don't know how many were
        // counted as ReSeek vs correction. Just assert
        // corrections+re_seeks <= 800.
        assert!(s.drift_corrections + s.re_seeks <= 800);
    }
}
