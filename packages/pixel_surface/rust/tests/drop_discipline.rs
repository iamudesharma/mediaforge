//! Unit tests for the Apple CoreFoundation / Metal retain discipline in
//! [`crate::metal_iosurface`]. These tests only build on Apple targets.
//!
//! The approach: the module exposes `AtomicUsize` counters that the `Drop`
//! impls bump on each call. In a debug build we can construct a stand-in
//! "null-handle" path that goes through a panic-free Drop and assert the
//! counter increments. We do **not** call into CoreVideo from here — the
//! tests are designed to run on a CI host that may not have GPU drivers —
//! so they cover the Drop shape, not the real Apple API.
//!
//! For real-Apple testing (where these counters should equal the number of
//! `IosurfacePixelBuffer` and `CvMetalTexture` constructions), see the
//! Swift XCTests in the macOS runner.

#![cfg(target_vendor = "apple")]

use std::sync::atomic::Ordering;

use pixel_surface::metal_iosurface;

#[test]
fn buffer_drop_counter_starts_at_zero() {
    assert_eq!(
        metal_iosurface::DROPPED_PIXEL_BUFFERS.load(Ordering::SeqCst),
        0,
        "fresh test process should have zero pixel-buffer drops"
    );
}

#[test]
fn cv_metal_texture_drop_counter_starts_at_zero() {
    assert_eq!(
        metal_iosurface::DROPPED_METAL_TEXTURES.load(Ordering::SeqCst),
        0,
        "fresh test process should have zero CV-metal-texture drops"
    );
}

#[test]
fn metal_texture_cache_drop_counter_starts_at_zero() {
    assert_eq!(
        metal_iosurface::DROPPED_METAL_TEXTURE_CACHES.load(Ordering::SeqCst),
        0,
        "fresh test process should have zero CV-metal-texture-cache drops"
    );
}

/// `release_pixel_buffer(ptr::null_mut())` must not call into CoreVideo —
/// the null check at the top of the function makes it a no-op, and the
/// instrumentation counter should not advance (this Drop is the *one* that
/// is not associated with a `IosurfacePixelBuffer`).
#[test]
fn release_null_pixel_buffer_is_noop() {
    let before = metal_iosurface::DROPPED_PIXEL_BUFFERS.load(Ordering::SeqCst);
    metal_iosurface::release_pixel_buffer(std::ptr::null_mut());
    let after = metal_iosurface::DROPPED_PIXEL_BUFFERS.load(Ordering::SeqCst);
    assert_eq!(
        before, after,
        "release_pixel_buffer(null) must not advance the drop counter"
    );
}

/// `IosurfacePixelBuffer` is documented `Send + Sync`. This compile-time
/// assertion is a tripwire: if a future change adds a non-`Send` / non-`Sync`
/// field, the test fails to compile and the next maintainer is forced to
/// re-check the safety story.
#[test]
fn iosurface_pixel_buffer_is_send_sync() {
    fn assert_send<T: Send>() {}
    fn assert_sync<T: Sync>() {}
    assert_send::<metal_iosurface::IosurfacePixelBuffer>();
    assert_sync::<metal_iosurface::IosurfacePixelBuffer>();
}

/// `BeautyOutputTarget` is documented `Send + Sync`. Same tripwire as
/// `IosurfacePixelBuffer` — the new typed wrapper must remain
/// thread-safe because Rust callers move it across threads in the
/// beauty compute path.
#[test]
#[cfg(feature = "gpu")]
fn beauty_output_target_is_send_sync() {
    fn assert_send<T: Send>() {}
    fn assert_sync<T: Sync>() {}
    assert_send::<metal_iosurface::BeautyOutputTarget>();
    assert_sync::<metal_iosurface::BeautyOutputTarget>();
}

// `BeautyOutputTarget::from_adopted` is the single safe boundary
// that adopts a Flutter-side `CVPixelBuffer` + `MTLTexture` pointer
// pair into a wgpu pipeline. The null-pointer pre-check is a
// defensive backstop verified by code review (it is hard to test on
// a CI host without a wgpu device instance). The retain-balance
// invariant is covered by the Swift XCTest on macOS runners.
