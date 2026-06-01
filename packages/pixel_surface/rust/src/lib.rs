//! GPU texture runtime (`pixel_surface` Rust crate).
//!
//! P0.3: foundation crate and workspace boundary. `GpuEditSurface` / wgpu engine
//! remain in `image_forge` until beauty-pass coupling is split (see
//! `docs/PUB_PACKAGE_SPLIT.md`).

pub mod buffer;

#[cfg(target_vendor = "apple")]
pub mod metal_iosurface;
#[cfg(all(target_vendor = "apple", feature = "gpu"))]
pub mod wgpu_metal_import;

/// Crate version for diagnostics and pub.dev alignment.
pub const VERSION: &str = env!("CARGO_PKG_VERSION");

#[cfg(feature = "gpu")]
pub fn gpu_feature_enabled() -> bool {
    true
}

#[cfg(not(feature = "gpu"))]
pub fn gpu_feature_enabled() -> bool {
    false
}
