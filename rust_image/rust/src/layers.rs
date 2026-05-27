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
    pub erase: bool,
    pub brush_kind: u8,
    pub filled: bool,
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
    let (w, h) = (base.width, base.height);

    // 1. Apply local censors (blur/pixelate) directly on base
    for stroke in strokes {
        if stroke.erase || stroke.points.len() < 2 {
            continue;
        }
        if stroke.brush_kind == 14 {
            let x_min = stroke.points[0].0.min(stroke.points[1].0).round() as i32;
            let x_max = stroke.points[0].0.max(stroke.points[1].0).round() as i32;
            let y_min = stroke.points[0].1.min(stroke.points[1].1).round() as i32;
            let y_max = stroke.points[0].1.max(stroke.points[1].1).round() as i32;
            let x_start = x_min.clamp(0, w as i32) as u32;
            let x_end = x_max.clamp(0, w as i32) as u32;
            let y_start = y_min.clamp(0, h as i32) as u32;
            let y_end = y_max.clamp(0, h as i32) as u32;
            if x_end > x_start && y_end > y_start {
                apply_local_blur(&mut base, x_start, y_start, x_end - x_start, y_end - y_start, 15);
            }
        } else if stroke.brush_kind == 15 {
            let x_min = stroke.points[0].0.min(stroke.points[1].0).round() as i32;
            let x_max = stroke.points[0].0.max(stroke.points[1].0).round() as i32;
            let y_min = stroke.points[0].1.min(stroke.points[1].1).round() as i32;
            let y_max = stroke.points[0].1.max(stroke.points[1].1).round() as i32;
            let x_start = x_min.clamp(0, w as i32) as u32;
            let x_end = x_max.clamp(0, w as i32) as u32;
            let y_start = y_min.clamp(0, h as i32) as u32;
            let y_end = y_max.clamp(0, h as i32) as u32;
            if x_end > x_start && y_end > y_start {
                apply_local_pixelate(&mut base, x_start, y_start, x_end - x_start, y_end - y_start, 15);
            }
        }
    }

    // 2. Draw regular paint strokes on paint_only
    let mut paint_only = RgbaImage::from_pixel(w, h, Rgba([0, 0, 0, 0]));
    for stroke in strokes {
        if stroke.erase || stroke.points.len() < 2 {
            continue;
        }
        if stroke.brush_kind == 14 || stroke.brush_kind == 15 {
            continue;
        }
        draw_stroke_on_image(&mut paint_only, stroke);
    }

    // 3. Apply erases
    for stroke in strokes {
        if !stroke.erase || stroke.points.len() < 2 {
            continue;
        }
        erase_stroke_on_image(&mut paint_only, stroke);
    }

    blend_overlay_at_buffer(&mut base, &paint_only, 0, 0);
    Ok(base)
}

fn apply_local_blur(base: &mut RgbaImageBuffer, x_start: u32, y_start: u32, crop_w: u32, crop_h: u32, radius: usize) {
    if crop_w == 0 || crop_h == 0 {
        return;
    }
    let mut temp = vec![[0u8; 4]; (crop_w * crop_h) as usize];
    let bw = base.width;
    for y in 0..crop_h {
        for x in 0..crop_w {
            let bx = x_start + x;
            let by = y_start + y;
            let bi = ((by * bw + bx) * 4) as usize;
            temp[(y * crop_w + x) as usize] = [
                base.pixels[bi],
                base.pixels[bi + 1],
                base.pixels[bi + 2],
                base.pixels[bi + 3],
            ];
        }
    }

    // Horizontal pass
    let mut temp_h = temp.clone();
    let r = radius as i32;
    for y in 0..crop_h as i32 {
        for x in 0..crop_w as i32 {
            let mut sum_r = 0u32;
            let mut sum_g = 0u32;
            let mut sum_b = 0u32;
            let mut sum_a = 0u32;
            let mut count = 0u32;
            for dx in -r..=r {
                let px = (x + dx).clamp(0, crop_w as i32 - 1) as u32;
                let pixel = temp[(y as u32 * crop_w + px) as usize];
                sum_r += pixel[0] as u32;
                sum_g += pixel[1] as u32;
                sum_b += pixel[2] as u32;
                sum_a += pixel[3] as u32;
                count += 1;
            }
            temp_h[(y as u32 * crop_w + x as u32) as usize] = [
                (sum_r / count) as u8,
                (sum_g / count) as u8,
                (sum_b / count) as u8,
                (sum_a / count) as u8,
            ];
        }
    }

    // Vertical pass
    let mut temp_v = temp_h.clone();
    for y in 0..crop_h as i32 {
        for x in 0..crop_w as i32 {
            let mut sum_r = 0u32;
            let mut sum_g = 0u32;
            let mut sum_b = 0u32;
            let mut sum_a = 0u32;
            let mut count = 0u32;
            for dy in -r..=r {
                let py = (y + dy).clamp(0, crop_h as i32 - 1) as u32;
                let pixel = temp_h[(py * crop_w + x as u32) as usize];
                sum_r += pixel[0] as u32;
                sum_g += pixel[1] as u32;
                sum_b += pixel[2] as u32;
                sum_a += pixel[3] as u32;
                count += 1;
            }
            temp_v[(y as u32 * crop_w + x as u32) as usize] = [
                (sum_r / count) as u8,
                (sum_g / count) as u8,
                (sum_b / count) as u8,
                (sum_a / count) as u8,
            ];
        }
    }

    // Write back
    for y in 0..crop_h {
        for x in 0..crop_w {
            let bx = x_start + x;
            let by = y_start + y;
            let bi = ((by * bw + bx) * 4) as usize;
            let pixel = temp_v[(y * crop_w + x) as usize];
            base.pixels[bi] = pixel[0];
            base.pixels[bi + 1] = pixel[1];
            base.pixels[bi + 2] = pixel[2];
            base.pixels[bi + 3] = pixel[3];
        }
    }
}

fn apply_local_pixelate(base: &mut RgbaImageBuffer, x_start: u32, y_start: u32, crop_w: u32, crop_h: u32, block_size: u32) {
    if crop_w == 0 || crop_h == 0 || block_size == 0 {
        return;
    }
    let bw = base.width;

    for by in (0..crop_h).step_by(block_size as usize) {
        for bx in (0..crop_w).step_by(block_size as usize) {
            let bx_end = (bx + block_size).min(crop_w);
            let by_end = (by + block_size).min(crop_h);

            let mut sum_r = 0u64;
            let mut sum_g = 0u64;
            let mut sum_b = 0u64;
            let mut sum_a = 0u64;
            let mut count = 0u64;

            for y in by..by_end {
                for x in bx..bx_end {
                    let pixel_x = x_start + x;
                    let pixel_y = y_start + y;
                    let bi = ((pixel_y * bw + pixel_x) * 4) as usize;
                    sum_r += base.pixels[bi] as u64;
                    sum_g += base.pixels[bi + 1] as u64;
                    sum_b += base.pixels[bi + 2] as u64;
                    sum_a += base.pixels[bi + 3] as u64;
                    count += 1;
                }
            }

            if count > 0 {
                let avg_r = (sum_r / count) as u8;
                let avg_g = (sum_g / count) as u8;
                let avg_b = (sum_b / count) as u8;
                let avg_a = (sum_a / count) as u8;

                for y in by..by_end {
                    for x in bx..bx_end {
                        let pixel_x = x_start + x;
                        let pixel_y = y_start + y;
                        let bi = ((pixel_y * bw + pixel_x) * 4) as usize;
                        base.pixels[bi] = avg_r;
                        base.pixels[bi + 1] = avg_g;
                        base.pixels[bi + 2] = avg_b;
                        base.pixels[bi + 3] = avg_a;
                    }
                }
            }
        }
    }
}

fn stroke_effective_width(stroke: &PaintStroke) -> f32 {
    let base = stroke.width.max(1.0);
    match stroke.brush_kind {
        1 => base * 1.4,
        2 => base * 2.2,
        4 => base * 1.25,
        _ => base,
    }
}

fn stroke_draw_color(stroke: &PaintStroke) -> Rgba<u8> {
    let mut r = stroke.color_r;
    let mut g = stroke.color_g;
    let mut b = stroke.color_b;
    let mut a = ((stroke.color_a as f32) * stroke.opacity.clamp(0.0, 1.0)).round() as u8;
    match stroke.brush_kind {
        2 => a = ((a as f32) * 0.35).round() as u8,
        4 => {
            r = r.saturating_add(40);
            g = g.saturating_add(40);
            b = (b as u16).saturating_add(80).min(255) as u8;
        }
        _ => {}
    }
    Rgba([r, g, b, a])
}

fn draw_thick_line_segment(img: &mut RgbaImage, p1: (f32, f32), p2: (f32, f32), color: Rgba<u8>, width: f32) {
    draw_line_segment_mut(img, p1, p2, color);
    let r = (width / 2.0) as i32;
    if r > 0 {
        imageproc::drawing::draw_filled_circle_mut(img, (p1.0 as i32, p1.1 as i32), r, color);
        imageproc::drawing::draw_filled_circle_mut(img, (p2.0 as i32, p2.1 as i32), r, color);
    }
}

fn draw_arrow(img: &mut RgbaImage, start: (f32, f32), end: (f32, f32), color: Rgba<u8>, thickness: f32, double_arrow: bool) {
    draw_thick_line_segment(img, start, end, color, thickness);

    let dx = end.0 - start.0;
    let dy = end.1 - start.1;
    let theta = dy.atan2(dx);
    let arrow_angle = std::f32::consts::PI / 6.0;
    let arrow_length = 16.0f32;

    let x1 = end.0 - arrow_length * (theta - arrow_angle).cos();
    let y1 = end.1 - arrow_length * (theta - arrow_angle).sin();
    let x2 = end.0 - arrow_length * (theta + arrow_angle).cos();
    let y2 = end.1 - arrow_length * (theta + arrow_angle).sin();

    draw_thick_line_segment(img, end, (x1, y1), color, thickness);
    draw_thick_line_segment(img, end, (x2, y2), color, thickness);

    if double_arrow {
        let bx1 = start.0 + arrow_length * (theta - arrow_angle).cos();
        let by1 = start.1 + arrow_length * (theta - arrow_angle).sin();
        let bx2 = start.0 + arrow_length * (theta + arrow_angle).cos();
        let by2 = start.1 + arrow_length * (theta + arrow_angle).sin();

        draw_thick_line_segment(img, start, (bx1, by1), color, thickness);
        draw_thick_line_segment(img, start, (bx2, by2), color, thickness);
    }
}

fn draw_dashed_line(img: &mut RgbaImage, start: (f32, f32), end: (f32, f32), color: Rgba<u8>, thickness: f32, dash_length: f32, gap_length: f32) {
    let dx = end.0 - start.0;
    let dy = end.1 - start.1;
    let distance = (dx * dx + dy * dy).sqrt();
    if distance == 0.0 {
        return;
    }
    let dir_x = dx / distance;
    let dir_y = dy / distance;

    let mut current_distance = 0.0f32;
    while current_distance < distance {
        let next_dash = (current_distance + dash_length).min(distance);
        let p1 = (start.0 + dir_x * current_distance, start.1 + dir_y * current_distance);
        let p2 = (start.0 + dir_x * next_dash, start.1 + dir_y * next_dash);

        draw_thick_line_segment(img, p1, p2, color, thickness);
        current_distance += dash_length + gap_length;
    }
}

fn draw_dash_dot_line(img: &mut RgbaImage, start: (f32, f32), end: (f32, f32), color: Rgba<u8>, thickness: f32) {
    let dx = end.0 - start.0;
    let dy = end.1 - start.1;
    let distance = (dx * dx + dy * dy).sqrt();
    if distance == 0.0 {
        return;
    }
    let dir_x = dx / distance;
    let dir_y = dy / distance;

    let dash_len = 10.0f32;
    let gap_len = 5.0f32;
    let dot_len = 2.0f32;

    let mut current_distance = 0.0f32;
    let mut is_dash = true;
    while current_distance < distance {
        if is_dash {
            let next_dash = (current_distance + dash_len).min(distance);
            let p1 = (start.0 + dir_x * current_distance, start.1 + dir_y * current_distance);
            let p2 = (start.0 + dir_x * next_dash, start.1 + dir_y * next_dash);
            draw_thick_line_segment(img, p1, p2, color, thickness);
            current_distance += dash_len + gap_len;
        } else {
            let next_dot = (current_distance + dot_len).min(distance);
            let p1 = (start.0 + dir_x * current_distance, start.1 + dir_y * current_distance);
            let p2 = (start.0 + dir_x * next_dot, start.1 + dir_y * next_dot);
            draw_thick_line_segment(img, p1, p2, color, thickness);
            current_distance += dot_len + gap_len;
        }
        is_dash = !is_dash;
    }
}

fn get_hexagon_vertices(center: (f32, f32), radius: f32) -> Vec<(f32, f32)> {
    let mut vertices = Vec::with_capacity(6);
    for i in 0..6 {
        let angle = (i as f32) * std::f32::consts::PI / 3.0;
        vertices.push((
            center.0 + radius * angle.cos(),
            center.1 + radius * angle.sin(),
        ));
    }
    vertices
}

fn draw_filled_polygon(img: &mut RgbaImage, vertices: &[(f32, f32)], color: Rgba<u8>) {
    if vertices.len() < 3 {
        return;
    }
    let mut min_x = vertices[0].0;
    let mut max_x = vertices[0].0;
    let mut min_y = vertices[0].1;
    let mut max_y = vertices[0].1;
    for &p in vertices.iter().skip(1) {
        if p.0 < min_x { min_x = p.0; }
        if p.0 > max_x { max_x = p.0; }
        if p.1 < min_y { min_y = p.1; }
        if p.1 > max_y { max_y = p.1; }
    }

    let x_start = min_x.floor().max(0.0) as i32;
    let x_end = max_x.ceil().min(img.width() as f32 - 1.0) as i32;
    let y_start = min_y.floor().max(0.0) as i32;
    let y_end = max_y.ceil().min(img.height() as f32 - 1.0) as i32;

    for y in y_start..=y_end {
        for x in x_start..=x_end {
            let px = x as f32;
            let py = y as f32;
            let mut inside = false;
            let mut j = vertices.len() - 1;
            for i in 0..vertices.len() {
                let pi = vertices[i];
                let pj = vertices[j];
                if ((pi.1 > py) != (pj.1 > py))
                    && (px < (pj.0 - pi.0) * (py - pi.1) / (pj.1 - pi.1) + pi.0)
                {
                    inside = !inside;
                }
                j = i;
            }
            if inside {
                img.put_pixel(x as u32, y as u32, color);
            }
        }
    }
}

fn draw_stroke_on_image(img: &mut RgbaImage, stroke: &PaintStroke) {
    let color = stroke_draw_color(stroke);
    let w = stroke_effective_width(stroke);

    match stroke.brush_kind {
        0 | 1 | 2 | 4 => {
            if stroke.brush_kind == 4 {
                let glow = Rgba([
                    color[0],
                    color[1],
                    color[2],
                    ((color[3] as f32) * 0.25).round() as u8,
                ]);
                let glow_w = w * 2.5;
                for window in stroke.points.windows(2) {
                    let (x0, y0) = window[0];
                    let (x1, y1) = window[1];
                    draw_line_segment_mut(img, (x0, y0), (x1, y1), glow);
                    let r = (glow_w / 2.0) as i32;
                    imageproc::drawing::draw_filled_circle_mut(
                        img,
                        (x1 as i32, y1 as i32),
                        r.max(2),
                        glow,
                    );
                }
            }
            for window in stroke.points.windows(2) {
                let (x0, y0) = window[0];
                let (x1, y1) = window[1];
                draw_line_segment_mut(img, (x0, y0), (x1, y1), color);
                let r = (w / 2.0) as i32;
                imageproc::drawing::draw_filled_circle_mut(
                    img,
                    (x1 as i32, y1 as i32),
                    r.max(1),
                    color,
                );
            }
        }
        5 => {
            if stroke.points.len() >= 2 {
                draw_thick_line_segment(img, stroke.points[0], stroke.points[1], color, w);
            }
        }
        6 => {
            if stroke.points.len() >= 2 {
                draw_arrow(img, stroke.points[0], stroke.points[1], color, w, false);
            }
        }
        7 => {
            if stroke.points.len() >= 2 {
                draw_arrow(img, stroke.points[0], stroke.points[1], color, w, true);
            }
        }
        8 => {
            if stroke.points.len() >= 2 {
                let p1 = stroke.points[0];
                let p2 = stroke.points[1];
                if stroke.filled {
                    let x_min = p1.0.min(p2.0).round() as i32;
                    let x_max = p1.0.max(p2.0).round() as i32;
                    let y_min = p1.1.min(p2.1).round() as i32;
                    let y_max = p1.1.max(p2.1).round() as i32;
                    for y in y_min..=y_max {
                        for x in x_min..=x_max {
                            if x >= 0 && y >= 0 && x < img.width() as i32 && y < img.height() as i32 {
                                img.put_pixel(x as u32, y as u32, color);
                            }
                        }
                    }
                } else {
                    let x_min = p1.0.min(p2.0);
                    let x_max = p1.0.max(p2.0);
                    let y_min = p1.1.min(p2.1);
                    let y_max = p1.1.max(p2.1);

                    draw_thick_line_segment(img, (x_min, y_min), (x_max, y_min), color, w);
                    draw_thick_line_segment(img, (x_max, y_min), (x_max, y_max), color, w);
                    draw_thick_line_segment(img, (x_max, y_max), (x_min, y_max), color, w);
                    draw_thick_line_segment(img, (x_min, y_max), (x_min, y_min), color, w);
                }
            }
        }
        9 => {
            if stroke.points.len() >= 2 {
                let center = stroke.points[0];
                let dx = stroke.points[1].0 - center.0;
                let dy = stroke.points[1].1 - center.1;
                let r = (dx * dx + dy * dy).sqrt();

                if stroke.filled {
                    let x_min = (center.0 - r).floor() as i32;
                    let x_max = (center.0 + r).ceil() as i32;
                    let y_min = (center.1 - r).floor() as i32;
                    let y_max = (center.1 + r).ceil() as i32;
                    let r_sq = r * r;
                    for y in y_min..=y_max {
                        for x in x_min..=x_max {
                            if x >= 0 && y >= 0 && x < img.width() as i32 && y < img.height() as i32 {
                                let dx = x as f32 - center.0;
                                let dy = y as f32 - center.1;
                                if dx * dx + dy * dy <= r_sq {
                                    img.put_pixel(x as u32, y as u32, color);
                                }
                            }
                        }
                    }
                } else {
                    let x_min = (center.0 - r - w / 2.0).floor() as i32;
                    let x_max = (center.0 + r + w / 2.0).ceil() as i32;
                    let y_min = (center.1 - r - w / 2.0).floor() as i32;
                    let y_max = (center.1 + r + w / 2.0).ceil() as i32;
                    let half_t = w / 2.0;
                    for y in y_min..=y_max {
                        for x in x_min..=x_max {
                            if x >= 0 && y >= 0 && x < img.width() as i32 && y < img.height() as i32 {
                                let dx = x as f32 - center.0;
                                let dy = y as f32 - center.1;
                                let dist = (dx * dx + dy * dy).sqrt();
                                if (dist - r).abs() <= half_t {
                                    img.put_pixel(x as u32, y as u32, color);
                                }
                            }
                        }
                    }
                }
            }
        }
        10 => {
            if stroke.points.len() >= 2 {
                let center = stroke.points[0];
                let dx = stroke.points[1].0 - center.0;
                let dy = stroke.points[1].1 - center.1;
                let r = (dx * dx + dy * dy).sqrt();
                let vertices = get_hexagon_vertices(center, r);

                if stroke.filled {
                    draw_filled_polygon(img, &vertices, color);
                } else {
                    for i in 0..6 {
                        draw_thick_line_segment(img, vertices[i], vertices[(i + 1) % 6], color, w);
                    }
                }
            }
        }
        11 => {
            if stroke.points.len() >= 3 {
                if stroke.filled {
                    draw_filled_polygon(img, &stroke.points, color);
                } else {
                    for i in 0..stroke.points.len() {
                        draw_thick_line_segment(img, stroke.points[i], stroke.points[(i + 1) % stroke.points.len()], color, w);
                    }
                }
            }
        }
        12 => {
            if stroke.points.len() >= 2 {
                draw_dashed_line(img, stroke.points[0], stroke.points[1], color, w, 8.0, 6.0);
            }
        }
        13 => {
            if stroke.points.len() >= 2 {
                draw_dash_dot_line(img, stroke.points[0], stroke.points[1], color, w);
            }
        }
        _ => {}
    }
}

fn erase_stroke_on_image(img: &mut RgbaImage, stroke: &PaintStroke) {
    let clear = Rgba([0, 0, 0, 0]);
    let w = stroke_effective_width(stroke);
    for window in stroke.points.windows(2) {
        let (x0, y0) = window[0];
        let (x1, y1) = window[1];
        draw_line_segment_mut(img, (x0, y0), (x1, y1), clear);
        let r = (w / 2.0) as i32;
        imageproc::drawing::draw_filled_circle_mut(
            img,
            (x1 as i32, y1 as i32),
            r.max(1),
            clear,
        );
    }
}

fn blend_overlay_at_buffer(base: &mut RgbaImageBuffer, overlay: &RgbaImage, x: i32, y: i32) {
    let (ow, oh) = overlay.dimensions();
    for oy in 0..oh {
        for ox in 0..ow {
            let bx = x + ox as i32;
            let by = y + oy as i32;
            if bx < 0
                || by < 0
                || bx >= base.width as i32
                || by >= base.height as i32
            {
                continue;
            }
            let o = overlay.get_pixel(ox, oy);
            if o[3] == 0 {
                continue;
            }
            let bi = ((by as u32 * base.width + bx as u32) * 4) as usize;
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
