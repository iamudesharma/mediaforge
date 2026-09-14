//! GPU video enhancement bridge for the playback engine.
//!
//! Wraps [`pixel_surface::enhance`] with the policy the playback path needs:
//! a requested mode, a resolution-aware plan, and a deadline-aware quality
//! ladder. The engine calls [`VideoEnhancementRuntime::enhance`] once per
//! presented frame; on any failure it returns `None` and the caller presents
//! the decoded frame unchanged, so enhancement can never break playback.
//!
//! # Pixel-buffer ownership
//!
//! [`VideoEnhancementRuntime::enhance`] takes the decoded frame's `+1`
//! `CVPixelBuffer` retain and, on success, consumes it (returning a `+1` on
//! the enhanced surface instead). On failure the caller's retain is left
//! untouched so the same frame can still be presented as-is.

use std::time::{Duration, Instant};

use pixel_surface::enhance::plan::{self, EnhancementPlan, PlanRequest, Scaler};
use pixel_surface::enhance::policy::{EnhancementPolicy, PolicyAction};
use pixel_surface::enhance::{
    EnhancementBackend, EnhancementCapabilities, FrameHandle, FrameSize,
};

/// Re-exported so the FRB layer converts modes without naming the GPU crate.
pub use pixel_surface::enhance::EnhancementMode;

/// Stable log tag — grep this to follow the enhancement stage.
const TAG: &str = "[VideoEnhance]";

/// Default source frame interval used until PTS deltas are observed.
const DEFAULT_DEADLINE_MS: f32 = 33.3;

/// Consecutive backend failures before enhancement gives up entirely.
const MAX_CONSECUTIVE_FAILURES: u32 = 5;

macro_rules! enhance_log {
    ($($arg:tt)*) => {
        eprintln!($($arg)*)
    };
}

/// A resolution + backend snapshot for the public diagnostics surface.
#[derive(Debug, Clone)]
pub struct EnhancementCapabilitiesSnapshot {
    pub supported: bool,
    pub backend: String,
    pub modes: Vec<EnhancementMode>,
    pub max_output_edge: u32,
    pub reason: String,
}

impl EnhancementCapabilitiesSnapshot {
    fn unsupported(reason: impl Into<String>) -> Self {
        let caps = EnhancementCapabilities::unsupported(reason);
        Self {
            supported: caps.supported,
            backend: caps.backend,
            modes: caps.modes,
            max_output_edge: caps.max_output_edge,
            reason: caps.reason,
        }
    }
}

fn capabilities_of(caps: &EnhancementCapabilities) -> EnhancementCapabilitiesSnapshot {
    EnhancementCapabilitiesSnapshot {
        supported: caps.supported,
        backend: caps.backend.clone(),
        modes: caps.modes.clone(),
        max_output_edge: caps.max_output_edge,
        reason: caps.reason.clone(),
    }
}

/// Answer used before the GPU probe runs: target/build truth, no device yet.
fn provisional_capabilities() -> EnhancementCapabilitiesSnapshot {
    if pixel_surface::enhance::enhancement_compiled_in() {
        EnhancementCapabilitiesSnapshot {
            supported: true,
            backend: "metal_wgpu".to_string(),
            modes: EnhancementMode::ALL.to_vec(),
            max_output_edge: plan::HIGH_QUALITY_MAX_EDGE,
            reason: "probe_pending".to_string(),
        }
    } else {
        EnhancementCapabilitiesSnapshot::unsupported(pixel_surface::enhance::unsupported_reason())
    }
}

/// Live enhancement state for diagnostics.
#[derive(Debug, Clone)]
pub struct EnhancementStatusSnapshot {
    pub supported: bool,
    pub requested_mode: EnhancementMode,
    pub active_mode: EnhancementMode,
    pub backend: String,
    pub path: String,
    pub scaler: String,
    pub input_width: u32,
    pub input_height: u32,
    pub output_width: u32,
    pub output_height: u32,
    pub last_frame_ms: f32,
    pub average_frame_ms: f32,
    pub deadline_ms: f32,
    pub deadline_misses: u64,
    pub hard_deadline_misses: u64,
    pub enhanced_frames: u64,
    pub bypassed_frames: u64,
    pub failed_frames: u64,
    pub passes: u32,
    pub fallback_reason: String,
    pub bypass_reason: String,
}

/// Owns the backend + policy for one playback engine.
///
/// The GPU backend is created **lazily**, on the first capability query or
/// mode request. Constructing a playback engine therefore never touches the
/// GPU, and an app that never enables enhancement never pays for a device.
pub struct VideoEnhancementRuntime {
    backend: Option<Box<dyn EnhancementBackend>>,
    /// Set when backend creation failed; the reason survives for diagnostics.
    backend_error: Option<String>,
    capabilities: EnhancementCapabilitiesSnapshot,
    policy: EnhancementPolicy,
    viewport: Option<FrameSize>,
    max_output_edge: Option<u32>,
    started: Instant,
    last_pts_ms: Option<i64>,
    pts_delta_ema_ms: f32,
    input_size: FrameSize,
    output_size: FrameSize,
    last_plan: Option<EnhancementPlan>,
    last_frame_ms: f32,
    last_path: String,
    last_passes: u32,
    enhanced_frames: u64,
    bypassed_frames: u64,
    failed_frames: u64,
    consecutive_failures: u32,
    fallback_reason: String,
    bypass_reason: String,
}

impl Default for VideoEnhancementRuntime {
    fn default() -> Self {
        Self::new()
    }
}

impl VideoEnhancementRuntime {
    pub fn new() -> Self {
        Self::with_backend(None)
    }

    /// Test seam: run the bridge against a scripted backend.
    #[cfg(test)]
    fn from_backend(backend: Box<dyn EnhancementBackend>) -> Self {
        Self::with_backend(Some(backend))
    }

    fn with_backend(backend: Option<Box<dyn EnhancementBackend>>) -> Self {
        let (backend, capabilities) = match backend {
            Some(backend) => {
                let caps = backend.capabilities();
                (Some(backend), capabilities_of(&caps))
            }
            // Not probed yet: report the build/target truth, which is
            // optimistic on Apple (Metal) and negative everywhere else.
            None => (None, provisional_capabilities()),
        };
        if capabilities.supported {
            enhance_log!(
                "{TAG} capability supported=true backend={} modes={:?} maxEdge={} note={}",
                capabilities.backend,
                capabilities.modes,
                capabilities.max_output_edge,
                if capabilities.reason.is_empty() {
                    "ready"
                } else {
                    &capabilities.reason
                }
            );
        } else {
            enhance_log!(
                "{TAG} capability supported=false backend={} reason={}",
                capabilities.backend,
                capabilities.reason
            );
        }
        Self {
            backend,
            backend_error: None,
            capabilities,
            policy: EnhancementPolicy::new(),
            viewport: None,
            max_output_edge: None,
            started: Instant::now(),
            last_pts_ms: None,
            pts_delta_ema_ms: 0.0,
            input_size: FrameSize::new(0, 0),
            output_size: FrameSize::new(0, 0),
            last_plan: None,
            last_frame_ms: 0.0,
            last_path: String::new(),
            last_passes: 0,
            enhanced_frames: 0,
            bypassed_frames: 0,
            failed_frames: 0,
            consecutive_failures: 0,
            fallback_reason: String::new(),
            bypass_reason: String::new(),
        }
    }

    /// Create the GPU backend on first use and cache the authoritative
    /// capability answer. Idempotent and cheap after the first call.
    fn ensure_backend(&mut self) {
        if self.backend.is_some() || self.backend_error.is_some() {
            return;
        }
        let backend = pixel_surface::enhance::create_backend();
        let caps = backend.capabilities();
        self.capabilities = capabilities_of(&caps);
        if caps.supported {
            self.backend = Some(backend);
            enhance_log!(
                "{TAG} capability supported=true backend={} modes={:?} maxEdge={}",
                self.capabilities.backend,
                self.capabilities.modes,
                self.capabilities.max_output_edge
            );
        } else {
            self.backend_error = Some(caps.reason.clone());
            enhance_log!(
                "{TAG} capability supported=false backend={} reason={}",
                self.capabilities.backend,
                self.capabilities.reason
            );
        }
    }

    pub fn capabilities(&mut self) -> &EnhancementCapabilitiesSnapshot {
        self.ensure_backend();
        &self.capabilities
    }

    /// Apply a new mode. Takes effect on the next presented frame — no media
    /// reopen, no engine restart, no queue flush.
    pub fn set_mode(&mut self, mode: EnhancementMode) -> bool {
        self.ensure_backend();
        self.policy.request(mode);
        self.policy.clamp_to(&self.capabilities.modes);
        let active = self.policy.effective();
        if !active.is_active() {
            // Drop pooled surfaces so disabling enhancement (or falling back
            // because the device cannot run it) gives the memory straight back.
            if let Some(backend) = self.backend.as_mut() {
                backend.release_pooled_resources();
            }
            self.output_size = FrameSize::new(0, 0);
        }
        if !self.capabilities.supported && mode.is_active() {
            self.fallback_reason = self.capabilities.reason.clone();
            enhance_log!(
                "{TAG} set_mode requested={} supported=false reason={}",
                mode,
                self.capabilities.reason
            );
            return false;
        }
        enhance_log!("{TAG} set_mode requested={} active={} (no reopen)", mode, active);
        true
    }

    /// Display box in device pixels. Drives the resolution-aware target plan.
    pub fn set_viewport(&mut self, width: u32, height: u32) {
        let next = if width > 0 && height > 0 {
            Some(FrameSize::new(width, height))
        } else {
            None
        };
        if self.viewport == next {
            return;
        }
        self.viewport = next;
        enhance_log!(
            "{TAG} viewport={:?} (target replanned for the next frame)",
            self.viewport
        );
    }

    /// Hard ceiling for the output longest edge (host override).
    pub fn set_max_output_edge(&mut self, edge: u32) {
        self.max_output_edge = if edge > 0 { Some(edge) } else { None };
    }

    /// The decoder output changed — drop timing history so a new resolution is
    /// measured on its own merits rather than inheriting the old budget.
    pub fn on_resolution_change(&mut self, width: u32, height: u32) {
        let next = FrameSize::new(width, height);
        if self.input_size == next {
            return;
        }
        self.input_size = next;
        self.policy.on_resolution_change();
        self.output_size = FrameSize::new(0, 0);
        self.last_plan = None;
    }

    /// A seek jumped the timeline: the next PTS delta would be meaningless.
    pub fn on_seek(&mut self) {
        self.last_pts_ms = None;
    }

    /// Reset per-source counters (not the mode, and not the device).
    pub fn on_source_change(&mut self) {
        if let Some(backend) = self.backend.as_mut() {
            backend.release_pooled_resources();
        }
        self.output_size = FrameSize::new(0, 0);
        self.last_plan = None;
        self.last_pts_ms = None;
        self.pts_delta_ema_ms = 0.0;
        self.input_size = FrameSize::new(0, 0);
        self.policy.on_resolution_change();
        self.bypass_reason.clear();
    }

    pub fn status(&self) -> EnhancementStatusSnapshot {
        EnhancementStatusSnapshot {
            supported: self.capabilities.supported,
            requested_mode: self.policy.requested(),
            active_mode: self.policy.effective(),
            backend: self.capabilities.backend.clone(),
            path: self.last_path.clone(),
            scaler: self
                .last_plan
                .map(|p| p.scaler)
                .unwrap_or(Scaler::None)
                .as_str()
                .to_string(),
            input_width: self.input_size.width,
            input_height: self.input_size.height,
            output_width: self.output_size.width,
            output_height: self.output_size.height,
            last_frame_ms: self.last_frame_ms,
            average_frame_ms: self.policy.average_frame_ms(),
            deadline_ms: self.policy.deadline_ms(),
            deadline_misses: self.policy.deadline_misses(),
            hard_deadline_misses: self.policy.hard_deadline_misses(),
            enhanced_frames: self.enhanced_frames,
            bypassed_frames: self.bypassed_frames,
            failed_frames: self.failed_frames,
            passes: self.last_passes,
            fallback_reason: self.reason(),
            bypass_reason: self.bypass_reason.clone(),
        }
    }

    /// Why enhancement is not running at the requested level, if it is not.
    fn reason(&self) -> String {
        if !self.capabilities.supported {
            return self.capabilities.reason.clone();
        }
        self.policy
            .fallback_reason()
            .map(str::to_string)
            .unwrap_or_else(|| self.fallback_reason.clone())
    }

    /// Plan for the current frame without running anything.
    ///
    /// Test seam: production reads the *result* of a plan through
    /// [`Self::enhance`] and [`Self::status`].
    #[cfg(test)]
    pub fn plan_for(&mut self, width: u32, height: u32) -> Option<EnhancementPlan> {
        self.ensure_backend();
        if self.backend.is_none() || !self.policy.effective().is_active() {
            return None;
        }
        let request = PlanRequest::new(self.policy.effective())
            .with_viewport(self.viewport)
            .with_max_output_edge(self.max_output_edge);
        Some(plan::plan(request, FrameSize::new(width, height)))
    }

    /// Enhancement entry point for the presentation path.
    ///
    /// Returns the `+1`-owned enhanced `CVPixelBuffer` pointer and its size,
    /// or `None` to present the decoded frame untouched. See the module docs
    /// for the pixel-buffer ownership contract.
    pub fn enhance(
        &mut self,
        pixel_buffer_ptr: u64,
        width: u32,
        height: u32,
        pts_ms: i64,
    ) -> Option<(u64, FrameSize)> {
        if pixel_buffer_ptr == 0 {
            return None;
        }
        self.ensure_backend();
        if self.backend.is_none() || !self.policy.effective().is_active() {
            return None;
        }
        self.on_resolution_change(width, height);

        let source = FrameSize::new(width, height);
        let request = PlanRequest::new(self.policy.effective())
            .with_viewport(self.viewport)
            .with_max_output_edge(self.max_output_edge);
        let plan = plan::plan(request, source);
        if !plan.is_active() {
            self.bypass_reason = plan.bypass_reason.unwrap_or("inactive").to_string();
            self.bypassed_frames += 1;
            return None;
        }
        self.bypass_reason.clear();

        let deadline_ms = self.frame_deadline_ms(pts_ms);

        // `ensure_backend` above guarantees `Some`.
        let backend = self.backend.as_mut()?;
        let outcome = backend.process(
            FrameHandle::CvPixelBuffer(pixel_buffer_ptr as usize),
            source,
            &plan,
        );

        match outcome {
            Ok(frame) => {
                let handle = match frame.handle {
                    FrameHandle::CvPixelBuffer(p) | FrameHandle::Raw(p) => p as u64,
                };
                if handle == 0 {
                    self.note_failure("backend returned a null surface");
                    return None;
                }
                self.consecutive_failures = 0;
                self.enhanced_frames += 1;
                self.last_frame_ms = frame.frame_ms;
                self.last_path = frame.path.to_string();
                self.last_passes = frame.passes;
                self.last_plan = Some(plan);
                self.output_size = frame.size;
                if frame.fresh_surface {
                    enhance_log!(
                        "{TAG} output surfaces allocated {}x{} (mode change / new size)",
                        frame.size.width,
                        frame.size.height
                    );
                }
                self.apply_policy(deadline_ms, frame.frame_ms);
                // On success the backend has already consumed the decoded
                // frame's retain; the caller presents `handle` instead.
                Some((handle, frame.size))
            }
            Err(err) => {
                self.note_failure(&err.to_string());
                None
            }
        }
    }

    fn apply_policy(&mut self, deadline_ms: f32, frame_ms: f32) {
        let now: Duration = self.started.elapsed();
        match self.policy.observe(now, frame_ms, deadline_ms) {
            PolicyAction::Downgrade(mode) => {
                enhance_log!(
                    "{TAG} QOS downgrade → {} ({} frame={:.2}ms deadline={:.2}ms)",
                    mode,
                    self.policy.fallback_reason().unwrap_or("deadline_pressure"),
                    frame_ms,
                    deadline_ms
                );
            }
            PolicyAction::Bypass => {
                if let Some(backend) = self.backend.as_mut() {
                    backend.release_pooled_resources();
                }
                self.output_size = FrameSize::new(0, 0);
                enhance_log!(
                    "{TAG} QOS bypass — enhancement off for this source \
                     ({} frame={:.2}ms deadline={:.2}ms)",
                    self.policy.fallback_reason().unwrap_or("deadline_exceeded"),
                    frame_ms,
                    deadline_ms
                );
            }
            PolicyAction::Recover(mode) => {
                enhance_log!("{TAG} QOS recovered → {mode}");
            }
            PolicyAction::Hold => {}
        }
    }

    fn note_failure(&mut self, reason: &str) {
        self.failed_frames += 1;
        self.consecutive_failures += 1;
        enhance_log!(
            "{TAG} frame failed ({} consecutive): {} — bypassing this frame",
            self.consecutive_failures,
            reason
        );
        if self.consecutive_failures >= MAX_CONSECUTIVE_FAILURES {
            self.policy
                .latch_fallback(format!("enhancement_unavailable: {reason}"));
            if let Some(backend) = self.backend.as_mut() {
                backend.release_pooled_resources();
            }
            self.output_size = FrameSize::new(0, 0);
            enhance_log!(
                "{TAG} disabled after {} consecutive failures — normal render path",
                self.consecutive_failures
            );
        }
    }

    /// Source frame interval in ms, smoothed from decoded PTS deltas.
    ///
    /// This is the deadline the enhancement stage is measured against: the
    /// time the source itself gives us to produce the next frame.
    fn frame_deadline_ms(&mut self, pts_ms: i64) -> f32 {
        if let Some(prev) = self.last_pts_ms {
            let delta = pts_ms - prev;
            if (4..=200).contains(&delta) {
                let delta = delta as f32;
                self.pts_delta_ema_ms = if self.pts_delta_ema_ms <= 0.0 {
                    delta
                } else {
                    self.pts_delta_ema_ms * 0.9 + delta * 0.1
                };
            }
        }
        self.last_pts_ms = Some(pts_ms);
        if self.pts_delta_ema_ms > 0.0 {
            self.pts_delta_ema_ms
        } else {
            DEFAULT_DEADLINE_MS
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use pixel_surface::enhance::EnhancementError;

    /// Backend stub so the bridge logic is testable on any machine.
    struct FakeBackend {
        supported: bool,
        fail: bool,
        calls: u32,
    }

    impl FakeBackend {
        fn new(supported: bool) -> Self {
            Self {
                supported,
                fail: false,
                calls: 0,
            }
        }

        fn failing() -> Self {
            Self {
                supported: true,
                fail: true,
                calls: 0,
            }
        }
    }

    impl EnhancementBackend for FakeBackend {
        fn backend_name(&self) -> String {
            "fake".to_string()
        }

        fn capabilities(&self) -> EnhancementCapabilities {
            if self.supported {
                EnhancementCapabilities {
                    supported: true,
                    backend: "fake".to_string(),
                    modes: EnhancementMode::ALL.to_vec(),
                    max_output_edge: plan::HIGH_QUALITY_MAX_EDGE,
                    reason: String::new(),
                }
            } else {
                EnhancementCapabilities::unsupported("no fake gpu")
            }
        }

        fn process(
            &mut self,
            _input: FrameHandle,
            _input_size: FrameSize,
            request: &EnhancementPlan,
        ) -> Result<pixel_surface::enhance::EnhancementFrame, EnhancementError> {
            self.calls += 1;
            if self.fail {
                return Err(EnhancementError::OutputUnavailable("fake failure".into()));
            }
            Ok(pixel_surface::enhance::EnhancementFrame {
                handle: FrameHandle::Raw(0xFACE_0000 + self.calls as usize),
                size: request.target,
                path: "fake_pass",
                passes: 1,
                scaler: request.scaler,
                frame_ms: 1.5,
                fresh_surface: self.calls == 1,
            })
        }

        fn release_pooled_resources(&mut self) {}
    }

    fn runtime() -> VideoEnhancementRuntime {
        VideoEnhancementRuntime::from_backend(Box::new(FakeBackend::new(true)))
    }

    #[test]
    fn default_mode_is_off_and_off_never_touches_a_frame() {
        let mut rt = runtime();
        assert_eq!(rt.status().requested_mode, EnhancementMode::Off);
        assert_eq!(rt.status().active_mode, EnhancementMode::Off);
        assert!(rt.enhance(0xDEAD, 1280, 720, 0).is_none());
        let status = rt.status();
        assert_eq!(status.enhanced_frames, 0);
        assert_eq!(status.failed_frames, 0);
    }

    #[test]
    fn switching_modes_is_live_and_never_reopens_anything() {
        let mut rt = runtime();
        rt.set_mode(EnhancementMode::HighQuality);
        assert_eq!(rt.status().requested_mode, EnhancementMode::HighQuality);
        rt.set_viewport(1920, 1080);
        // 720p → 1080p is the documented Enhanced/HighQuality behaviour.
        let plan = rt.plan_for(1280, 720).expect("supported device plans work");
        assert_eq!(plan.target, FrameSize::new(1920, 1080));
        assert_eq!(plan.scaler, Scaler::Lanczos3);

        rt.set_mode(EnhancementMode::Sharp);
        let plan = rt.plan_for(1280, 720).expect("sharp plans");
        assert_eq!(plan.target, FrameSize::new(1280, 720));
        assert_eq!(plan.scaler, Scaler::None);

        rt.set_mode(EnhancementMode::Off);
        assert!(rt.plan_for(1280, 720).is_none());
        assert_eq!(rt.status().active_mode, EnhancementMode::Off);
    }

    #[test]
    fn enhancement_runs_through_the_backend_and_reports_resolutions() {
        let mut rt = runtime();
        rt.set_mode(EnhancementMode::Enhanced);
        rt.set_viewport(1920, 1080);
        let (out, size) = rt
            .enhance(0x1000, 854, 480, 0)
            .expect("enhanced frame");
        assert_ne!(out, 0x1000);
        assert_eq!(size, FrameSize::new(1920, 1080));
        let status = rt.status();
        assert_eq!(status.enhanced_frames, 1);
        assert_eq!((status.input_width, status.input_height), (854, 480));
        assert_eq!((status.output_width, status.output_height), (1920, 1080));
        assert_eq!(status.path, "fake_pass");
        assert!(status.last_frame_ms > 0.0);
    }

    #[test]
    fn a_failing_backend_bypasses_frames_and_then_gives_up() {
        let mut rt = VideoEnhancementRuntime::from_backend(Box::new(FakeBackend::failing()));
        rt.set_mode(EnhancementMode::Enhanced);
        for _ in 0..MAX_CONSECUTIVE_FAILURES {
            assert!(rt.enhance(0x2000, 1280, 720, 0).is_none());
        }
        let status = rt.status();
        assert_eq!(status.failed_frames, MAX_CONSECUTIVE_FAILURES as u64);
        assert_eq!(status.active_mode, EnhancementMode::Off);
        assert!(status.fallback_reason.starts_with("enhancement_unavailable"));
        // Re-requesting re-arms the ladder (a user action always wins).
        rt.set_mode(EnhancementMode::Enhanced);
        assert_eq!(rt.status().active_mode, EnhancementMode::Enhanced);
    }

    #[test]
    fn an_unsupported_backend_reports_it_and_never_enhances() {
        let mut rt = VideoEnhancementRuntime::from_backend(Box::new(FakeBackend::new(false)));
        assert!(!rt.capabilities().supported);
        assert!(!rt.set_mode(EnhancementMode::HighQuality));
        assert!(rt.enhance(0x3000, 1280, 720, 0).is_none());
        assert!(rt.plan_for(1280, 720).is_none());
        assert_eq!(rt.status().fallback_reason, "no fake gpu");
    }

    #[test]
    fn an_unsupported_mode_falls_back_to_the_best_supported_one() {
        let mut rt = runtime();
        rt.set_mode(EnhancementMode::HighQuality);
        // Simulate a device that only offers Off + Sharp.
        rt.policy
            .clamp_to(&[EnhancementMode::Off, EnhancementMode::Sharp]);
        assert_eq!(rt.status().active_mode, EnhancementMode::Sharp);
        rt.policy.clamp_to(&[EnhancementMode::Off]);
        assert_eq!(rt.status().active_mode, EnhancementMode::Off);
        assert_eq!(rt.status().fallback_reason, "mode_not_supported");
    }

    #[test]
    fn status_reports_input_and_output_resolution() {
        let mut rt = runtime();
        rt.set_mode(EnhancementMode::Enhanced);
        rt.set_viewport(1920, 1080);
        rt.on_resolution_change(854, 480);
        let status = rt.status();
        assert_eq!((status.input_width, status.input_height), (854, 480));
        assert_eq!(status.requested_mode, EnhancementMode::Enhanced);
    }

    #[test]
    fn deadline_tracks_the_source_frame_interval() {
        let mut rt = runtime();
        assert_eq!(rt.frame_deadline_ms(0), DEFAULT_DEADLINE_MS);
        // 30 fps cadence.
        for i in 1..60 {
            rt.frame_deadline_ms(i * 33);
        }
        let deadline = rt.frame_deadline_ms(60 * 33);
        assert!((deadline - 33.0).abs() < 1.0, "got {deadline}");
    }

    #[test]
    fn seeks_do_not_poison_the_deadline() {
        let mut rt = runtime();
        for i in 1..60 {
            rt.frame_deadline_ms(i * 33);
        }
        let before = rt.frame_deadline_ms(60 * 33);
        assert!((before - 33.0).abs() < 1.0, "got {before}");
        // A seek punches the PTS far forward without changing the cadence.
        rt.frame_deadline_ms(600_000);
        let after_jump = rt.frame_deadline_ms(600_400);
        assert!((after_jump - 33.0).abs() < 1.0, "got {after_jump}");
        // After `on_seek` the tracker re-seeds from the next real interval.
        rt.on_seek();
        assert_eq!(rt.frame_deadline_ms(600_410), 33.0);
    }

    #[test]
    fn disabling_releases_pooled_surfaces_and_re_enabling_replans() {
        let mut rt = runtime();
        rt.set_mode(EnhancementMode::HighQuality);
        rt.set_viewport(1920, 1080);
        rt.set_mode(EnhancementMode::Off);
        rt.set_mode(EnhancementMode::HighQuality);
        let plan = rt.plan_for(1280, 720).expect("plans after re-enable");
        assert_eq!(plan.target, FrameSize::new(1920, 1080));
    }

    #[test]
    fn null_handles_are_rejected_without_counting_as_failures() {
        let mut rt = runtime();
        rt.set_mode(EnhancementMode::Enhanced);
        assert!(rt.enhance(0, 1280, 720, 0).is_none());
        assert_eq!(rt.status().failed_frames, 0);
    }

    #[test]
    fn four_k_source_in_a_small_window_is_bypassed_with_a_reason() {
        let mut rt = runtime();
        rt.set_mode(EnhancementMode::HighQuality);
        rt.set_viewport(1280, 720);
        assert!(rt.enhance(0x1234, 3840, 2160, 0).is_none());
        let status = rt.status();
        assert_eq!(status.bypass_reason, "display_smaller_than_source");
        assert_eq!(status.bypassed_frames, 1);
    }

    #[test]
    fn quality_ladder_downgrades_under_pressure_without_oscillating() {
        let mut rt = runtime();
        rt.set_mode(EnhancementMode::HighQuality);
        rt.set_viewport(3840, 2160);
        // 60 fps source (16.6 ms deadline) where every enhancement costs 40 ms.
        let mut now = Duration::ZERO;
        for _ in 0..40 {
            now += Duration::from_millis(200);
            rt.policy.observe(now, 40.0, 16.6);
        }
        assert_eq!(rt.policy.effective(), EnhancementMode::Off);
        assert_eq!(rt.policy.fallback_reason(), Some("deadline_exceeded"));
        assert!(rt.policy.downgrade_count() >= 3);
    }
}
