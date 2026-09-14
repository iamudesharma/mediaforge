//! End-to-end GPU checks for the Metal enhancement backend.
//!
//! These run the real shader on the real device: decode-shaped BGRA
//! `CVPixelBuffer` in, enhanced IOSurface out. They are the only tests that
//! can catch a broken pipeline (bad WGSL, wrong texture format, bad retain
//! discipline), so they are worth the GPU dependency.
//!
//! Compiled only when the `gpu` feature and Apple Metal are available — the
//! same condition under which the feature reports itself supported at runtime.

#![cfg(all(target_vendor = "apple", feature = "gpu"))]

use std::ffi::c_void;

use pixel_surface::enhance::plan::{self, PlanRequest, Scaler};
use pixel_surface::enhance::{
    create_backend, EnhancementMode, FrameHandle, FrameSize,
};
use pixel_surface::metal_iosurface::{
    self, create_bgra_iosurface_pixel_buffer_metal, IosurfacePixelBuffer,
};
use pixel_surface::metal::Device;

type CVPixelBufferRef = *mut c_void;

fn device() -> Device {
    Device::system_default().expect("this Mac must expose a Metal device")
}

/// Horizontal luminance ramp with a hard vertical step past the midpoint, so
/// the scaler has both a smooth gradient and a real edge to work with.
fn fill_pattern(buffer: &IosurfacePixelBuffer, width: u32, height: u32) {
    unsafe {
        metal_iosurface::with_bgra_pixels_mut(buffer.pixel_buffer, |pixels, stride| {
            for y in 0..height as usize {
                for x in 0..width as usize {
                    let v = if x < (width / 2) as usize {
                        (x * 200) / (width / 2).max(1) as usize
                    } else {
                        255
                    } as u8;
                    let i = y * stride + x * 4;
                    pixels[i] = v; // B
                    pixels[i + 1] = v; // G
                    pixels[i + 2] = v; // R
                    pixels[i + 3] = 255; // A
                }
            }
        })
        .expect("lock input pattern");
    }
}

/// Mean blue/luma channel of one output column, read back on the CPU.
fn column_luma(buffer: CVPixelBufferRef, x: usize, height: u32) -> f32 {
    unsafe {
        metal_iosurface::with_bgra_pixels(buffer, |pixels, stride| {
            let mut sum = 0.0f32;
            for y in 0..height as usize {
                sum += pixels[y * stride + x * 4] as f32;
            }
            sum / height as f32
        })
        .expect("lock output")
    }
}

fn make_source(width: u32, height: u32) -> IosurfacePixelBuffer {
    create_bgra_iosurface_pixel_buffer_metal(&device(), width, height).expect("source surface")
}

fn release(handle: FrameHandle) {
    if let FrameHandle::CvPixelBuffer(p) = handle {
        metal_iosurface::release_pixel_buffer(p as CVPixelBufferRef);
    }
}

#[test]
fn backend_reports_metal_support() {
    let backend = create_backend();
    let caps = backend.capabilities();
    assert!(
        caps.supported,
        "expected Metal enhancement on this machine, got {:?}",
        caps.reason
    );
    assert_eq!(caps.backend, "metal_wgpu");
    for mode in EnhancementMode::ALL {
        assert!(caps.modes.contains(&mode), "missing {mode:?}");
    }
    assert_eq!(caps.max_output_edge, plan::HIGH_QUALITY_MAX_EDGE);
}

#[test]
fn upscales_and_sharpens_on_the_gpu() {
    let (src_w, src_h) = (64u32, 48u32);
    let source = make_source(src_w, src_h);
    fill_pattern(&source, src_w, src_h);

    let mut backend = create_backend();
    let request = PlanRequest::new(EnhancementMode::HighQuality)
        .with_viewport(Some(FrameSize::new(256, 192)));
    let plan = plan::plan(request, FrameSize::new(src_w, src_h));
    assert!(plan.is_active());
    assert_eq!(plan.target, FrameSize::new(256, 192));
    assert_eq!(plan.scaler, Scaler::Lanczos3);

    // The backend consumes the caller's retain on success, so hand it one.
    let handed_off = metal_iosurface::retain_pixel_buffer(source.pixel_buffer);
    let frame = backend
        .process(
            FrameHandle::CvPixelBuffer(handed_off as usize),
            FrameSize::new(src_w, src_h),
            &plan,
        )
        .expect("GPU pass");

    assert_eq!(frame.size, FrameSize::new(256, 192));
    assert_eq!(frame.path, "metal_lanczos_cas");
    assert_eq!(frame.passes, 3, "h-scale, v-scale, sharpen");
    assert!(frame.frame_ms > 0.0, "frame time must be measured");

    let out_ptr = match frame.handle {
        FrameHandle::CvPixelBuffer(p) => p as CVPixelBufferRef,
        _ => panic!("expected a CVPixelBuffer output"),
    };
    assert!(!out_ptr.is_null());

    // The output must be directly adoptable by Flutter's texture: a Metal view
    // of it has to be creatable at the enhanced size.
    let view = unsafe {
        metal_iosurface::metal_texture_view_for_pixel_buffer(&device(), out_ptr, 256, 192)
    };
    match &view {
        Ok(texture) => assert_eq!((texture.width(), texture.height()), (256, 192)),
        Err(err) => panic!("output must be an adoptable BGRA surface: {err}"),
    }
    drop(view);

    // Content assertions are read back on the CPU, so they are about pixels
    // rather than about the GPU agreeing with itself.
    let left = column_luma(out_ptr, 8, 192);
    let right = column_luma(out_ptr, 248, 192);
    assert!(
        right > left + 40.0,
        "the brightness ramp must survive the upscale: left={left} right={right}"
    );
    assert!(
        (0.0..=255.0).contains(&left) && (0.0..=255.0).contains(&right),
        "output must stay in range: left={left} right={right}"
    );

    release(frame.handle);
}

#[test]
fn sharp_mode_runs_the_single_pass_path() {
    let (w, h) = (64u32, 64u32);
    let source = make_source(w, h);
    fill_pattern(&source, w, h);

    let mut backend = create_backend();
    let plan = plan::plan(PlanRequest::new(EnhancementMode::Sharp), FrameSize::new(w, h));
    assert_eq!(plan.scaler, Scaler::None);

    let handed_off = metal_iosurface::retain_pixel_buffer(source.pixel_buffer);
    let frame = backend
        .process(
            FrameHandle::CvPixelBuffer(handed_off as usize),
            FrameSize::new(w, h),
            &plan,
        )
        .expect("GPU pass");

    assert_eq!(frame.path, "metal_cas");
    assert_eq!(frame.passes, 1);
    assert_eq!(frame.size, FrameSize::new(w, h));
    release(frame.handle);
}

#[test]
fn output_surfaces_are_recycled_between_frames() {
    let (w, h) = (48u32, 32u32);
    let source = make_source(w, h);
    fill_pattern(&source, w, h);

    let mut backend = create_backend();
    let plan = plan::plan(
        PlanRequest::new(EnhancementMode::Enhanced).with_viewport(Some(FrameSize::new(192, 128))),
        FrameSize::new(w, h),
    );

    let mut fresh = 0;
    for _ in 0..6 {
        let handed_off = metal_iosurface::retain_pixel_buffer(source.pixel_buffer);
        let frame = backend
            .process(
                FrameHandle::CvPixelBuffer(handed_off as usize),
                FrameSize::new(w, h),
                &plan,
            )
            .expect("GPU pass");
        if frame.fresh_surface {
            fresh += 1;
        }
        release(frame.handle);
    }
    // The ring is allocated once, then recycled: no per-frame allocation.
    assert_eq!(fresh, 1, "expected exactly one ring allocation");
}

#[test]
fn releasing_pooled_resources_drops_the_ring() {
    let (w, h) = (48u32, 32u32);
    let source = make_source(w, h);
    fill_pattern(&source, w, h);

    let mut backend = create_backend();
    let plan = plan::plan(
        PlanRequest::new(EnhancementMode::Enhanced).with_viewport(Some(FrameSize::new(96, 64))),
        FrameSize::new(w, h),
    );

    let handed_off = metal_iosurface::retain_pixel_buffer(source.pixel_buffer);
    let first = backend
        .process(
            FrameHandle::CvPixelBuffer(handed_off as usize),
            FrameSize::new(w, h),
            &plan,
        )
        .expect("GPU pass");
    assert!(first.fresh_surface);
    release(first.handle);

    backend.release_pooled_resources();

    let handed_off = metal_iosurface::retain_pixel_buffer(source.pixel_buffer);
    let after = backend
        .process(
            FrameHandle::CvPixelBuffer(handed_off as usize),
            FrameSize::new(w, h),
            &plan,
        )
        .expect("GPU pass after release");
    assert!(
        after.fresh_surface,
        "releasing must drop the cached surfaces so they are re-allocated"
    );
    release(after.handle);
}

#[test]
fn inactive_or_null_requests_never_render() {
    let mut backend = create_backend();
    let source = make_source(32, 32);

    let off = plan::plan(PlanRequest::new(EnhancementMode::Off), FrameSize::new(32, 32));
    assert!(!off.is_active());
    assert!(backend
        .process(
            FrameHandle::CvPixelBuffer(source.pixel_buffer as usize),
            FrameSize::new(32, 32),
            &off,
        )
        .is_err());

    let active = plan::plan(
        PlanRequest::new(EnhancementMode::Enhanced),
        FrameSize::new(32, 32),
    );
    assert!(backend
        .process(FrameHandle::CvPixelBuffer(0), FrameSize::new(32, 32), &active)
        .is_err());
}
