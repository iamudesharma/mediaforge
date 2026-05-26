use crate::api::face::BeautyParams;
use crate::api::image::RgbaImageBuffer;

use super::makeup::{
    apply_blush_rgba, apply_eye_brighten_rgba, apply_lip_tint_rgba, apply_teeth_whiten_rgba,
    apply_under_eye_soften_rgba,
};
use super::regions::{
    apply_exclude_mask, build_blush_mask, build_eye_mask, build_lip_mask, build_teeth_mask,
    build_under_eye_mask,
};
use super::warp::{apply_lip_plump_rgba, lip_center_from_landmarks};
use super::{FaceAnalysisResult, Landmark2D, LandmarkRegions, SegmentationMask};

fn lip_center_from_analysis(landmarks: &[Landmark2D], regions: LandmarkRegions) -> (f32, f32) {
    let (s, n) = regions.inner_lips;
    if n > 0 && s + n <= landmarks.len() {
        let inner = &landmarks[s..s + n];
        // Bias plump center toward lower lip (beards often pull outer landmarks up).
        let mut sy = 0.0f32;
        let mut sw = 0.0f32;
        let (_, _, min_y, max_y) = {
            let mut min_y = 1.0f32;
            let mut max_y = 0.0f32;
            for p in inner {
                min_y = min_y.min(p.y);
                max_y = max_y.max(p.y);
            }
            (0.0, 0.0, min_y, max_y)
        };
        let span = (max_y - min_y).max(0.001);
        for p in inner {
            let t = ((p.y - min_y) / span).clamp(0.0, 1.0);
            let w = 0.35 + t * 0.65;
            sy += p.y * w;
            sw += w;
        }
        if sw > 0.0 {
            let sx: f32 = inner.iter().map(|p| p.x).sum::<f32>() / n as f32;
            return (sx, sy / sw);
        }
        return lip_center_from_landmarks(inner);
    }
    let (os, on) = regions.outer_lips;
    if on > 0 && os + on <= landmarks.len() {
        return lip_center_from_landmarks(&landmarks[os..os + on]);
    }
    (0.5, 0.65)
}

/// At slider 100%, soften tone this much (color blotches) — not full blur replacement.
const MAX_TONE_SMOOTH: f32 = 0.40;

/// Reduce fine skin texture (pores) while keeping edges and features sharp.
const MAX_DETAIL_REDUCTION: f32 = 0.45;

const FINE_RADIUS: i32 = 1;
const COARSE_RADIUS_MAX: i32 = 4;

/// Masked skin smooth via frequency separation: smooth tone, preserve detail.
pub fn apply_skin_smooth_rgba(
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
    let w = buffer.width as usize;
    let h = buffer.height as usize;
    let coarse_r = (1.0 + strength * (COARSE_RADIUS_MAX as f32 - 1.0)).round() as i32;

    let fine_blur = box_blur_separable(&buffer.pixels, w, h, FINE_RADIUS);
    let coarse_blur = box_blur_separable(&buffer.pixels, w, h, coarse_r);
    let mut out = buffer.pixels.clone();

    for y in 0..h {
        for x in 0..w {
            let mi = y * w + x;
            let m = mask.pixels[mi] as f32 / 255.0;
            if m < 0.02 {
                continue;
            }
            let s = m * strength;
            let tone = (s * MAX_TONE_SMOOTH).min(MAX_TONE_SMOOTH);
            let detail_keep = 1.0 - (s * MAX_DETAIL_REDUCTION).min(MAX_DETAIL_REDUCTION);

            let idx = mi * 4;
            for c in 0..3 {
                let orig = buffer.pixels[idx + c] as f32;
                let fine = fine_blur[idx + c] as f32;
                let coarse = coarse_blur[idx + c] as f32;
                let detail = orig - fine;
                let smooth_tone = orig * (1.0 - tone) + coarse * tone;
                let v = (smooth_tone + detail * detail_keep).clamp(0.0, 255.0);
                out[idx + c] = v as u8;
            }
        }
    }

    RgbaImageBuffer {
        width: buffer.width,
        height: buffer.height,
        pixels: out,
    }
}

/// Full still-photo beauty pipeline (Nexus B): plump → skin → eyes → lips → blush.
pub fn apply_beauty_rgba(
    buffer: &RgbaImageBuffer,
    analysis: &FaceAnalysisResult,
    skin_mask: &SegmentationMask,
    params: &BeautyParams,
    exclude_mask: Option<&SegmentationMask>,
) -> RgbaImageBuffer {
    if !params.is_active() {
        return buffer.clone();
    }
    let w = buffer.width;
    let h = buffer.height;

    let mut out = buffer.clone();

    if params.lip_plump > 0.001 {
        let lip_mask = apply_exclude_mask(&build_lip_mask(analysis, w, h), exclude_mask);
        let center = LandmarkRegions::from_analysis(analysis)
            .map(|r| lip_center_from_analysis(&analysis.landmarks, r))
            .unwrap_or((0.5, 0.65));
        out = apply_lip_plump_rgba(&out, &lip_mask, center, params.lip_plump);
    }

    if params.skin_smooth > 0.001 {
        let skin = apply_exclude_mask(skin_mask, exclude_mask);
        out = apply_skin_smooth_rgba(&out, &skin, params.skin_smooth);
    }

    if params.eye_brighten > 0.001 {
        let eye_mask = apply_exclude_mask(&build_eye_mask(analysis, w, h), exclude_mask);
        out = apply_eye_brighten_rgba(&out, &eye_mask, params.eye_brighten);
    }

    if params.lip_tint_strength > 0.001 {
        let lip_mask = apply_exclude_mask(&build_lip_mask(analysis, w, h), exclude_mask);
        out = apply_lip_tint_rgba(
            &out,
            &lip_mask,
            params.lip_tint,
            params.lip_tint_strength,
        );
    }

    if params.blush > 0.001 {
        let blush_mask = apply_exclude_mask(&build_blush_mask(analysis, w, h), exclude_mask);
        out = apply_blush_rgba(&out, &blush_mask, params.blush);
    }

    if params.under_eye > 0.001 {
        let ue_mask =
            apply_exclude_mask(&build_under_eye_mask(analysis, w, h), exclude_mask);
        out = apply_under_eye_soften_rgba(&out, &ue_mask, params.under_eye);
    }

    if params.teeth_whiten > 0.001 {
        let teeth_mask = apply_exclude_mask(&build_teeth_mask(analysis, w, h), exclude_mask);
        out = apply_teeth_whiten_rgba(&out, &teeth_mask, params.teeth_whiten);
    }

    out
}

/// Separable box blur on RGB channels (alpha unchanged from source).
pub(crate) fn box_blur_separable(pixels: &[u8], w: usize, h: usize, radius: i32) -> Vec<u8> {
    if radius <= 0 {
        return pixels.to_vec();
    }
    let r = radius as usize;
    let mut tmp = vec![0u8; pixels.len()];
    let mut out = vec![0u8; pixels.len()];

    for y in 0..h {
        for x in 0..w {
            let x0 = x.saturating_sub(r);
            let x1 = (x + r).min(w - 1);
            let mut rs = 0u32;
            let mut gs = 0u32;
            let mut bs = 0u32;
            let mut n = 0u32;
            for xx in x0..=x1 {
                let idx = (y * w + xx) * 4;
                rs += pixels[idx] as u32;
                gs += pixels[idx + 1] as u32;
                bs += pixels[idx + 2] as u32;
                n += 1;
            }
            let o = (y * w + x) * 4;
            tmp[o] = (rs / n) as u8;
            tmp[o + 1] = (gs / n) as u8;
            tmp[o + 2] = (bs / n) as u8;
            tmp[o + 3] = pixels[o + 3];
        }
    }

    for y in 0..h {
        for x in 0..w {
            let y0 = y.saturating_sub(r);
            let y1 = (y + r).min(h - 1);
            let mut rs = 0u32;
            let mut gs = 0u32;
            let mut bs = 0u32;
            let mut n = 0u32;
            for yy in y0..=y1 {
                let idx = (yy * w + x) * 4;
                rs += tmp[idx] as u32;
                gs += tmp[idx + 1] as u32;
                bs += tmp[idx + 2] as u32;
                n += 1;
            }
            let o = (y * w + x) * 4;
            out[o] = (rs / n) as u8;
            out[o + 1] = (gs / n) as u8;
            out[o + 2] = (bs / n) as u8;
            out[o + 3] = tmp[o + 3];
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::face::SegmentationMask;

    #[test]
    fn skin_smooth_changes_masked_pixels() {
        let mut pixels = vec![200u8; 4 * 4 * 4];
        pixels[0] = 50;
        let buffer = RgbaImageBuffer {
            width: 4,
            height: 4,
            pixels,
        };
        let mask = SegmentationMask {
            width: 4,
            height: 4,
            pixels: vec![255, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        };
        let out = apply_skin_smooth_rgba(&buffer, &mask, 1.0);
        assert_ne!(out.pixels[0], buffer.pixels[0]);
        assert_eq!(out.pixels[4 * 4 - 4], buffer.pixels[4 * 4 - 4]);
    }

    #[test]
    fn full_slider_preserves_more_detail_than_flat_blur() {
        let mut pixels = vec![0u8; 5 * 5 * 4];
        for y in 0..5 {
            for x in 0..5 {
                let o = (y * 5 + x) * 4;
                // Checkerboard fine detail
                pixels[o] = if (x + y) % 2 == 0 { 180 } else { 120 };
                pixels[o + 1] = 100;
                pixels[o + 2] = 90;
                pixels[o + 3] = 255;
            }
        }
        let buffer = RgbaImageBuffer {
            width: 5,
            height: 5,
            pixels,
        };
        let mask = SegmentationMask {
            width: 5,
            height: 5,
            pixels: vec![255; 25],
        };
        let out = apply_skin_smooth_rgba(&buffer, &mask, 1.0);
        let center = 2 * 5 + 2;
        let orig = buffer.pixels[center * 4];
        let smoothed = out.pixels[center * 4];
        // Should not collapse checkerboard to flat average (120–180 mid ~150).
        assert!((smoothed as i32 - orig as i32).abs() < 40);
        assert!(smoothed == 120 || smoothed == 180 || (smoothed > 115 && smoothed < 185));
    }

    #[test]
    fn zero_strength_is_noop() {
        let buffer = RgbaImageBuffer {
            width: 2,
            height: 2,
            pixels: vec![10, 20, 30, 255, 40, 50, 60, 255, 70, 80, 90, 255, 100, 110, 120, 255],
        };
        let mask = SegmentationMask {
            width: 2,
            height: 2,
            pixels: vec![255; 4],
        };
        let out = apply_skin_smooth_rgba(&buffer, &mask, 0.0);
        assert_eq!(out.pixels, buffer.pixels);
    }
}
