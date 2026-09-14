//! GPU video enhancement (experimental).
//!
//! A backend-agnostic upscale / detail-enhancement stage that runs between
//! hardware decode and presentation. The Apple backend (`metal`) executes a
//! wgpu compute pipeline directly on the decode IOSurface: the decoded
//! `CVPixelBuffer` is imported as a GPU texture, scaled and sharpened on the
//! GPU, and written into another IOSurface that is handed back to Flutter's
//! `Texture` widget. There is no CPU pixel copy and no RGBA round-trip.
//!
//! Layout:
//!
//! * [`plan`] — resolution-aware target planning (pure, unit-tested).
//! * [`policy`] — deadline-aware mode selection with anti-oscillation
//!   hysteresis (pure, unit-tested).
//! * [`metal`] — the Apple wgpu backend (feature `gpu`).
//!
//! Everything except `metal` compiles on every platform, which keeps the
//! public configuration surface identical across backends.

pub mod plan;
pub mod policy;

#[cfg(all(target_vendor = "apple", feature = "gpu"))]
mod metal;

use std::fmt;

/// Requested enhancement quality level.
///
/// The numeric order is the quality order: higher variants may run more GPU
/// passes and reach a larger output resolution.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Default)]
pub enum EnhancementMode {
    /// Untouched render path. No GPU work, no extra texture.
    #[default]
    Off,
    /// Single-pass contrast-adaptive sharpen at native size. For sources that
    /// are already close to display resolution.
    Sharp,
    /// High-quality 2D upscale plus adaptive sharpening and a light dither.
    Enhanced,
    /// Separable Lanczos-3 upscale plus adaptive sharpening and dithering —
    /// the best non-AI quality that fits a real-time frame budget.
    HighQuality,
}

impl EnhancementMode {
    pub const ALL: [EnhancementMode; 4] = [
        EnhancementMode::Off,
        EnhancementMode::Sharp,
        EnhancementMode::Enhanced,
        EnhancementMode::HighQuality,
    ];

    /// Stable wire name (used by logs, diagnostics and FRB conversion).
    pub fn as_str(self) -> &'static str {
        match self {
            EnhancementMode::Off => "off",
            EnhancementMode::Sharp => "sharp",
            EnhancementMode::Enhanced => "enhanced",
            EnhancementMode::HighQuality => "high_quality",
        }
    }

    /// Parse the stable wire name. Unknown input yields [`EnhancementMode::Off`]
    /// so an unrecognized request can never weaken playback safety.
    pub fn from_wire(value: &str) -> EnhancementMode {
        match value {
            "sharp" => EnhancementMode::Sharp,
            "enhanced" => EnhancementMode::Enhanced,
            "high_quality" => EnhancementMode::HighQuality,
            _ => EnhancementMode::Off,
        }
    }

    /// One step down the quality ladder (Off is the floor).
    pub fn step_down(self) -> EnhancementMode {
        match self {
            EnhancementMode::Off => EnhancementMode::Off,
            EnhancementMode::Sharp => EnhancementMode::Off,
            EnhancementMode::Enhanced => EnhancementMode::Sharp,
            EnhancementMode::HighQuality => EnhancementMode::Enhanced,
        }
    }

    /// One step up the quality ladder (HighQuality is the ceiling).
    pub fn step_up(self) -> EnhancementMode {
        match self {
            EnhancementMode::Off => EnhancementMode::Sharp,
            EnhancementMode::Sharp => EnhancementMode::Enhanced,
            EnhancementMode::Enhanced => EnhancementMode::HighQuality,
            EnhancementMode::HighQuality => EnhancementMode::HighQuality,
        }
    }

    /// True when the mode performs GPU work.
    pub fn is_active(self) -> bool {
        !matches!(self, EnhancementMode::Off)
    }
}

impl fmt::Display for EnhancementMode {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.as_str())
    }
}

/// Source frame dimensions.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct FrameSize {
    pub width: u32,
    pub height: u32,
}

impl FrameSize {
    pub const fn new(width: u32, height: u32) -> Self {
        Self { width, height }
    }

    pub fn is_valid(&self) -> bool {
        self.width > 0 && self.height > 0
    }

    /// Longest edge in pixels.
    pub fn max_edge(&self) -> u32 {
        self.width.max(self.height)
    }

    pub fn size_tuple(&self) -> (u32, u32) {
        (self.width, self.height)
    }

    pub fn pixel_count(&self) -> u64 {
        self.width as u64 * self.height as u64
    }
}

/// What a backend can do on this device.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EnhancementCapabilities {
    pub supported: bool,
    /// Human-readable backend name, e.g. `metal_wgpu`.
    pub backend: String,
    /// Modes the backend will actually run. Always contains
    /// [`EnhancementMode::Off`].
    pub modes: Vec<EnhancementMode>,
    /// Largest output edge the backend will produce.
    pub max_output_edge: u32,
    /// Why enhancement is unavailable (empty when `supported`).
    pub reason: String,
}

impl EnhancementCapabilities {
    /// Capability record for a platform with no enhancement backend.
    pub fn unsupported(reason: impl Into<String>) -> Self {
        Self {
            supported: false,
            backend: "none".to_string(),
            modes: vec![EnhancementMode::Off],
            max_output_edge: 0,
            reason: reason.into(),
        }
    }

    pub fn supports(&self, mode: EnhancementMode) -> bool {
        self.modes.contains(&mode)
    }
}

/// A GPU-visible frame handle, abstracted so future backends (Vulkan via
/// `AHardwareBuffer`, D3D12 via shared NT handles) reuse the same API.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FrameHandle {
    /// Apple `CVPixelBufferRef`, IOSurface-backed, BGRA8. Never owned — the
    /// caller keeps its retain for the duration of the call.
    CvPixelBuffer(usize),
    /// Raw handle with no backend-specific interpretation, for tests.
    Raw(usize),
}

impl FrameHandle {
    pub fn is_null(&self) -> bool {
        match self {
            FrameHandle::CvPixelBuffer(p) | FrameHandle::Raw(p) => *p == 0,
        }
    }
}

/// A completed enhancement result: the GPU-written output surface plus what
/// actually ran, for diagnostics.
#[derive(Debug, Clone)]
pub struct EnhancementFrame {
    /// Output surface. Carries a `+1` retain the caller owns.
    pub handle: FrameHandle,
    pub size: FrameSize,
    /// Name of the executed path, e.g. `metal_lanczos_cas`.
    pub path: &'static str,
    /// GPU passes issued for this frame.
    pub passes: u32,
    /// Scaler actually used.
    pub scaler: plan::Scaler,
    /// Wall time of the whole stage (encode + submit + GPU completion), in ms.
    pub frame_ms: f32,
    /// True when the output surface is a fresh allocation rather than a
    /// recycled pool entry (observability for jank investigations).
    pub fresh_surface: bool,
}

/// Errors a backend can report. All of them are recoverable: the caller
/// bypasses enhancement and keeps playing.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum EnhancementError {
    /// No backend for this platform / build.
    Unsupported(String),
    /// The device cannot run the pipeline (feature missing, device lost).
    DeviceUnavailable(String),
    /// This particular frame could not be imported.
    InputUnavailable(String),
    /// Output surface allocation failed (out of IOSurface memory).
    OutputUnavailable(String),
}

impl fmt::Display for EnhancementError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            EnhancementError::Unsupported(m) => write!(f, "unsupported: {m}"),
            EnhancementError::DeviceUnavailable(m) => write!(f, "device unavailable: {m}"),
            EnhancementError::InputUnavailable(m) => write!(f, "input unavailable: {m}"),
            EnhancementError::OutputUnavailable(m) => write!(f, "output unavailable: {m}"),
        }
    }
}

impl std::error::Error for EnhancementError {}

/// Anything that can render an enhanced frame.
///
/// Implementations must be usable from a single thread at a time; callers
/// serialize calls (the playback engine holds one instance behind a mutex).
pub trait EnhancementBackend: Send {
    /// Backend identity for diagnostics, e.g. `metal_wgpu`.
    fn backend_name(&self) -> String;

    /// Device + pipeline capabilities. Called once per device.
    fn capabilities(&self) -> EnhancementCapabilities;

    /// Render `input` at `request.target`, returning the output surface.
    ///
    /// `input` is borrowed: the backend must not release the caller's retain
    /// on a failure path. On success the backend **consumes** that retain,
    /// because the caller is expected to present the returned frame instead
    /// of the decoded one. The returned [`EnhancementFrame::handle`] carries
    /// a fresh `+1` retain that the caller owns and must release (or hand to
    /// the presentation layer).
    fn process(
        &mut self,
        input: FrameHandle,
        input_size: FrameSize,
        request: &plan::EnhancementPlan,
    ) -> Result<EnhancementFrame, EnhancementError>;

    /// Drop cached output surfaces and scratch textures. Called when
    /// enhancement is disabled or the player is released.
    fn release_pooled_resources(&mut self);
}

/// Backend for platforms without an enhancement implementation. Reports
/// `supported == false` and never touches a frame, which is exactly what the
/// player needs to keep the untouched render path.
pub struct NullBackend {
    reason: String,
}

impl NullBackend {
    pub fn new(reason: impl Into<String>) -> Self {
        Self {
            reason: reason.into(),
        }
    }
}

impl EnhancementBackend for NullBackend {
    fn backend_name(&self) -> String {
        "none".to_string()
    }

    fn capabilities(&self) -> EnhancementCapabilities {
        EnhancementCapabilities::unsupported(self.reason.clone())
    }

    fn process(
        &mut self,
        _input: FrameHandle,
        _input_size: FrameSize,
        _request: &plan::EnhancementPlan,
    ) -> Result<EnhancementFrame, EnhancementError> {
        Err(EnhancementError::Unsupported(self.reason.clone()))
    }

    fn release_pooled_resources(&mut self) {}
}

/// Create the best backend for the current platform.
///
/// Never fails: an unavailable backend is reported through
/// [`EnhancementCapabilities::supported`], and the caller keeps the normal
/// render path.
pub fn create_backend() -> Box<dyn EnhancementBackend> {
    #[cfg(all(target_vendor = "apple", feature = "gpu"))]
    {
        match metal::MetalEnhancementBackend::new() {
            Ok(backend) => return Box::new(backend),
            Err(reason) => return Box::new(NullBackend::new(reason)),
        }
    }
    #[cfg(not(all(target_vendor = "apple", feature = "gpu")))]
    {
        Box::new(NullBackend::new(unsupported_reason()))
    }
}

/// Why the default backend is unavailable on this target/feature set.
pub fn unsupported_reason() -> String {
    #[cfg(not(target_vendor = "apple"))]
    {
        "video enhancement backend is Apple-only in this release (Metal); \
         Android/Vulkan/Windows backends are not implemented yet"
            .to_string()
    }
    #[cfg(all(target_vendor = "apple", not(feature = "gpu")))]
    {
        "pixel_surface was built without the `gpu` feature".to_string()
    }
    #[cfg(all(target_vendor = "apple", feature = "gpu"))]
    {
        format!("{}: {}", metal::BACKEND_NAME, "backend unavailable")
    }
}

/// True when an enhancement backend is compiled in for this platform.
pub fn enhancement_compiled_in() -> bool {
    cfg!(all(target_vendor = "apple", feature = "gpu"))
}
