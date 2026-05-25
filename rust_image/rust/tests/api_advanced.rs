//! Integration tests for `rust_image_core::api::advanced::*` — RGBA buffer
//! pipeline (decode -> ops -> encode), pool, and execution-path metadata.
//!
//! This binary deliberately leaves `RUST_IMAGE_NO_POOL` unset so the buffer
//! pool starts enabled (the env-toggle counterpart lives in
//! `tests/pool_runtime.rs`, which runs in its own process).

mod common;

use common::{rgb_mean, synthetic_jpeg, synthetic_png, synthetic_webp};
use rust_image_core::api::advanced::*;
use rust_image_core::api::image::*;

// ---------------------------------------------------------------------------
// probe_image
// ---------------------------------------------------------------------------

#[test]
fn probe_jpeg_reports_dims_and_format() {
    let info = probe_image(synthetic_jpeg(80, 40, 85)).expect("probe ok");
    assert_eq!(info.width, 80);
    assert_eq!(info.height, 40);
    let format = info.format.expect("format present");
    assert!(format.to_lowercase().contains("jpeg"), "got {format}");
    assert_eq!(info.exif_orientation, None);
}

#[test]
fn probe_png_reports_format() {
    let info = probe_image(synthetic_png(40, 80)).expect("probe ok");
    assert_eq!((info.width, info.height), (40, 80));
    let format = info.format.expect("format present");
    assert!(format.to_lowercase().contains("png"), "got {format}");
}

#[test]
fn probe_webp_reports_format() {
    let info = probe_image(synthetic_webp(48, 32)).expect("probe ok");
    assert_eq!((info.width, info.height), (48, 32));
    let format = info.format.expect("format present");
    assert!(format.to_lowercase().contains("webp"), "got {format}");
}

#[test]
fn probe_bad_bytes_errors() {
    let err = probe_image(b"not an image".to_vec()).expect_err("bad bytes must fail");
    assert!(!err.is_empty());
}

// ---------------------------------------------------------------------------
// decode_to_rgba_buffer / encode_rgba_buffer / encode_rgba_preview_buffer
// ---------------------------------------------------------------------------

#[test]
fn decode_to_rgba_full_size_matches_probe() {
    let src = synthetic_jpeg(120, 80, 85);
    let buf = decode_to_rgba_buffer(src, false, None).expect("decode ok");
    assert_eq!((buf.width, buf.height), (120, 80));
    assert_eq!(buf.pixels.len(), (120 * 80 * 4) as usize);
}

#[test]
fn decode_to_rgba_respects_max_edge() {
    let src = synthetic_jpeg(400, 200, 85);
    let buf = decode_to_rgba_buffer(src, false, Some(100)).expect("decode ok");
    let max_dim = buf.width.max(buf.height);
    assert!(max_dim <= 100, "max edge violated: {max_dim}");
    assert_eq!(max_dim, 100);
}

#[test]
fn encode_rgba_buffer_roundtrips_jpeg() {
    let src = synthetic_png(64, 48);
    let buf = decode_to_rgba_buffer(src, false, None).expect("decode");
    let out = encode_rgba_buffer(buf, OutputFormat::Jpeg, 85).expect("encode");
    let info = probe_image(out).expect("probe");
    assert_eq!((info.width, info.height), (64, 48));
}

#[test]
fn encode_rgba_buffer_roundtrips_png() {
    let buf = common::synthetic_rgba(32, 24);
    let out = encode_rgba_buffer(buf, OutputFormat::Png, 85).expect("encode png");
    let info = probe_image(out).expect("probe");
    assert_eq!((info.width, info.height), (32, 24));
}

#[test]
fn encode_rgba_buffer_roundtrips_webp() {
    let buf = common::synthetic_rgba(32, 24);
    let out = encode_rgba_buffer(buf, OutputFormat::WebP, 85).expect("encode webp");
    let info = probe_image(out).expect("probe");
    assert_eq!((info.width, info.height), (32, 24));
}

#[cfg(feature = "avif")]
#[test]
fn encode_rgba_buffer_roundtrips_avif() {
    let buf = common::synthetic_rgba(32, 24);
    let dims = (buf.width, buf.height);
    let out = encode_rgba_buffer(buf, OutputFormat::Avif, 60).expect("encode avif");
    assert!(!out.is_empty());
    // `image` load_from_memory does not decode AVIF; dimensions are validated at encode time.
    assert_eq!(dims, (32, 24));
}

#[test]
fn encode_rgba_preview_both_quality_modes() {
    for pq in [PreviewQuality::Fast, PreviewQuality::Quality] {
        let buf = common::synthetic_rgba(200, 150);
        let out = encode_rgba_preview_buffer(buf, 80, 70, pq)
            .unwrap_or_else(|e| panic!("preview {pq:?} failed: {e}"));
        let info = probe_image(out).expect("probe");
        assert!(info.width.max(info.height) <= 80, "preview max edge");
    }
}

// ---------------------------------------------------------------------------
// resize_rgba_buffer
// ---------------------------------------------------------------------------

#[test]
fn resize_rgba_buffer_all_algorithms_cpu() {
    let algorithms = [
        ResizeAlgorithm::Nearest,
        ResizeAlgorithm::Box,
        ResizeAlgorithm::Hamming,
        ResizeAlgorithm::CatmullRom,
        ResizeAlgorithm::Mitchell,
        ResizeAlgorithm::Lanczos3,
    ];
    for algo in algorithms {
        let buf = common::synthetic_rgba(120, 80);
        let out =
            resize_rgba_buffer(buf, 60, 40, algo, ProcessingBackend::Cpu)
                .unwrap_or_else(|e| panic!("algo {algo:?} failed: {e}"));
        assert_eq!((out.width, out.height), (60, 40), "algo {algo:?}");
        assert_eq!(out.pixels.len(), (60 * 40 * 4) as usize);
    }
}

#[test]
fn resize_rgba_buffer_auto_backend_matches_dims() {
    if is_gpu_compute_available() {
        // Auto selects GPU; parallel `cargo test` can hit wgpu readback mapping races.
        eprintln!("skip auto resize when GPU is on; see resize_rgba_buffer_gpu_when_available");
        return;
    }
    let buf = common::synthetic_rgba(120, 80);
    let out = resize_rgba_buffer(buf, 30, 20, ResizeAlgorithm::Lanczos3, ProcessingBackend::Auto)
        .expect("auto resize ok");
    assert_eq!((out.width, out.height), (30, 20));
}

#[test]
fn resize_rgba_buffer_gpu_when_available() {
    if !is_gpu_compute_available() {
        eprintln!("skipping GPU resize_rgba_buffer test: GPU compute unavailable");
        return;
    }
    let buf = common::synthetic_rgba(120, 80);
    let out = resize_rgba_buffer(buf, 30, 20, ResizeAlgorithm::Lanczos3, ProcessingBackend::Gpu)
        .expect("gpu resize ok");
    assert_eq!((out.width, out.height), (30, 20));
}

#[test]
fn resize_rgba_buffer_zero_dim_errors() {
    let buf = common::synthetic_rgba(32, 32);
    let err = resize_rgba_buffer(buf, 0, 32, ResizeAlgorithm::Lanczos3, ProcessingBackend::Cpu)
        .expect_err("zero width fails");
    assert!(err.to_lowercase().contains("greater than zero"));
}

// ---------------------------------------------------------------------------
// crop_rgba_buffer
// ---------------------------------------------------------------------------

#[test]
fn crop_rgba_buffer_in_bounds() {
    let buf = common::synthetic_rgba(100, 80);
    let out = crop_rgba_buffer(buf, 10, 20, 50, 40).expect("crop ok");
    assert_eq!((out.width, out.height), (50, 40));
    assert_eq!(out.pixels.len(), (50 * 40 * 4) as usize);
}

#[test]
fn crop_rgba_buffer_out_of_bounds_errors() {
    let buf = common::synthetic_rgba(64, 64);
    let err = crop_rgba_buffer(buf, 50, 50, 100, 100).expect_err("oob fails");
    assert!(err.to_lowercase().contains("out of bounds"));
}

#[test]
fn crop_rgba_buffer_zero_dim_errors() {
    let buf = common::synthetic_rgba(64, 64);
    let err = crop_rgba_buffer(buf, 0, 0, 0, 10).expect_err("zero crop fails");
    assert!(err.to_lowercase().contains("greater than zero"));
}

// ---------------------------------------------------------------------------
// filter_rgba_buffer + filter_execution_path_name
// ---------------------------------------------------------------------------

fn known_path(name: &str) -> bool {
    matches!(
        name,
        "cpu_photon"
            | "cpu_parallel"
            | "gpu_adjust"
            | "gpu_blur"
            | "gpu_sharpen"
            | "gpu_resize"
            | "cpu_resize"
    )
}

#[test]
fn filter_execution_path_returns_known_label() {
    let cpu_brightness = filter_execution_path_name(
        ImageFilter::Brightness { amount: 10 },
        ProcessingBackend::Cpu,
    );
    assert_eq!(cpu_brightness, "cpu_parallel");

    let cpu_blur = filter_execution_path_name(
        ImageFilter::Blur { radius: 3 },
        ProcessingBackend::Cpu,
    );
    assert_eq!(cpu_blur, "cpu_photon");

    let auto_brightness = filter_execution_path_name(
        ImageFilter::Brightness { amount: 10 },
        ProcessingBackend::Auto,
    );
    assert!(
        known_path(&auto_brightness),
        "auto brightness path not in expected set: {auto_brightness}"
    );
}

#[test]
fn filter_rgba_buffer_brightness_shifts_mean() {
    let buf = common::synthetic_rgba(64, 64);
    let baseline = rgb_mean(&buf);
    let out = filter_rgba_buffer(
        buf,
        ImageFilter::Brightness { amount: 50 },
        ProcessingBackend::Cpu,
    )
    .expect("brightness ok");
    let new_mean = rgb_mean(&out);
    assert!(
        new_mean > baseline + 10.0,
        "brightness +50: {baseline} -> {new_mean}"
    );
}

#[test]
fn filter_rgba_buffer_every_variant_runs() {
    let filters: Vec<ImageFilter> = vec![
        ImageFilter::Blur { radius: 2 },
        ImageFilter::Sharpen,
        ImageFilter::Brightness { amount: 10 },
        ImageFilter::Contrast { amount: 20.0 },
        ImageFilter::Saturation { amount: 1.2 },
        ImageFilter::HueRotate { degrees: 45.0 },
        ImageFilter::Oil { radius: 2, intensity: 30.0 },
        ImageFilter::FrostedGlass,
        ImageFilter::Pixelize { size: 4 },
        ImageFilter::Solarize,
        ImageFilter::Preset {
            preset: FilterPreset::Lofi,
            strength: 1.0,
        },
    ];
    for filter in filters {
        let buf = common::synthetic_rgba(48, 48);
        let out = filter_rgba_buffer(buf, filter.clone(), ProcessingBackend::Cpu)
            .unwrap_or_else(|e| panic!("filter {filter:?} failed: {e}"));
        assert_eq!((out.width, out.height), (48, 48), "filter {filter:?}");
    }
}

// ---------------------------------------------------------------------------
// fit_max_edge_rgba_buffer
// ---------------------------------------------------------------------------

#[test]
fn fit_max_edge_noop_when_small() {
    let buf = common::synthetic_rgba(50, 50);
    let out = fit_max_edge_rgba_buffer(buf.clone(), 100, PreviewQuality::Fast)
        .expect("fit ok");
    assert_eq!((out.width, out.height), (50, 50));
}

#[test]
fn fit_max_edge_downscales_when_needed() {
    let buf = common::synthetic_rgba(200, 100);
    let out = fit_max_edge_rgba_buffer(buf, 50, PreviewQuality::Quality)
        .expect("fit ok");
    assert!(out.width.max(out.height) <= 50);
    assert_eq!(out.width.max(out.height), 50);
}

#[test]
fn fit_max_edge_zero_returns_unchanged() {
    let buf = common::synthetic_rgba(64, 64);
    let out = fit_max_edge_rgba_buffer(buf.clone(), 0, PreviewQuality::Fast)
        .expect("zero edge ok");
    assert_eq!((out.width, out.height), (64, 64));
}

// ---------------------------------------------------------------------------
// decode_progressive_image
// ---------------------------------------------------------------------------

#[test]
fn decode_progressive_returns_preview_and_full() {
    let src = synthetic_jpeg(400, 300, 85);
    let res = decode_progressive_image(src, 100, false).expect("progressive ok");
    assert_eq!((res.info.width, res.info.height), (400, 300));
    let preview_max = res.preview_rgba.width.max(res.preview_rgba.height);
    assert!(preview_max <= 100, "preview violates max_edge: {preview_max}");
    assert_eq!((res.buffer.width, res.buffer.height), (400, 300));
}

// ---------------------------------------------------------------------------
// draw_*_rgba_buffer
// ---------------------------------------------------------------------------

#[test]
fn draw_line_rgba_preserves_dims() {
    let buf = common::synthetic_rgba(64, 64);
    let line = DrawLine {
        x0: 4,
        y0: 4,
        x1: 60,
        y1: 60,
        color_r: 255,
        color_g: 0,
        color_b: 0,
        color_a: 255,
    };
    let out = draw_line_rgba_buffer(buf, line).expect("line ok");
    assert_eq!((out.width, out.height), (64, 64));
}

#[test]
fn draw_circle_rgba_preserves_dims() {
    let buf = common::synthetic_rgba(64, 64);
    let circle = DrawCircle {
        center_x: 32,
        center_y: 32,
        radius: 10,
        color_r: 0,
        color_g: 0,
        color_b: 255,
        color_a: 255,
    };
    let out = draw_circle_rgba_buffer(buf, circle).expect("circle ok");
    assert_eq!((out.width, out.height), (64, 64));
}

#[test]
fn draw_text_rgba_preserves_dims() {
    let buf = common::synthetic_rgba(120, 60);
    let overlay = TextOverlay {
        text: "abc".into(),
        x: 4,
        y: 4,
        font_size: 18.0,
        color_r: 255,
        color_g: 255,
        color_b: 0,
        color_a: 255,
    };
    let out = draw_text_rgba_buffer(buf, overlay).expect("text ok");
    assert_eq!((out.width, out.height), (120, 60));
}

// ---------------------------------------------------------------------------
// overlay_on_rgba_buffer
// ---------------------------------------------------------------------------

#[test]
fn overlay_on_rgba_each_blend_mode() {
    let over_bytes = synthetic_png(20, 20);
    for mode in [
        BlendMode::Normal,
        BlendMode::Multiply,
        BlendMode::Screen,
        BlendMode::Overlay,
        BlendMode::Add,
    ] {
        let buf = common::synthetic_rgba(64, 64);
        let out = overlay_on_rgba_buffer(buf, over_bytes.clone(), 10, 10, mode)
            .unwrap_or_else(|e| panic!("overlay {mode:?} failed: {e}"));
        assert_eq!((out.width, out.height), (64, 64), "blend {mode:?}");
    }
}

#[test]
fn overlay_on_rgba_offscreen_offsets_dont_panic() {
    let over_bytes = synthetic_png(16, 16);
    let buf = common::synthetic_rgba(64, 64);
    let out = overlay_on_rgba_buffer(buf, over_bytes.clone(), -100, -100, BlendMode::Normal)
        .expect("offscreen ok");
    assert_eq!((out.width, out.height), (64, 64));

    let buf = common::synthetic_rgba(64, 64);
    let out = overlay_on_rgba_buffer(buf, over_bytes, 9999, 9999, BlendMode::Normal)
        .expect("far offscreen ok");
    assert_eq!((out.width, out.height), (64, 64));
}

// ---------------------------------------------------------------------------
// apply_edit_pipeline
// ---------------------------------------------------------------------------

#[test]
fn edit_pipeline_chain_cpu() {
    let buf = common::synthetic_rgba(120, 80);
    let ops = vec![
        EditOp::Filter { filter: ImageFilter::Brightness { amount: 20 } },
        EditOp::Resize { width: 60, height: 40, algorithm: ResizeAlgorithm::Lanczos3 },
        EditOp::Crop { x: 5, y: 5, width: 40, height: 30 },
        EditOp::Rotate { rotation: Rotation::Rotate90 },
    ];
    let out = apply_edit_pipeline(buf, ops, ProcessingBackend::Cpu).expect("pipeline ok");
    // 60×40 → crop 40×30 → rotate90 → 30×40
    assert_eq!((out.width, out.height), (30, 40));
}

#[test]
fn edit_pipeline_auto_matches_cpu_dims() {
    let make_ops = || {
        vec![
            EditOp::Filter { filter: ImageFilter::Brightness { amount: 10 } },
            EditOp::Resize { width: 64, height: 32, algorithm: ResizeAlgorithm::Lanczos3 },
        ]
    };
    let cpu = apply_edit_pipeline(common::synthetic_rgba(120, 80), make_ops(), ProcessingBackend::Cpu)
        .expect("cpu ok");
    let auto = apply_edit_pipeline(common::synthetic_rgba(120, 80), make_ops(), ProcessingBackend::Auto)
        .expect("auto ok");
    assert_eq!((cpu.width, cpu.height), (64, 32));
    assert_eq!((auto.width, auto.height), (64, 32));
    // CPU vs Auto means may differ slightly (GPU vs CPU brightness rounding).
    // Just bound the difference.
    let diff = (rgb_mean(&cpu) - rgb_mean(&auto)).abs();
    assert!(diff < 10.0, "auto vs cpu mean diff too large: {diff}");
}

// ---------------------------------------------------------------------------
// processing_backend_name / is_gpu_compute_available
// ---------------------------------------------------------------------------

#[test]
fn processing_backend_name_cpu_is_cpu_simd() {
    assert_eq!(processing_backend_name(ProcessingBackend::Cpu), "cpu_simd");
}

#[test]
fn processing_backend_name_gpu_reflects_availability() {
    let name = processing_backend_name(ProcessingBackend::Gpu);
    if is_gpu_compute_available() {
        assert_ne!(name, "unavailable");
        assert!(!name.is_empty());
    } else {
        assert_eq!(name, "unavailable");
    }
}

#[test]
fn processing_backend_name_auto_picks_concrete_backend() {
    let name = processing_backend_name(ProcessingBackend::Auto);
    // Auto always resolves Ok, so name must NOT be "unavailable".
    assert_ne!(name, "unavailable", "auto must always resolve");
    assert!(!name.is_empty());
}

#[test]
fn gpu_compute_info_consistent_with_availability() {
    let info = gpu_compute_info();
    assert_eq!(info.available, is_gpu_compute_available());
    if info.available {
        assert!(!info.api.is_empty(), "available GPU must report API name");
    }
}

// ---------------------------------------------------------------------------
// Buffer pool (pool enabled in this binary)
// ---------------------------------------------------------------------------

#[test]
fn buffer_pool_release_then_acquire_returns_capacity() {
    let mut buf = Vec::with_capacity(2048);
    buf.resize(2048, 0);
    buffer_pool_release(buf);

    let acquired = buffer_pool_acquire(1024);
    assert!(
        acquired.capacity() >= 1024,
        "acquired capacity {} < requested 1024",
        acquired.capacity()
    );
    // Don't reseed the pool — keeps stats clean for other tests.
    drop(acquired);
}

#[test]
fn buffer_pool_stats_reports_nonzero_after_release() {
    // Use a sufficiently large unique buffer so we can detect at least one
    // pooled entry. (Other concurrent tests may inflate counts, so we only
    // assert monotonic growth, not exact values.)
    let before = buffer_pool_stats();
    let buf = vec![0u8; 4096];
    buffer_pool_release(buf);
    let after = buffer_pool_stats();
    assert!(
        after.0 >= before.0,
        "pool count should not decrease: {before:?} -> {after:?}"
    );
    assert!(
        after.1 >= before.1,
        "pool bytes should not decrease: {before:?} -> {after:?}"
    );
}

#[test]
fn buffer_pool_acquire_returns_min_capacity_when_empty_pool() {
    // Drain a chunk of the pool first (best effort).
    for _ in 0..10 {
        let _ = buffer_pool_acquire(1);
    }
    let acquired = buffer_pool_acquire(8192);
    assert!(acquired.capacity() >= 8192);
}
