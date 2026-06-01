use crate::api::face::LipTintPreset;
use crate::api::image::RgbaImageBuffer;

use super::SegmentationMask;

const MAX_EYE_LIFT: f32 = 0.35;

/// Lift luminance in masked eye regions.
pub fn apply_eye_brighten_rgba(
    buffer: &RgbaImageBuffer,
    mask: &SegmentationMask,
    strength: f32,
) -> RgbaImageBuffer {
    let strength = strength.clamp(0.0, 1.0);
    if strength <= 0.001 {
        return buffer.clone();
    }
    if mask.width != buffer.width || mask.height != buffer.height {
        return buffer.clone();
    }
    let lift = strength * MAX_EYE_LIFT;
    let mut out = buffer.pixels.clone();
    for i in 0..mask.pixels.len() {
        let m = mask.pixels[i] as f32 / 255.0;
        if m < 0.02 {
            continue;
        }
        let s = m * lift;
        let o = i * 4;
        for c in 0..3 {
            let v = out[o + c] as f32;
            let bright = v + (255.0 - v) * s;
            out[o + c] = bright.clamp(0.0, 255.0) as u8;
        }
    }
    RgbaImageBuffer {
        width: buffer.width,
        height: buffer.height,
        pixels: out,
    }
}

/// Soft cheek blush (multiply blend toward rosy tone).
pub fn apply_blush_rgba(
    buffer: &RgbaImageBuffer,
    mask: &SegmentationMask,
    strength: f32,
) -> RgbaImageBuffer {
    let strength = strength.clamp(0.0, 1.0);
    if strength <= 0.001 {
        return buffer.clone();
    }
    if mask.width != buffer.width || mask.height != buffer.height {
        return buffer.clone();
    }
    let mut out = buffer.pixels.clone();
    // Warm rose tint
    let tr = 220.0f32;
    let tg = 120.0;
    let tb = 130.0;
    for i in 0..mask.pixels.len() {
        let m = mask.pixels[i] as f32 / 255.0 * strength;
        if m < 0.02 {
            continue;
        }
        let o = i * 4;
        let r = out[o] as f32;
        let g = out[o + 1] as f32;
        let b = out[o + 2] as f32;
        out[o] = (r * (1.0 - m) + (r * tr / 255.0) * m).clamp(0.0, 255.0) as u8;
        out[o + 1] = (g * (1.0 - m) + (g * tg / 255.0) * m).clamp(0.0, 255.0) as u8;
        out[o + 2] = (b * (1.0 - m) + (b * tb / 255.0) * m).clamp(0.0, 255.0) as u8;
    }
    RgbaImageBuffer {
        width: buffer.width,
        height: buffer.height,
        pixels: out,
    }
}

fn lip_tint_hue(preset: LipTintPreset) -> Option<f32> {
    match preset {
        LipTintPreset::None => None,
        LipTintPreset::Nude => Some(18.0),
        LipTintPreset::Rose => Some(350.0),
        LipTintPreset::Berry => Some(330.0),
        LipTintPreset::Coral => Some(12.0),
        LipTintPreset::Red => Some(0.0),
    }
}

/// HSL-shift lip pixels toward preset hue.
pub fn apply_lip_tint_rgba(
    buffer: &RgbaImageBuffer,
    mask: &SegmentationMask,
    preset: LipTintPreset,
    strength: f32,
) -> RgbaImageBuffer {
    let strength = strength.clamp(0.0, 1.0);
    let target_h = match lip_tint_hue(preset) {
        Some(h) => h,
        None => return buffer.clone(),
    };
    if strength <= 0.001 {
        return buffer.clone();
    }
    if mask.width != buffer.width || mask.height != buffer.height {
        return buffer.clone();
    }
    let mut out = buffer.pixels.clone();
    for i in 0..mask.pixels.len() {
        let m = mask.pixels[i] as f32 / 255.0;
        if m < 0.02 {
            continue;
        }
        let s = m * strength * 0.88;
        if s < 0.03 {
            continue;
        }
        let o = i * 4;
        let (h, l, sat) = rgb_to_hsl(out[o] as f32, out[o + 1] as f32, out[o + 2] as f32);
        let new_h = lerp_angle(h, target_h, s * 0.85);
        let new_sat = (sat + 0.25 * s).min(1.0);
        let (r, g, b) = hsl_to_rgb(new_h, l, new_sat);
        out[o] = r as u8;
        out[o + 1] = g as u8;
        out[o + 2] = b as u8;
    }
    RgbaImageBuffer {
        width: buffer.width,
        height: buffer.height,
        pixels: out,
    }
}

fn lerp_angle(a: f32, b: f32, t: f32) -> f32 {
    let mut diff = b - a;
    while diff > 180.0 {
        diff -= 360.0;
    }
    while diff < -180.0 {
        diff += 360.0;
    }
    a + diff * t
}

fn rgb_to_hsl(r: f32, g: f32, b: f32) -> (f32, f32, f32) {
    let r = r / 255.0;
    let g = g / 255.0;
    let b = b / 255.0;
    let max = r.max(g).max(b);
    let min = r.min(g).min(b);
    let l = (max + min) * 0.5;
    if (max - min).abs() < 1e-6 {
        return (0.0, l, 0.0);
    }
    let d = max - min;
    let s = if l > 0.5 {
        d / (2.0 - max - min)
    } else {
        d / (max + min)
    };
    let h = if (max - r).abs() < 1e-6 {
        ((g - b) / d + if g < b { 6.0 } else { 0.0 }) * 60.0
    } else if (max - g).abs() < 1e-6 {
        ((b - r) / d + 2.0) * 60.0
    } else {
        ((r - g) / d + 4.0) * 60.0
    };
    (h, l, s)
}

fn hsl_to_rgb(h: f32, l: f32, s: f32) -> (f32, f32, f32) {
    if s <= 1e-6 {
        let v = l * 255.0;
        return (v, v, v);
    }
    let q = if l < 0.5 {
        l * (1.0 + s)
    } else {
        l + s - l * s
    };
    let p = 2.0 * l - q;
    let hk = (h / 360.0 + 1.0) % 1.0;
    let r = hue_to_rgb(p, q, hk + 1.0 / 3.0) * 255.0;
    let g = hue_to_rgb(p, q, hk) * 255.0;
    let b = hue_to_rgb(p, q, hk - 1.0 / 3.0) * 255.0;
    (r, g, b)
}

fn hue_to_rgb(p: f32, q: f32, mut t: f32) -> f32 {
    if t > 1.0 {
        t -= 1.0;
    }
    if t < 0.0 {
        t += 1.0;
    }
    if t < 1.0 / 6.0 {
        p + (q - p) * 6.0 * t
    } else if t < 1.0 / 2.0 {
        q
    } else if t < 2.0 / 3.0 {
        p + (q - p) * (2.0 / 3.0 - t) * 6.0
    } else {
        p
    }
}

const MAX_UNDER_EYE_SMOOTH: f32 = 0.50;

/// Gentle tone softening under eyes (Nexus E) — lighter than full skin smooth.
pub fn apply_under_eye_soften_rgba(
    buffer: &RgbaImageBuffer,
    mask: &SegmentationMask,
    strength: f32,
) -> RgbaImageBuffer {
    let strength = strength.clamp(0.0, 1.0);
    if strength <= 0.001 {
        return buffer.clone();
    }
    if mask.width != buffer.width || mask.height != buffer.height {
        return buffer.clone();
    }
    let effective = strength * MAX_UNDER_EYE_SMOOTH;
    let w = buffer.width as usize;
    let h = buffer.height as usize;
    let blurred = super::beauty::box_blur_separable(&buffer.pixels, w, h, 2);
    let mut out = buffer.pixels.clone();
    for i in 0..mask.pixels.len() {
        let m = mask.pixels[i] as f32 / 255.0 * effective;
        if m < 0.02 {
            continue;
        }
        let o = i * 4;
        for c in 0..3 {
            let v = out[o + c] as f32;
            let b = blurred[o + c] as f32;
            out[o + c] = (v * (1.0 - m) + b * m).clamp(0.0, 255.0) as u8;
        }
    }
    RgbaImageBuffer {
        width: buffer.width,
        height: buffer.height,
        pixels: out,
    }
}

/// Lift luminance and reduce yellow in teeth mask (Nexus E).
pub fn apply_teeth_whiten_rgba(
    buffer: &RgbaImageBuffer,
    mask: &SegmentationMask,
    strength: f32,
) -> RgbaImageBuffer {
    let strength = strength.clamp(0.0, 1.0);
    if strength <= 0.001 {
        return buffer.clone();
    }
    if mask.width != buffer.width || mask.height != buffer.height {
        return buffer.clone();
    }
    let lift = strength * 0.45;
    let desat = strength * 0.25;
    let mut out = buffer.pixels.clone();
    for i in 0..mask.pixels.len() {
        let m = mask.pixels[i] as f32 / 255.0;
        if m < 0.02 {
            continue;
        }
        let o = i * 4;
        let r = out[o] as f32;
        let g = out[o + 1] as f32;
        let b = out[o + 2] as f32;
        let luma = 0.299 * r + 0.587 * g + 0.114 * b;
        let lift_amt = (255.0 - luma) * lift * m;
        let mut nr = (r + lift_amt).min(255.0);
        let mut ng = (g + lift_amt).min(255.0);
        let mut nb = (b + lift_amt * 1.05).min(255.0);
        let avg = (nr + ng + nb) / 3.0;
        nr = nr * (1.0 - desat * m) + avg * (desat * m);
        ng = ng * (1.0 - desat * m) + avg * (desat * m);
        nb = nb * (1.0 - desat * m) + avg * (desat * m);
        out[o] = nr.clamp(0.0, 255.0) as u8;
        out[o + 1] = ng.clamp(0.0, 255.0) as u8;
        out[o + 2] = nb.clamp(0.0, 255.0) as u8;
    }
    RgbaImageBuffer {
        width: buffer.width,
        height: buffer.height,
        pixels: out,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn eye_brighten_changes_masked_pixel() {
        let buffer = RgbaImageBuffer {
            width: 2,
            height: 2,
            pixels: vec![80, 80, 80, 255, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        };
        let mask = SegmentationMask {
            width: 2,
            height: 2,
            pixels: vec![255, 0, 0, 0],
        };
        let out = apply_eye_brighten_rgba(&buffer, &mask, 1.0);
        assert!(out.pixels[0] > buffer.pixels[0]);
    }
}
