//! # image_forge
//!
//! A high-performance image processing library written in Rust.
//! It serves as the native backend for the `image_forge` Flutter plugin.
//!
//! ## Key Modules
//! - `api`: Defines the FFI boundaries and bridges exported via `flutter_rust_bridge`.
//! - `backend`: Handles target execution routing (CPU vs GPU capabilities).
//! - `buffer`: Manages raw RGBA pixel arrays and conversions.
//! - `compress`: Direct wrappers around MozJPEG and oxipng.
//! - `face`: Real-time face parsing, landmarks tracking, and beauty shaders.
//! - `gpu`: Compute pipeline integration (WGSL shaders via wgpu).
//! - `layers`: Multi-layer sticker and vector drawing compositor.
//! - `filters`: Core color matrices, vignettes, warmth shifts, and 3D LUT lookups.

pub mod api;
pub mod benchmark;
mod frb_generated;

pub mod backend;
mod buffer;
mod compress;
mod crop;
mod decode;
mod draw;
mod face;
mod layers;
mod exif;
mod filters;
mod overlay;
mod parallel_ops;
mod perf;
mod pool;
pub mod runtime;
mod resize;
mod rotate;
mod thumbnail;
mod utils;

#[cfg(feature = "gpu")]
pub mod gpu;

#[cfg(feature = "blurhash")]
mod blurhash;

pub mod test_support;
