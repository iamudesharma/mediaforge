use rayon::prelude::*;

pub const MIN_PIXELS_FOR_PAR: usize = 100_000;

pub fn par_brightness(pixels: &mut [u8], amount: i16) {
    if pixels.len() < MIN_PIXELS_FOR_PAR * 4 {
        for px in pixels.chunks_exact_mut(4) {
            px[0] = (px[0] as i16 + amount).clamp(0, 255) as u8;
            px[1] = (px[1] as i16 + amount).clamp(0, 255) as u8;
            px[2] = (px[2] as i16 + amount).clamp(0, 255) as u8;
        }
    } else {
        pixels.par_chunks_mut(4).for_each(|px| {
            px[0] = (px[0] as i16 + amount).clamp(0, 255) as u8;
            px[1] = (px[1] as i16 + amount).clamp(0, 255) as u8;
            px[2] = (px[2] as i16 + amount).clamp(0, 255) as u8;
        });
    }
}

pub fn par_contrast(pixels: &mut [u8], adjust: f32) {
    let adjust = adjust.clamp(-255.0, 254.0);
    let factor = (259.0 * (adjust + 255.0)) / (255.0 * (259.0 - adjust));

    if pixels.len() < MIN_PIXELS_FOR_PAR * 4 {
        for px in pixels.chunks_exact_mut(4) {
            for c in &mut px[..3] {
                let val = factor * (*c as f32 - 128.0) + 128.0;
                *c = val.clamp(0.0, 255.0) as u8;
            }
        }
    } else {
        pixels.par_chunks_mut(4).for_each(|px| {
            for c in &mut px[..3] {
                let val = factor * (*c as f32 - 128.0) + 128.0;
                *c = val.clamp(0.0, 255.0) as u8;
            }
        });
    }
}

pub fn par_saturation(pixels: &mut [u8], level: f32) {
    if pixels.len() < MIN_PIXELS_FOR_PAR * 4 {
        for px in pixels.chunks_exact_mut(4) {
            let (h, s, v) = rgb_to_hsv(px[0], px[1], px[2]);
            let new_s = (s * level).clamp(0.0, 1.0);
            let (r, g, b) = hsv_to_rgb(h, new_s, v);
            px[0] = r;
            px[1] = g;
            px[2] = b;
        }
    } else {
        pixels.par_chunks_mut(4).for_each(|px| {
            let (h, s, v) = rgb_to_hsv(px[0], px[1], px[2]);
            let new_s = (s * level).clamp(0.0, 1.0);
            let (r, g, b) = hsv_to_rgb(h, new_s, v);
            px[0] = r;
            px[1] = g;
            px[2] = b;
        });
    }
}

pub fn par_hue_rotate(pixels: &mut [u8], degrees: f32) {
    if pixels.len() < MIN_PIXELS_FOR_PAR * 4 {
        for px in pixels.chunks_exact_mut(4) {
            let (h, s, v) = rgb_to_hsv(px[0], px[1], px[2]);
            let mut new_h = h + degrees;
            if new_h < 0.0 {
                new_h = (new_h % 360.0) + 360.0;
            }
            new_h = new_h % 360.0;
            let (r, g, b) = hsv_to_rgb(new_h, s, v);
            px[0] = r;
            px[1] = g;
            px[2] = b;
        }
    } else {
        pixels.par_chunks_mut(4).for_each(|px| {
            let (h, s, v) = rgb_to_hsv(px[0], px[1], px[2]);
            let mut new_h = h + degrees;
            if new_h < 0.0 {
                new_h = (new_h % 360.0) + 360.0;
            }
            new_h = new_h % 360.0;
            let (r, g, b) = hsv_to_rgb(new_h, s, v);
            px[0] = r;
            px[1] = g;
            px[2] = b;
        });
    }
}

#[inline]
fn rgb_to_hsv(r: u8, g: u8, b: u8) -> (f32, f32, f32) {
    let r = r as f32 / 255.0;
    let g = g as f32 / 255.0;
    let b = b as f32 / 255.0;

    let max = r.max(g).max(b);
    let min = r.min(g).min(b);
    let delta = max - min;

    let h = if delta == 0.0 {
        0.0
    } else if max == r {
        60.0 * (((g - b) / delta) % 6.0)
    } else if max == g {
        60.0 * (((b - r) / delta) + 2.0)
    } else {
        60.0 * (((r - g) / delta) + 4.0)
    };

    let h = if h < 0.0 { h + 360.0 } else { h };
    let s = if max == 0.0 { 0.0 } else { delta / max };
    let v = max;

    (h, s, v)
}

#[inline]
fn hsv_to_rgb(h: f32, s: f32, v: f32) -> (u8, u8, u8) {
    let c = v * s;
    let x = c * (1.0 - ((h / 60.0) % 2.0 - 1.0).abs());
    let m = v - c;

    let (r, g, b) = if h >= 0.0 && h < 60.0 {
        (c, x, 0.0)
    } else if h >= 60.0 && h < 120.0 {
        (x, c, 0.0)
    } else if h >= 120.0 && h < 180.0 {
        (0.0, c, x)
    } else if h >= 180.0 && h < 240.0 {
        (0.0, x, c)
    } else if h >= 240.0 && h < 300.0 {
        (x, 0.0, c)
    } else {
        (c, 0.0, x)
    };

    (
        ((r + m) * 255.0).round().clamp(0.0, 255.0) as u8,
        ((g + m) * 255.0).round().clamp(0.0, 255.0) as u8,
        ((b + m) * 255.0).round().clamp(0.0, 255.0) as u8,
    )
}
