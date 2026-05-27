//! Integration tests for `rust_image_core::api::layers::*` — raster + paint
//! stroke compositing onto an RGBA base.

mod common;

use rust_image_core::api::image::RgbaImageBuffer;
use rust_image_core::api::layers::*;

fn pixel(buf: &RgbaImageBuffer, x: u32, y: u32) -> [u8; 4] {
    let idx = ((y * buf.width + x) * 4) as usize;
    [
        buf.pixels[idx],
        buf.pixels[idx + 1],
        buf.pixels[idx + 2],
        buf.pixels[idx + 3],
    ]
}

fn solid_rgba(w: u32, h: u32, r: u8, g: u8, b: u8, a: u8) -> RgbaImageBuffer {
    let mut pixels = Vec::with_capacity((w * h * 4) as usize);
    for _ in 0..(w * h) {
        pixels.extend_from_slice(&[r, g, b, a]);
    }
    RgbaImageBuffer {
        width: w,
        height: h,
        pixels,
    }
}

/// Checkerboard so blur/pixelate change measured pixels (uniform fills are invariant).
fn checker_rgba(w: u32, h: u32) -> RgbaImageBuffer {
    let mut pixels = vec![0u8; (w * h * 4) as usize];
    for y in 0..h {
        for x in 0..w {
            let idx = ((y * w + x) * 4) as usize;
            let on = ((x / 6) + (y / 6)) % 2 == 0;
            let (r, g, b) = if on { (255, 0, 0) } else { (0, 0, 255) };
            pixels[idx..idx + 4].copy_from_slice(&[r, g, b, 255]);
        }
    }
    RgbaImageBuffer {
        width: w,
        height: h,
        pixels,
    }
}

#[test]
fn bake_layers_with_only_raster_blends_at_center() {
    let base = solid_rgba(100, 100, 0, 0, 0, 255);
    let overlay = solid_rgba(40, 40, 255, 255, 255, 255).pixels;
    let layer = RasterLayerInput {
        pixels: overlay,
        width: 40,
        height: 40,
        center_x: 50.0,
        center_y: 50.0,
        scale: 1.0,
        rotation_rad: 0.0,
        opacity: 0.5,
    };
    let out = bake_layers_on_rgba(base, vec![layer], vec![]).expect("bake ok");
    assert_eq!((out.width, out.height), (100, 100));

    // Center pixel should be mid-grey (~127): 50/50 black base + white overlay @ 50% opacity.
    let center = pixel(&out, 50, 50);
    for (i, c) in center.iter().take(3).enumerate() {
        assert!(
            *c >= 100 && *c <= 160,
            "center channel {i} = {c}, expected mid-grey"
        );
    }
}

#[test]
fn bake_layers_with_only_paint_stroke_shifts_endpoint_pixel() {
    let base = solid_rgba(80, 80, 0, 0, 0, 255);
    let stroke = PaintStrokeInput {
        points: vec![(10.0, 10.0), (70.0, 70.0)],
        color_r: 255,
        color_g: 0,
        color_b: 0,
        color_a: 255,
        width: 4.0,
        opacity: 1.0,
        erase: false,
        brush_kind: 0,
        filled: false,
    };
    let out = bake_layers_on_rgba(base, vec![], vec![stroke]).expect("bake ok");
    assert_eq!((out.width, out.height), (80, 80));

    // Pixel near the stroke endpoint should have nonzero red.
    let endpoint = pixel(&out, 70, 70);
    assert!(endpoint[0] > 100, "stroke endpoint red = {}", endpoint[0]);
}

#[test]
fn bake_layers_combined_raster_and_stroke() {
    let base = solid_rgba(80, 80, 0, 0, 0, 255);
    let overlay = solid_rgba(20, 20, 0, 255, 0, 255).pixels;
    let layer = RasterLayerInput {
        pixels: overlay,
        width: 20,
        height: 20,
        center_x: 20.0,
        center_y: 20.0,
        scale: 1.0,
        rotation_rad: 0.0,
        opacity: 1.0,
    };
    let stroke = PaintStrokeInput {
        points: vec![(5.0, 60.0), (75.0, 60.0)],
        color_r: 0,
        color_g: 0,
        color_b: 255,
        color_a: 255,
        width: 3.0,
        opacity: 1.0,
        erase: false,
        brush_kind: 0,
        filled: false,
    };
    let out = bake_layers_on_rgba(base, vec![layer], vec![stroke]).expect("bake ok");
    assert_eq!((out.width, out.height), (80, 80));

    // Raster region should be green-ish.
    let green = pixel(&out, 20, 20);
    assert!(green[1] > 200, "raster center green = {}", green[1]);
    // Stroke region should be blue-ish.
    let blue = pixel(&out, 40, 60);
    assert!(blue[2] > 200, "stroke midline blue = {}", blue[2]);
}

#[test]
fn bake_layers_empty_inputs_returns_buffer_unchanged_dims() {
    let base = solid_rgba(50, 40, 10, 20, 30, 255);
    let out = bake_layers_on_rgba(base.clone(), vec![], vec![]).expect("bake ok");
    assert_eq!((out.width, out.height), (50, 40));
    assert_eq!(out.pixels.len(), base.pixels.len());
}

#[test]
fn bake_layers_empty_raster_layer_is_skipped() {
    let base = solid_rgba(50, 40, 10, 20, 30, 255);
    let layer = RasterLayerInput {
        pixels: vec![],
        width: 0,
        height: 0,
        center_x: 0.0,
        center_y: 0.0,
        scale: 1.0,
        rotation_rad: 0.0,
        opacity: 1.0,
    };
    let out = bake_layers_on_rgba(base.clone(), vec![layer], vec![]).expect("bake ok");
    assert_eq!(out.pixels, base.pixels);
}

#[test]
fn bake_layers_invalid_raster_dims_errors() {
    let base = solid_rgba(40, 40, 0, 0, 0, 255);
    // Non-empty pixels but mismatched width/height should fail to construct.
    let layer = RasterLayerInput {
        pixels: vec![255, 0, 0, 255],
        width: 100,
        height: 100,
        center_x: 20.0,
        center_y: 20.0,
        scale: 1.0,
        rotation_rad: 0.0,
        opacity: 1.0,
    };
    let err = bake_layers_on_rgba(base, vec![layer], vec![]).expect_err("bad layer fails");
    assert!(!err.is_empty());
}

#[test]
fn bake_layers_short_stroke_is_skipped() {
    let base = solid_rgba(40, 40, 0, 0, 0, 255);
    // Only one point — needs ≥2 to render.
    let stroke = PaintStrokeInput {
        points: vec![(10.0, 10.0)],
        color_r: 255,
        color_g: 0,
        color_b: 0,
        color_a: 255,
        width: 2.0,
        opacity: 1.0,
        erase: false,
        brush_kind: 0,
        filled: false,
    };
    let out = bake_layers_on_rgba(base.clone(), vec![], vec![stroke]).expect("bake ok");
    assert_eq!(out.pixels, base.pixels);
}

#[test]
fn bake_layers_local_blur_softens_interior() {
    let base = checker_rgba(40, 40);
    let sharp = pixel(&base, 15, 15);
    let stroke = PaintStrokeInput {
        points: vec![(5.0, 5.0), (25.0, 25.0)],
        color_r: 0,
        color_g: 0,
        color_b: 0,
        color_a: 255,
        width: 2.0,
        opacity: 1.0,
        erase: false,
        brush_kind: 14,
        filled: false,
    };
    let out = bake_layers_on_rgba(base, vec![], vec![stroke]).expect("bake ok");
    let blurred = pixel(&out, 15, 15);
    assert_ne!(
        blurred, sharp,
        "blurred center {:?} should differ from sharp {:?}",
        blurred,
        sharp
    );
}

#[test]
fn bake_layers_local_pixelate_averages_blocks() {
    let base = checker_rgba(60, 60);
    let sharp_a = pixel(&base, 12, 12);
    let sharp_b = pixel(&base, 12, 18);
    let stroke = PaintStrokeInput {
        points: vec![(10.0, 10.0), (40.0, 40.0)],
        color_r: 0,
        color_g: 0,
        color_b: 0,
        color_a: 255,
        width: 2.0,
        opacity: 1.0,
        erase: false,
        brush_kind: 15,
        filled: false,
    };
    let out = bake_layers_on_rgba(base, vec![], vec![stroke]).expect("bake ok");
    let a = pixel(&out, 12, 12);
    let b = pixel(&out, 13, 13);
    assert_eq!(a, b, "pixelate block should be flat within a cell");
    assert_ne!(
        sharp_a, sharp_b,
        "checker source should differ at test coords"
    );
}

#[test]
fn bake_layers_filled_rect_paints_interior() {
    let base = solid_rgba(50, 50, 0, 0, 0, 255);
    let stroke = PaintStrokeInput {
        points: vec![(10.0, 10.0), (30.0, 30.0)],
        color_r: 0,
        color_g: 255,
        color_b: 0,
        color_a: 255,
        width: 2.0,
        opacity: 1.0,
        erase: false,
        brush_kind: 8,
        filled: true,
    };
    let out = bake_layers_on_rgba(base, vec![], vec![stroke]).expect("bake ok");
    let inside = pixel(&out, 20, 20);
    assert!(inside[1] > 200, "filled rect interior green = {}", inside[1]);
}
