//! GPU texture runtime (`pixel_surface` Rust crate).
//!
//! P0.3: foundation crate and workspace boundary. `GpuEditSurface` / wgpu engine
//! remain in `image_forge` until beauty-pass coupling is split (see
//! `docs/PUB_PACKAGE_SPLIT.md`).
//!
//! ## Features
//!
//! - `gpu` — enables the wgpu + Metal integration for zero-copy beauty
//!   compute. **Apple-only** today: the `wgpu` `metal` backend is the only
//!   one wired into this crate, and the compile graph relies on
//!   `target_vendor = "apple"`. Enabling `gpu` on a non-Apple target is a
//!   hard error to prevent silent dead code.
//!
//!   Future: when `GpuEditSurface` migrates into this crate, the `gpu`
//!   feature will be expanded to cover Vulkan/Metal/DX12.

#![forbid(unsafe_op_in_unsafe_fn)]
#![warn(clippy::missing_safety_doc)]

pub mod buffer;

#[cfg(target_vendor = "apple")]
#[macro_use]
extern crate objc;

#[cfg(target_vendor = "apple")]
pub mod metal_iosurface;

// Both `wgpu_metal_import` and the `wgpu` re-export require the wgpu `metal`
// backend, which is only present on Apple. Keep the gate consistent.
#[cfg(all(target_vendor = "apple", feature = "gpu"))]
pub mod wgpu_metal_import;

// Re-export the wgpu and metal versions we build against so downstream
// crates (e.g. `image_forge`) can use the same pinned versions. This
// eliminates the workspace risk of two crates pulling in different wgpu
// majors and then passing `wgpu::Device` across the crate boundary.
#[cfg(all(target_vendor = "apple", feature = "gpu"))]
pub use wgpu;

#[cfg(target_vendor = "apple")]
pub use metal;

#[cfg(all(feature = "gpu", not(target_vendor = "apple")))]
compile_error!(
    "pixel_surface `gpu` feature is only supported on Apple targets today \
     (depends on the wgpu `metal` backend). Disable the `gpu` feature for \
     non-Apple builds, or add the relevant wgpu backend to Cargo.toml and \
     extend the metal_iosurface / wgpu_metal_import modules."
);

/// Crate version for diagnostics and pub.dev alignment.
pub const VERSION: &str = env!("CARGO_PKG_VERSION");

#[cfg(all(target_vendor = "apple", feature = "gpu"))]
pub fn gpu_feature_enabled() -> bool {
    true
}

#[cfg(not(all(target_vendor = "apple", feature = "gpu")))]
pub fn gpu_feature_enabled() -> bool {
    false
}
