mod common;

use common::{
    decode_dims, mean_r_channel, plain_jpeg, synthetic_jpeg, synthetic_png, tiny_rgba,
};
use rust_image_core::api::advanced::{decode_to_rgba_buffer, filter_rgba_buffer};
use rust_image_core::api::image::{
    add_watermark, apply_filter, batch_resize_images, compress_image, create_thumbnail, crop_image,
    draw_circle_on_image, draw_line_on_image, draw_text_on_image, fix_exif_orientation,
    init_app, overlay_image, read_exif_orientation, resize_image, rotate_image, BatchResizeItem,
    BlendMode, DrawCircle, DrawLine, FilterPreset, ImageFilter, OutputFormat, ProcessingBackend,
    ResizeAlgorithm, Rotation, TextOverlay,
};

#[cfg(feature = "blurhash")]
use rust_image_core::api::image::{decode_blurhash, encode_blurhash};

fn roundtrip(bytes: Vec<u8>, format: OutputFormat) -> Vec<u8> {
    compress_image(bytes, format, 85).expect("roundtrip compress")
}

#[test]
fn resize_image_shrinks_jpeg() {
    init_app();
    let src = plain_jpeg(1024, 768);
    let out = resize_image(
        src,
        256,
        192,
        ResizeAlgorithm::Mitchell,
        OutputFormat::Jpeg,
        85,
        false,
        ProcessingBackend::Cpu,
    )
    .expect("resize");
    let (w, h) = decode_dims(&out);
    assert_eq!((w, h), (256, 192));
}

#[test]
fn resize_image_rejects_zero_dims() {
    init_app();
    let src = plain_jpeg(64, 64);
    let err = resize_image(
        src.clone(),
        0,
        64,
        ResizeAlgorithm::Nearest,
        OutputFormat::Jpeg,
        85,
        false,
        ProcessingBackend::Cpu,
    )
    .unwrap_err();
    assert!(err.contains("must be greater than zero"));
    let err2 = resize_image(
        src,
        64,
        0,
        ResizeAlgorithm::Nearest,
        OutputFormat::Jpeg,
        85,
        false,
        ProcessingBackend::Cpu,
    )
    .unwrap_err();
    assert!(err2.contains("must be greater than zero"));
}

#[test]
fn resize_image_rejects_bad_bytes() {
    init_app();
    let err = resize_image(
        vec![0, 1, 2],
        10,
        10,
        ResizeAlgorithm::Nearest,
        OutputFormat::Jpeg,
        85,
        false,
        ProcessingBackend::Cpu,
    )
    .unwrap_err();
    assert!(!err.is_empty());
}

#[test]
fn create_thumbnail_tall_and_wide() {
    init_app();
    let tall = plain_jpeg(200, 800);
    let out_t = create_thumbnail(
        tall,
        100,
        OutputFormat::Jpeg,
        80,
        ResizeAlgorithm::Mitchell,
        false,
        ProcessingBackend::Cpu,
    )
    .expect("thumb tall");
    let (w, h) = decode_dims(&out_t);
    assert_eq!(w.max(h), 100);

    let wide = plain_jpeg(800, 200);
    let out_w = create_thumbnail(
        wide,
        100,
        OutputFormat::Jpeg,
        80,
        ResizeAlgorithm::Mitchell,
        false,
        ProcessingBackend::Cpu,
    )
    .expect("thumb wide");
    let (w2, h2) = decode_dims(&out_w);
    assert_eq!(w2.max(h2), 100);
}

#[test]
fn create_thumbnail_rejects_zero_max_edge() {
    init_app();
    let src = plain_jpeg(64, 64);
    let err = create_thumbnail(
        src,
        0,
        OutputFormat::Jpeg,
        80,
        ResizeAlgorithm::Mitchell,
        false,
        ProcessingBackend::Cpu,
    )
    .unwrap_err();
    assert!(err.contains("must be greater than zero"));
}

#[test]
fn crop_image_in_bounds_and_oob() {
    init_app();
    let src = plain_jpeg(100, 80);
    let ok = crop_image(src.clone(), 10, 10, 50, 40, OutputFormat::Png, 90, false).expect("crop");
    let (w, h) = decode_dims(&ok);
    assert_eq!((w, h), (50, 40));
    let err = crop_image(src, 90, 70, 20, 20, OutputFormat::Png, 90, false).unwrap_err();
    assert!(err.contains("exceeds image bounds"));
}

#[test]
fn rotate_image_variants() {
    init_app();
    let src = plain_jpeg(120, 80);
    for rot in [
        Rotation::Rotate90,
        Rotation::Rotate180,
        Rotation::Rotate270,
        Rotation::FlipHorizontal,
        Rotation::FlipVertical,
    ] {
        let out = rotate_image(src.clone(), rot, OutputFormat::Png, 90, false).expect("rot");
        assert!(!out.is_empty());
        let _ = decode_dims(&out);
    }
    let r90 = rotate_image(src, Rotation::Rotate90, OutputFormat::Png, 90, false).expect("90");
    let (w, h) = decode_dims(&r90);
    assert_eq!((w, h), (80, 120));
}

#[test]
fn read_exif_orientation_plain_jpeg_none() {
    init_app();
    let jpg = plain_jpeg(64, 64);
    assert_eq!(read_exif_orientation(jpg), None);
}

#[test]
fn fix_exif_smoke() {
    init_app();
    let jpg = plain_jpeg(64, 48);
    let out = fix_exif_orientation(jpg, OutputFormat::Jpeg, 85).expect("fix");
    assert!(!out.is_empty());
}

#[test]
fn compress_formats_roundtrip() {
    init_app();
    let src = synthetic_png(48, 48);
    for fmt in [OutputFormat::Jpeg, OutputFormat::Png, OutputFormat::WebP] {
        let out = roundtrip(src.clone(), fmt);
        assert!(!out.is_empty());
    }
    #[cfg(feature = "avif")]
    {
        let avif = roundtrip(src, OutputFormat::Avif);
        assert!(!avif.is_empty());
    }
}

#[test]
fn apply_filter_variants_and_brightness() {
    init_app();
    let src = plain_jpeg(64, 64);
    let filters = vec![
        ImageFilter::Blur { radius: 2 },
        ImageFilter::Sharpen,
        ImageFilter::Brightness { amount: 50 },
        ImageFilter::Contrast { amount: 1.2 },
        ImageFilter::Saturation { amount: 1.1 },
        ImageFilter::HueRotate { degrees: 15.0 },
        ImageFilter::Pixelize { size: 4 },
        ImageFilter::Solarize,
        ImageFilter::FrostedGlass,
        ImageFilter::Oil {
            radius: 2,
            intensity: 0.5,
        },
    ];
    for f in filters {
        let out = apply_filter(src.clone(), f, OutputFormat::Png, 90, false).expect("filter");
        assert!(!out.is_empty());
    }
    let bright = apply_filter(
        src.clone(),
        ImageFilter::Brightness { amount: 50 },
        OutputFormat::Png,
        90,
        false,
    )
    .expect("bright");
    let dark = apply_filter(
        src,
        ImageFilter::Brightness { amount: -50 },
        OutputFormat::Png,
        90,
        false,
    )
    .expect("dark");
    let rb = rust_image_core::api::advanced::decode_to_rgba_buffer(bright, false, None).unwrap();
    let rd = rust_image_core::api::advanced::decode_to_rgba_buffer(dark, false, None).unwrap();
    assert!(mean_r_channel(&rb) > mean_r_channel(&rd));
}

#[test]
fn apply_filter_all_presets() {
    init_app();
    let src = plain_jpeg(48, 48);
    let presets = [
        FilterPreset::Neue,
        FilterPreset::Lix,
        FilterPreset::Ryo,
        FilterPreset::Lofi,
        FilterPreset::PastelPink,
        FilterPreset::Golden,
        FilterPreset::Cali,
        FilterPreset::Dramatic,
        FilterPreset::Firenze,
        FilterPreset::Obsidian,
        FilterPreset::DuotoneViolette,
        FilterPreset::DuotoneHorizon,
        FilterPreset::DuotoneLilac,
        FilterPreset::DuotoneOchre,
    ];
    for p in presets {
        let out = apply_filter(
            src.clone(),
            ImageFilter::Preset {
                preset: p,
                strength: 1.0,
            },
            OutputFormat::Jpeg,
            85,
            false,
        )
        .expect("preset");
        assert!(!out.is_empty());
    }
}

#[test]
fn tone_filters_at_zero_are_near_identity() {
    init_app();
    let buf = decode_to_rgba_buffer(synthetic_png(32, 32), false, None).expect("decode");
    let mean_before = mean_r_channel(&buf);
    for filter in [
        ImageFilter::Highlights { amount: 0.0 },
        ImageFilter::Shadows { amount: 0.0 },
        ImageFilter::Structure { amount: 0.0 },
    ] {
        let out = filter_rgba_buffer(buf.clone(), filter, ProcessingBackend::Cpu)
            .expect("filter");
        let mean_after = mean_r_channel(&out);
        assert!(
            (mean_before - mean_after).abs() < 2.0,
            "filter at 0 should be near identity: {mean_before} vs {mean_after}"
        );
    }
}

#[test]
fn rotate_rgba_arbitrary_changes_dimensions() {
    init_app();
    use rust_image_core::api::advanced::rotate_rgba_arbitrary;
    let buf = decode_to_rgba_buffer(synthetic_png(40, 30), false, None).expect("decode");
    let out = rotate_rgba_arbitrary(buf, 5.0).expect("rotate");
    assert!(out.width >= 40 && out.height >= 30);
}

#[test]
fn preset_strength_zero_is_near_identity() {
    init_app();
    let src = synthetic_png(32, 32);
    let buf = decode_to_rgba_buffer(src, false, None).expect("decode");
    let mean_before = mean_r_channel(&buf);
    let out = filter_rgba_buffer(
        buf,
        ImageFilter::Preset {
            preset: FilterPreset::Dramatic,
            strength: 0.0,
        },
        ProcessingBackend::Cpu,
    )
    .expect("filter");
    let mean_after = mean_r_channel(&out);
    assert!(
        (mean_before - mean_after).abs() < 2.0,
        "strength 0 should barely change image: {mean_before} vs {mean_after}"
    );
}

#[test]
fn watermark_and_overlay_blend_modes() {
    init_app();
    let base = synthetic_png(64, 64);
    let overlay = synthetic_png(16, 16);
    let wm = add_watermark(base.clone(), overlay.clone(), 4, 4, OutputFormat::Png, 90)
        .expect("watermark");
    assert!(!wm.is_empty());
    for mode in [
        BlendMode::Normal,
        BlendMode::Multiply,
        BlendMode::Screen,
        BlendMode::Overlay,
        BlendMode::Add,
    ] {
        let out = overlay_image(
            base.clone(),
            overlay.clone(),
            4,
            4,
            mode,
            OutputFormat::Png,
            90,
        )
        .expect("overlay");
        assert!(!out.is_empty());
    }
    // Mostly off-canvas — should clip without error
    let clipped = overlay_image(
        base,
        overlay,
        60,
        60,
        BlendMode::Normal,
        OutputFormat::Png,
        90,
    )
    .expect("clipped overlay");
    assert!(!clipped.is_empty());
}

#[test]
fn draw_text_line_circle() {
    init_app();
    let src = plain_jpeg(80, 80);
    let line = draw_line_on_image(
        src.clone(),
        DrawLine {
            x0: 0,
            y0: 0,
            x1: 60,
            y1: 60,
            color_r: 255,
            color_g: 0,
            color_b: 0,
            color_a: 255,
        },
        OutputFormat::Png,
        95,
        false,
    )
    .expect("line");
    assert!(!line.is_empty());
    let circle = draw_circle_on_image(
        src.clone(),
        DrawCircle {
            center_x: 40,
            center_y: 40,
            radius: 15,
            color_r: 0,
            color_g: 255,
            color_b: 0,
            color_a: 255,
        },
        OutputFormat::Png,
        95,
        false,
    )
    .expect("circle");
    assert!(!circle.is_empty());
    let text = draw_text_on_image(
        src,
        TextOverlay {
            text: "test".into(),
            x: 5,
            y: 5,
            font_size: 14.0,
            color_r: 255,
            color_g: 255,
            color_b: 255,
            color_a: 255,
        },
        OutputFormat::Png,
        95,
        false,
    )
    .expect("text");
    assert!(!text.is_empty());
}

#[test]
fn batch_resize_parallel() {
    init_app();
    let items: Vec<BatchResizeItem> = (0..8)
        .map(|i| {
            let w = 32 + i;
            BatchResizeItem {
                bytes: synthetic_jpeg(w, w, 80),
                width: 16,
                height: 16,
            }
        })
        .collect();
    let outs = batch_resize_images(
        items,
        ResizeAlgorithm::Mitchell,
        OutputFormat::Jpeg,
        85,
        ProcessingBackend::Cpu,
    )
    .expect("batch");
    assert_eq!(outs.len(), 8);
    for out in outs {
        let (w, h) = decode_dims(&out);
        assert_eq!((w, h), (16, 16));
    }
}

#[test]
fn batch_resize_propagates_error() {
    init_app();
    let items = vec![
        BatchResizeItem {
            bytes: plain_jpeg(32, 32),
            width: 16,
            height: 16,
        },
        BatchResizeItem {
            bytes: vec![1, 2, 3],
            width: 16,
            height: 16,
        },
    ];
    assert!(batch_resize_images(
        items,
        ResizeAlgorithm::Nearest,
        OutputFormat::Jpeg,
        85,
        ProcessingBackend::Cpu,
    )
    .is_err());
}

#[cfg(feature = "blurhash")]
#[test]
fn blurhash_encode_decode() {
    init_app();
    let src = plain_jpeg(32, 32);
    let hash = encode_blurhash(src, 4, 3).expect("encode");
    assert!(hash.len() >= 6);
    let out = decode_blurhash(hash, 32, 32, OutputFormat::Png, 90).expect("decode");
    assert!(!out.is_empty());
}
