use crate::api::image::RgbaImageBuffer;

use super::{Landmark2D, SegmentationMask};

const MAX_PLUMP: f32 = 0.15;

/// Localized lip plump via backward radial sampling (0 = none, 1 = max plump).
pub fn apply_lip_plump_rgba(
    buffer: &RgbaImageBuffer,
    mask: &SegmentationMask,
    lip_center: (f32, f32),
    strength: f32,
) -> RgbaImageBuffer {
    let strength = strength.clamp(0.0, 1.0);
    if strength <= 0.001 {
        return buffer.clone();
    }
    if mask.width != buffer.width || mask.height != buffer.height {
        return buffer.clone();
    }
    let w = buffer.width as f32;
    let h = buffer.height as f32;
    let cx = lip_center.0 * w;
    let cy = lip_center.1 * h;
    let max_push = MAX_PLUMP * strength;
    let src = &buffer.pixels;
    let mut out = src.clone();

    for y in 0..buffer.height as usize {
        for x in 0..buffer.width as usize {
            let mi = y * buffer.width as usize + x;
            let m = mask.pixels[mi] as f32 / 255.0;
            if m < 0.05 {
                continue;
            }
            let fx = x as f32;
            let fy = y as f32;
            let dx = fx - cx;
            let dy = fy - cy;
            let dist = (dx * dx + dy * dy).sqrt().max(1.0);
            let push = max_push * m * 40.0 / dist;
            let sx = (fx - dx / dist * push).clamp(0.0, w - 1.0);
            let sy = (fy - dy / dist * push).clamp(0.0, h - 1.0);
            let o = mi * 4;
            let (r, g, b, a) = sample_bilinear(src, buffer.width, buffer.height, sx, sy);
            out[o] = r;
            out[o + 1] = g;
            out[o + 2] = b;
            out[o + 3] = a;
        }
    }

    RgbaImageBuffer {
        width: buffer.width,
        height: buffer.height,
        pixels: out,
    }
}

pub fn lip_center_from_landmarks(lips: &[Landmark2D]) -> (f32, f32) {
    if lips.is_empty() {
        return (0.5, 0.5);
    }
    let mut sx = 0.0f32;
    let mut sy = 0.0f32;
    for p in lips {
        sx += p.x;
        sy += p.y;
    }
    let n = lips.len() as f32;
    (sx / n, sy / n)
}

fn sample_bilinear(pixels: &[u8], width: u32, height: u32, x: f32, y: f32) -> (u8, u8, u8, u8) {
    let w = width as i32;
    let h = height as i32;
    let x0 = x.floor() as i32;
    let y0 = y.floor() as i32;
    let x1 = (x0 + 1).min(w - 1);
    let y1 = (y0 + 1).min(h - 1);
    let tx = x - x0 as f32;
    let ty = y - y0 as f32;
    let x0 = x0.clamp(0, w - 1);
    let y0 = y0.clamp(0, h - 1);

    let mut out = [0u8; 4];
    for c in 0..4 {
        let v00 = pixel_at(pixels, width, x0, y0, c);
        let v10 = pixel_at(pixels, width, x1, y0, c);
        let v01 = pixel_at(pixels, width, x0, y1, c);
        let v11 = pixel_at(pixels, width, x1, y1, c);
        let top = v00 as f32 * (1.0 - tx) + v10 as f32 * tx;
        let bot = v01 as f32 * (1.0 - tx) + v11 as f32 * tx;
        out[c] = (top * (1.0 - ty) + bot * ty).clamp(0.0, 255.0) as u8;
    }
    (out[0], out[1], out[2], out[3])
}

fn pixel_at(pixels: &[u8], width: u32, x: i32, y: i32, c: usize) -> u8 {
    pixels[(y as usize * width as usize + x as usize) * 4 + c]
}
