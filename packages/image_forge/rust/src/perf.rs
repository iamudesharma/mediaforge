use std::sync::OnceLock;
use std::time::Instant;

use crate::api::image::{ImageFilter, ProcessingBackend};
use crate::backend::{self, EffectiveBackend};

/// Accurate RGBA filter route (matches `buffer::filter_rgba_with_backend_inner`).
pub fn resolve_rgba_filter_path(
    filter: &ImageFilter,
    requested: ProcessingBackend,
) -> &'static str {
    if uses_gpu_filter(filter, requested) {
        return match filter {
            ImageFilter::Blur { .. } => "gpu_blur",
            ImageFilter::Sharpen => "gpu_sharpen",
            ImageFilter::Vignette { .. } => "gpu_vignette",
            ImageFilter::Mood { .. } => "gpu_mood",
            ImageFilter::SwipeLook { .. } => "gpu_swipe_look",
            ImageFilter::Brightness { .. }
            | ImageFilter::Contrast { .. }
            | ImageFilter::Saturation { .. }
            | ImageFilter::HueRotate { .. } => "gpu_adjust",
            _ => "cpu_photon",
        };
    }
    match filter {
        ImageFilter::Brightness { .. }
        | ImageFilter::Contrast { .. }
        | ImageFilter::Saturation { .. }
        | ImageFilter::HueRotate { .. } => "cpu_parallel",
        _ => "cpu_photon",
    }
}

/// Accurate RGBA resize route.
pub fn resolve_rgba_resize_path(requested: ProcessingBackend) -> &'static str {
    match backend::resolve(requested) {
        Ok(EffectiveBackend::Gpu) => "gpu_resize",
        _ => "cpu_resize",
    }
}

/// Accurate bytes-path resize / thumbnail route.
pub fn resolve_bytes_resize_path(requested: ProcessingBackend) -> &'static str {
    resolve_rgba_resize_path(requested)
}

/// Status / metrics label (alias for [resolve_rgba_filter_path]).
pub fn filter_execution_path(filter: &ImageFilter, requested: ProcessingBackend) -> &'static str {
    resolve_rgba_filter_path(filter, requested)
}

fn uses_gpu_filter(filter: &ImageFilter, requested: ProcessingBackend) -> bool {
    if backend::resolve(requested) != Ok(EffectiveBackend::Gpu) {
        return false;
    }
    #[cfg(feature = "gpu")]
    {
        matches!(
            filter,
            ImageFilter::Brightness { .. }
                | ImageFilter::Contrast { .. }
                | ImageFilter::Saturation { .. }
                | ImageFilter::HueRotate { .. }
                | ImageFilter::Blur { .. }
                | ImageFilter::Sharpen
                | ImageFilter::Vignette { .. }
                | ImageFilter::Mood { .. }
                | ImageFilter::SwipeLook { .. }
        )
    }
    #[cfg(not(feature = "gpu"))]
    {
        let _ = filter;
        false
    }
}

/// Simple stage timer for internal profiling (optional `RUST_IMAGE_PERF=1` logs).
pub struct PerfSpan {
    label: &'static str,
    start: Instant,
    log: bool,
}

static PERF_ENABLED: OnceLock<bool> = OnceLock::new();

impl PerfSpan {
    pub fn new(label: &'static str) -> Self {
        let log = *PERF_ENABLED.get_or_init(|| {
            std::env::var("RUST_IMAGE_PERF")
                .map(|v| v == "1" || v.eq_ignore_ascii_case("true"))
                .unwrap_or(false)
        });
        Self {
            label,
            start: Instant::now(),
            log,
        }
    }

    pub fn elapsed_micros(&self) -> u64 {
        self.start.elapsed().as_micros() as u64
    }

    pub fn finish(self) -> u64 {
        let us = self.elapsed_micros();
        if self.log {
            eprintln!("[rust_image] {}: {} ms", self.label, us / 1000);
        }
        us
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::image::ImageFilter;

    #[test]
    fn cpu_brightness_is_parallel_not_photon() {
        assert_eq!(
            resolve_rgba_filter_path(
                &ImageFilter::Brightness { amount: 10 },
                ProcessingBackend::Cpu
            ),
            "cpu_parallel"
        );
    }

    #[test]
    fn cpu_blur_is_photon() {
        assert_eq!(
            resolve_rgba_filter_path(&ImageFilter::Blur { radius: 4 }, ProcessingBackend::Cpu),
            "cpu_photon"
        );
    }

    #[test]
    #[cfg(feature = "gpu")]
    fn gpu_blur_is_gpu_blur() {
        assert_eq!(
            resolve_rgba_filter_path(&ImageFilter::Blur { radius: 4 }, ProcessingBackend::Gpu),
            "gpu_blur"
        );
    }

    #[test]
    #[cfg(feature = "gpu")]
    fn gpu_sharpen_uses_gpu_sharpen() {
        assert_eq!(
            resolve_rgba_filter_path(&ImageFilter::Sharpen, ProcessingBackend::Gpu),
            "gpu_sharpen"
        );
    }

    #[test]
    #[cfg(feature = "gpu")]
    fn gpu_hue_uses_gpu_adjust() {
        assert_eq!(
            resolve_rgba_filter_path(
                &ImageFilter::HueRotate { degrees: 15.0 },
                ProcessingBackend::Gpu
            ),
            "gpu_adjust"
        );
    }

    #[test]
    #[cfg(feature = "gpu")]
    fn gpu_mood_uses_gpu_mood() {
        assert_eq!(
            resolve_rgba_filter_path(
                &ImageFilter::Mood {
                    preset: crate::api::image::MoodFilterPreset::Rose,
                    strength: 1.0,
                },
                ProcessingBackend::Gpu,
            ),
            "gpu_mood"
        );
    }

    #[test]
    #[cfg(feature = "gpu")]
    fn gpu_vignette_uses_gpu_vignette() {
        assert_eq!(
            resolve_rgba_filter_path(
                &ImageFilter::Vignette { amount: 0.5 },
                ProcessingBackend::Gpu
            ),
            "gpu_vignette"
        );
    }
}
