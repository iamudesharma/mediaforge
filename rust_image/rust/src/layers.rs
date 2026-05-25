use image::{imageops, Rgba, RgbaImage};
use imageproc::drawing::draw_line_segment_mut;
use imageproc::geometric_transformations::{rotate_about_center, Interpolation};

use crate::api::image::RgbaImageBuffer;

/// Layer bitmap + transform for export bake (Dart rasterizes emoji/text/stickers).
#[derive(Debug, Clone)]
pub struct RasterLayer {
    pub pixels: Vec<u8>,
    pub width: u32,
    pub height: u32,
    pub center_x: f32,
    pub center_y: f32,
    pub scale: f32,
    pub rotation_rad: f32,
    pub opacity: f32,
}

#[derive(Debug, Clone)]
pub struct PaintStroke {
    pub points: Vec<(f32, f32)>,
    pub color_r: u8,
    pub color_g: u8,
    pub color_b: u8,
    pub color_a: u8,
    pub width: f32,
    pub opacity: f32,
}

pub fn composite_raster_layer(
    mut base: RgbaImageBuffer,
    layer: &RasterLayer,
) -> Result<RgbaImageBuffer, String> {
    if layer.pixels.is_empty() || layer.width == 0 || layer.height == 0 {
        return Ok(base);
    }

    let mut overlay = RgbaImage::from_raw(layer.width, layer.height, layer.pixels.clone())
        .ok_or_else(|| "invalid layer bitmap".to_string())?;

    if layer.scale != 1.0 && layer.scale > 0.0 {
        let nw = ((layer.width as f32) * layer.scale).round().max(1.0) as u32;
        let nh = ((layer.height as f32) * layer.scale).round().max(1.0) as u32;
        overlay = image::imageops::resize(
            &overlay,
            nw,
            nh,
            image::imageops::FilterType::Triangle,
        );
    }

    if layer.rotation_rad.abs() > 0.001 {
        overlay = rotate_about_center(
            &overlay,
            layer.rotation_rad,
            Interpolation::Bilinear,
            Rgba([0, 0, 0, 0]),
        );
    }

    let (ow, oh) = overlay.dimensions();
    let cx = layer.center_x.round() as i32;
    let cy = layer.center_y.round() as i32;
    let x = cx - (ow as i32 / 2);
    let y = cy - (oh as i32 / 2);

    let opacity = layer.opacity.clamp(0.0, 1.0);
    if opacity < 0.999 {
        for p in overlay.pixels_mut() {
            p[3] = ((p[3] as f32) * opacity).round() as u8;
        }
    }

    blend_overlay_at(&mut base, &overlay, x, y);
    Ok(base)
}

fn blend_overlay_at(base: &mut RgbaImageBuffer, overlay: &RgbaImage, x: i32, y: i32) {
    let (ow, oh) = overlay.dimensions();
    let bw = base.width;
    let bh = base.height;

    for oy in 0..oh {
        for ox in 0..ow {
            let bx = x + ox as i32;
            let by = y + oy as i32;
            if bx < 0 || by < 0 || bx >= bw as i32 || by >= bh as i32 {
                continue;
            }
            let o = overlay.get_pixel(ox, oy);
            if o[3] == 0 {
                continue;
            }
            let bi = ((by as u32 * bw + bx as u32) * 4) as usize;
            let src_a = o[3] as f32 / 255.0;
            let dst_a = base.pixels[bi + 3] as f32 / 255.0;
            let out_a = src_a + dst_a * (1.0 - src_a);
            if out_a < 0.001 {
                continue;
            }
            for c in 0..3 {
                let src = o[c] as f32;
                let dst = base.pixels[bi + c] as f32;
                let out = (src * src_a + dst * dst_a * (1.0 - src_a)) / out_a;
                base.pixels[bi + c] = out.round().clamp(0.0, 255.0) as u8;
            }
            base.pixels[bi + 3] = (out_a * 255.0).round().clamp(0.0, 255.0) as u8;
        }
    }
}

pub fn composite_paint_strokes(
    mut base: RgbaImageBuffer,
    strokes: &[PaintStroke],
) -> Result<RgbaImageBuffer, String> {
    let mut img = RgbaImage::from_raw(base.width, base.height, base.pixels.clone())
        .ok_or_else(|| "invalid base".to_string())?;

    for stroke in strokes {
        if stroke.points.len() < 2 {
            continue;
        }
        let color = Rgba([
            stroke.color_r,
            stroke.color_g,
            stroke.color_b,
            ((stroke.color_a as f32) * stroke.opacity.clamp(0.0, 1.0)).round() as u8,
        ]);
        let w = stroke.width.max(1.0);
        for window in stroke.points.windows(2) {
            let (x0, y0) = window[0];
            let (x1, y1) = window[1];
            draw_line_segment_mut(
                &mut img,
                (x0, y0),
                (x1, y1),
                color,
            );
            // Thicken line with a filled circle at joints
            let r = (w / 2.0) as i32;
            imageproc::drawing::draw_filled_circle_mut(
                &mut img,
                (x1 as i32, y1 as i32),
                r.max(1),
                color,
            );
        }
    }

    base.pixels = img.into_raw();
    Ok(base)
}

pub fn bake_overlay_layers(
    buffer: RgbaImageBuffer,
    raster_layers: Vec<RasterLayer>,
    paint_strokes: Vec<PaintStroke>,
) -> Result<RgbaImageBuffer, String> {
    let mut out = buffer;
    for layer in &raster_layers {
        out = composite_raster_layer(out, layer)?;
    }
    if !paint_strokes.is_empty() {
        out = composite_paint_strokes(out, &paint_strokes)?;
    }
    Ok(out)
}
