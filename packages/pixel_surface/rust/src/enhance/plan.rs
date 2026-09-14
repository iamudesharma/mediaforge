//! Resolution-aware enhancement planning.
//!
//! Pure functions only — no GPU, no platform types. This is where the
//! "what should we do for a 480p source on a 1080p display" policy lives, so
//! it can be unit-tested without a device and reused by every backend.
//!
//! # Policy
//!
//! | Source height | Behaviour |
//! | --- | --- |
//! | ≤ 576 (480p class) | strong upscale toward the display, moderate sharpen |
//! | ≤ 800 (720p class) | high-quality upscale, moderate sharpen |
//! | ≤ 1200 (1080p class) | only upscales when the display asks for more; light sharpen |
//! | > 1200 (1440p/4K class) | minimal: 1:1 or bypass — never upscale a 4K source |
//!
//! Two independent safety rails, both honest about *why* they fired:
//!
//! * `minimal` — a 4K-class source is never upscaled and only lightly
//!   sharpened (requirement: do not destroy grain/detail at high res).
//! * `display_smaller_than_source` — a 1440p+ source shown in a smaller
//!   viewport gains nothing from a GPU pass, so it is bypassed entirely
//!   rather than spending the frame budget on an invisible effect.

use super::{EnhancementMode, FrameSize};

/// Output longest-edge ceilings per mode. `Sharp` never scales, so it has no
/// ceiling beyond the source.
pub const ENHANCED_MAX_EDGE: u32 = 1920;
pub const HIGH_QUALITY_MAX_EDGE: u32 = 3840;

/// Source height at or above which enhancement becomes minimal / bypassed.
pub const HIGH_RESOLUTION_SOURCE_HEIGHT: u32 = 1200;

/// Smallest upscale ratio worth a scaling pass. Below this the scaler would
/// resample by less than a pixel per row and the extra passes cost more than
/// they show; the sharpen pass alone is a better trade.
pub const MIN_UPSCALE_RATIO: f32 = 1.06;

/// Which resampling kernel a plan selected.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Scaler {
    /// No resampling: the input is read at 1:1.
    None,
    /// 4×4 Catmull-Rom. Cheap, no ringing.
    CatmullRom,
    /// Separable 6-tap Lanczos-3. Sharper, used for the best-quality tier.
    Lanczos3,
}

impl Scaler {
    pub fn as_str(self) -> &'static str {
        match self {
            Scaler::None => "none",
            Scaler::CatmullRom => "catmull_rom",
            Scaler::Lanczos3 => "lanczos3",
        }
    }
}

/// Inputs to a planning decision.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct PlanRequest {
    pub mode: EnhancementMode,
    /// Display box in device pixels, when the host knows it.
    pub viewport: Option<FrameSize>,
    /// Hard ceiling for the output longest edge (`None` = mode default).
    pub max_output_edge: Option<u32>,
}

impl PlanRequest {
    pub fn new(mode: EnhancementMode) -> Self {
        Self {
            mode,
            viewport: None,
            max_output_edge: None,
        }
    }

    pub fn with_viewport(mut self, viewport: Option<FrameSize>) -> Self {
        self.viewport = viewport.filter(|v| v.is_valid());
        self
    }

    pub fn with_max_output_edge(mut self, edge: Option<u32>) -> Self {
        self.max_output_edge = edge.filter(|e| *e > 0);
        self
    }
}

/// A fully resolved decision: what to render and why.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct EnhancementPlan {
    pub mode: EnhancementMode,
    pub source: FrameSize,
    pub target: FrameSize,
    pub scaler: Scaler,
    /// Contrast-adaptive sharpening strength in `0.0..=1.0`.
    pub sharpen: f32,
    /// Output dither amplitude in LSB (0.0 disables the dither stage).
    pub dither: f32,
    /// `Some` when the plan intentionally does nothing.
    pub bypass_reason: Option<&'static str>,
}

impl EnhancementPlan {
    /// True when a GPU pass must be issued for this frame.
    pub fn is_active(&self) -> bool {
        self.bypass_reason.is_none() && self.mode.is_active() && self.source.is_valid()
    }

    /// True when the plan resamples (as opposed to sharpen-only).
    pub fn is_scaling(&self) -> bool {
        !matches!(self.scaler, Scaler::None)
    }

    /// Output/source longest-edge ratio.
    pub fn upscale_ratio(&self) -> f32 {
        if self.source.max_edge() == 0 {
            return 1.0;
        }
        self.target.max_edge() as f32 / self.source.max_edge() as f32
    }

    /// A plan that does nothing, for a specific reason.
    fn bypass(mode: EnhancementMode, source: FrameSize, reason: &'static str) -> Self {
        Self {
            mode,
            source,
            target: source,
            scaler: Scaler::None,
            sharpen: 0.0,
            dither: 0.0,
            bypass_reason: Some(reason),
        }
    }
}

/// Resolve `request` for a source frame of `source` pixels.
pub fn plan(request: PlanRequest, source: FrameSize) -> EnhancementPlan {
    let mode = request.mode;

    if !source.is_valid() {
        return EnhancementPlan::bypass(mode, source, "invalid_source_size");
    }
    if !mode.is_active() {
        return EnhancementPlan::bypass(mode, source, "mode_off");
    }

    let high_resolution = source.height >= HIGH_RESOLUTION_SOURCE_HEIGHT;
    let viewport = request.viewport;

    // 4K-class source in a smaller viewport: the rasterizer downscales anyway
    // and a GPU pass cannot add detail that the decoder did not produce.
    if high_resolution {
        if let Some(vp) = viewport {
            if (vp.max_edge() as f32) < source.max_edge() as f32 * 0.92 {
                return EnhancementPlan::bypass(mode, source, "display_smaller_than_source");
            }
        }
    }

    // Sharp is a 1:1 detail pass by definition.
    if mode == EnhancementMode::Sharp {
        let sharpen = base_sharpen(source, false);
        return EnhancementPlan {
            mode,
            source,
            target: source,
            scaler: Scaler::None,
            sharpen,
            dither: 0.0,
            bypass_reason: None,
        };
    }

    let cap_edge = request
        .max_output_edge
        .unwrap_or(match mode {
            EnhancementMode::HighQuality => HIGH_QUALITY_MAX_EDGE,
            _ => ENHANCED_MAX_EDGE,
        })
        .max(source.max_edge());

    // A high-resolution source is never upscaled: keep the target at source
    // size and only run the light sharpen pass.
    let desired = if high_resolution {
        source
    } else {
        match viewport {
            Some(vp) => fit_into(source, vp, cap_edge),
            // No viewport hint: aim for the mode ceiling, bounded by the cap.
            None => scale_to_edge(source, cap_edge),
        }
    };

    // Never go below the source (no GPU downscale — the rasterizer owns that).
    let target = if desired.max_edge() < source.max_edge() {
        source
    } else {
        desired
    };

    let ratio = target.max_edge() as f32 / source.max_edge() as f32;
    let scaler = if ratio < MIN_UPSCALE_RATIO {
        Scaler::None
    } else {
        match mode {
            EnhancementMode::HighQuality => Scaler::Lanczos3,
            _ => Scaler::CatmullRom,
        }
    };

    let sharpen = base_sharpen(source, scaler != Scaler::None);
    let dither = match mode {
        EnhancementMode::HighQuality => 0.75,
        EnhancementMode::Enhanced => 0.5,
        _ => 0.0,
    };

    EnhancementPlan {
        mode,
        source,
        target,
        scaler,
        sharpen,
        dither,
        bypass_reason: None,
    }
}

/// Contrast-adaptive sharpening strength.
///
/// Higher for low-resolution sources (which are soft to begin with) and
/// lower as resolution grows, so 1080p/4K detail is not over-sharpened.
/// A scaler adds interpolation softening, which earns a small bump.
fn base_sharpen(source: FrameSize, scaled: bool) -> f32 {
    let base: f32 = if source.height <= 576 {
        0.62
    } else if source.height <= 800 {
        0.55
    } else if source.height <= HIGH_RESOLUTION_SOURCE_HEIGHT {
        0.45
    } else if source.height <= 1600 {
        0.36
    } else {
        0.28
    };
    if scaled {
        (base + 0.05).min(0.85)
    } else {
        base
    }
}

/// Largest `source`-aspect box that fits inside `viewport`.
fn fit_into(source: FrameSize, viewport: FrameSize, cap_edge: u32) -> FrameSize {
    let src_ar = source.width as f64 / source.height as f64;
    let vp_ar = viewport.width as f64 / viewport.height as f64;
    let (w, h) = if vp_ar >= src_ar {
        // Viewport is wider: height is the limiting dimension.
        let h = viewport.height as f64;
        (h * src_ar, h)
    } else {
        let w = viewport.width as f64;
        (w, w / src_ar)
    };
    apply_edge_cap(
        normalize(FrameSize::new(w.round() as u32, h.round() as u32)),
        cap_edge,
    )
}

/// Scale `source` up so its longest edge reaches `edge`, preserving aspect.
fn scale_to_edge(source: FrameSize, edge: u32) -> FrameSize {
    if source.max_edge() >= edge {
        return source;
    }
    let ratio = edge as f64 / source.max_edge() as f64;
    normalize(FrameSize::new(
        (source.width as f64 * ratio).round() as u32,
        (source.height as f64 * ratio).round() as u32,
    ))
}

/// Shrink uniformly so the longest edge is at most `cap`.
fn apply_edge_cap(size: FrameSize, cap: u32) -> FrameSize {
    if size.max_edge() <= cap || size.max_edge() == 0 {
        return size;
    }
    let ratio = cap as f64 / size.max_edge() as f64;
    normalize(FrameSize::new(
        (size.width as f64 * ratio).round() as u32,
        (size.height as f64 * ratio).round() as u32,
    ))
}

/// Round to even, minimum 2. Even sizes keep every IOSurface / texture pitch
/// sane and avoid half-texel offsets in the separable passes.
fn normalize(size: FrameSize) -> FrameSize {
    let even = |v: u32| {
        let v = v.max(2);
        if v % 2 == 0 {
            v
        } else {
            v + 1
        }
    };
    FrameSize::new(even(size.width), even(size.height))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn vp(width: u32, height: u32) -> Option<FrameSize> {
        Some(FrameSize::new(width, height))
    }

    #[test]
    fn off_mode_never_plans_work() {
        for source in [
            FrameSize::new(854, 480),
            FrameSize::new(1280, 720),
            FrameSize::new(1920, 1080),
            FrameSize::new(3840, 2160),
        ] {
            let p = plan(PlanRequest::new(EnhancementMode::Off).with_viewport(vp(3840, 2160)), source);
            assert!(!p.is_active(), "off must never be active for {source:?}");
            assert_eq!(p.bypass_reason, Some("mode_off"));
            assert_eq!(p.target, source);
        }
    }

    #[test]
    fn sharp_is_one_to_one() {
        let source = FrameSize::new(1280, 720);
        let p = plan(PlanRequest::new(EnhancementMode::Sharp).with_viewport(vp(3840, 2160)), source);
        assert!(p.is_active());
        assert_eq!(p.target, source);
        assert_eq!(p.scaler, Scaler::None);
        assert!(p.sharpen > 0.0);
        assert_eq!(p.dither, 0.0, "sharp must not add dither noise");
    }

    #[test]
    fn low_resolution_upscales_to_display_ceiling() {
        // 480p on a 1080p display (the benchmark matrix case).
        let p = plan(
            PlanRequest::new(EnhancementMode::Enhanced).with_viewport(vp(1920, 1080)),
            FrameSize::new(854, 480),
        );
        assert!(p.is_active());
        assert_eq!(p.target, FrameSize::new(1920, 1080));
        assert_eq!(p.scaler, Scaler::CatmullRom);
        assert!(p.sharpen > 0.5, "480p gets the strongest sharpen");
    }

    #[test]
    fn enhanced_caps_at_1080p_class() {
        // 720p on a 4K display: Enhanced stays inside its 1080p ceiling.
        let p = plan(
            PlanRequest::new(EnhancementMode::Enhanced).with_viewport(vp(3840, 2160)),
            FrameSize::new(1280, 720),
        );
        assert_eq!(p.target.max_edge(), ENHANCED_MAX_EDGE);
        assert_eq!(p.target, FrameSize::new(1920, 1080));
    }

    #[test]
    fn high_quality_reaches_4k() {
        for (src, want) in [
            (FrameSize::new(1280, 720), FrameSize::new(3840, 2160)),
            (FrameSize::new(1920, 1080), FrameSize::new(3840, 2160)),
        ] {
            let p = plan(
                PlanRequest::new(EnhancementMode::HighQuality).with_viewport(vp(3840, 2160)),
                src,
            );
            assert_eq!(p.target, want, "source {src:?}");
            assert_eq!(p.scaler, Scaler::Lanczos3);
        }
    }

    #[test]
    fn ascpect_ratio_is_preserved() {
        // 4:3 source in a 16:9 viewport must letterbox, not stretch.
        let source = FrameSize::new(640, 480);
        let p = plan(
            PlanRequest::new(EnhancementMode::Enhanced).with_viewport(vp(1920, 1080)),
            source,
        );
        let src_ar = source.width as f32 / source.height as f32;
        let out_ar = p.target.width as f32 / p.target.height as f32;
        assert!((src_ar - out_ar).abs() < 0.01, "{src_ar} vs {out_ar}");
        assert!(p.target.height <= 1080);
    }

    #[test]
    fn portrait_sources_are_normalized_to_even_dimensions() {
        // 9:16 portrait upscaled to fill a portrait display.
        let p = plan(
            PlanRequest::new(EnhancementMode::HighQuality).with_viewport(vp(1080, 1920)),
            FrameSize::new(853, 479),
        );
        assert!(p.is_scaling(), "portrait source must upscale, got {:?}", p);
        assert_eq!(p.target.max_edge() % 2, 0);
        assert_eq!(p.target.height % 2, 0);
        let src_ar = 853.0 / 479.0;
        let out_ar = p.target.width as f32 / p.target.height as f32;
        assert!((src_ar - out_ar).abs() < 0.01);
    }

    #[test]
    fn one_to_one_plans_keep_the_exact_source_size() {
        // No resampling means no rounding: odd source sizes pass through.
        let source = FrameSize::new(1079, 1919);
        let p = plan(
            PlanRequest::new(EnhancementMode::Sharp).with_viewport(vp(1080, 1920)),
            source,
        );
        assert_eq!(p.target, source);
        assert!(!p.is_scaling());
    }

    #[test]
    fn four_k_source_bypasses_when_display_is_smaller() {
        let p = plan(
            PlanRequest::new(EnhancementMode::HighQuality).with_viewport(vp(1280, 720)),
            FrameSize::new(3840, 2160),
        );
        assert!(!p.is_active());
        assert_eq!(p.bypass_reason, Some("display_smaller_than_source"));
    }

    #[test]
    fn four_k_source_on_4k_display_sharpens_minimally_without_upscaling() {
        let p = plan(
            PlanRequest::new(EnhancementMode::Enhanced).with_viewport(vp(3840, 2160)),
            FrameSize::new(3840, 2160),
        );
        assert!(p.is_active());
        assert_eq!(p.scaler, Scaler::None);
        assert_eq!(p.target, FrameSize::new(3840, 2160));
        assert!(p.sharpen <= 0.30, "4K must stay minimal, got {}", p.sharpen);
    }

    #[test]
    fn no_viewport_uses_mode_ceiling() {
        let p = plan(PlanRequest::new(EnhancementMode::HighQuality), FrameSize::new(1280, 720));
        assert_eq!(p.target.max_edge(), HIGH_QUALITY_MAX_EDGE);
    }

    #[test]
    fn max_output_edge_override_wins_but_never_downscales() {
        let p = plan(
            PlanRequest::new(EnhancementMode::HighQuality)
                .with_viewport(vp(3840, 2160))
                .with_max_output_edge(Some(1280)),
            FrameSize::new(1280, 720),
        );
        assert_eq!(p.target, FrameSize::new(1280, 720));
        assert_eq!(p.scaler, Scaler::None);
    }

    #[test]
    fn near_native_ratio_skips_the_scaling_passes() {
        // 1080p → 1120p is below the scaler threshold: sharpen only.
        let p = plan(
            PlanRequest::new(EnhancementMode::HighQuality).with_viewport(vp(1120, 630)),
            FrameSize::new(1920, 1080),
        );
        assert_eq!(p.scaler, Scaler::None);
        assert!(p.is_active());
    }

    #[test]
    fn invalid_source_is_reported_not_crashed() {
        let p = plan(PlanRequest::new(EnhancementMode::Enhanced), FrameSize::new(0, 0));
        assert!(!p.is_active());
        assert_eq!(p.bypass_reason, Some("invalid_source_size"));
    }

    #[test]
    fn sharpen_decreases_with_resolution() {
        let low = plan(PlanRequest::new(EnhancementMode::Sharp), FrameSize::new(854, 480)).sharpen;
        let mid = plan(PlanRequest::new(EnhancementMode::Sharp), FrameSize::new(1280, 720)).sharpen;
        let high = plan(PlanRequest::new(EnhancementMode::Sharp), FrameSize::new(1920, 1080)).sharpen;
        assert!(low > mid && mid > high, "{low} {mid} {high}");
    }
}
