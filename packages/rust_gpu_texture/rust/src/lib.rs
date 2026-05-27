//! GPU texture runtime (`rust_gpu_texture` Rust crate).
//!
//! P0.3: foundation crate and workspace boundary. `GpuEditSurface` / wgpu engine
//! remain in `rust_image_core` until beauty-pass coupling is split (see
//! `docs/PUB_PACKAGE_SPLIT.md`).

pub mod buffer;

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
