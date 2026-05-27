use crate::api::face::BeautyParams;
use crate::api::image::RgbaImageBuffer;

use super::{FaceAnalysisResult, Landmark2D};

const MAX_EYE_ENLARGE: f32 = 0.12;
const MAX_JAW_SLIM: f32 = 0.10;
const MAX_NOSE_SLIM: f32 = 0.08;
const MAX_FACE_SLIM: f32 = 0.06;
const MAX_CHIN_V: f32 = 0.10;

/// Apply landmark-driven face reshaping before regional beauty.
pub fn apply_face_warp_rgba(
    buffer: RgbaImageBuffer,
    analysis: &FaceAnalysisResult,
    params: &BeautyParams,
) -> RgbaImageBuffer {
    let mut out = buffer;
    if params.eye_enlarge > 0.001 {
        out = warp_eyes(&out, &analysis.landmarks, params.eye_enlarge);
    }
    if params.nose_slim > 0.001 {
        out = warp_nose(&out, &analysis.landmarks, params.nose_slim);
    }
    if params.jaw_slim > 0.001 || params.chin_vshape > 0.001 {
        out = warp_jaw(
            &out,
            &analysis.landmarks,
            analysis.face_contour_count,
            params.jaw_slim,
            params.chin_vshape,
        );
    }
    if params.face_slim > 0.001 {
        out = warp_face_slim(&out, &analysis.landmarks, analysis.face_contour_count, params.face_slim);
    }
    out
}

fn warp_eyes(buffer: &RgbaImageBuffer, landmarks: &[Landmark2D], strength: f32) -> RgbaImageBuffer {
    radial_warp(buffer, landmarks, strength * MAX_EYE_ENLARGE, 0.06, 1.15)
}

fn warp_nose(buffer: &RgbaImageBuffer, landmarks: &[Landmark2D], strength: f32) -> RgbaImageBuffer {
    radial_warp(buffer, landmarks, -strength * MAX_NOSE_SLIM, 0.04, 0.85)
}

fn warp_jaw(
    buffer: &RgbaImageBuffer,
    landmarks: &[Landmark2D],
    contour_count: u32,
    jaw: f32,
    chin: f32,
) -> RgbaImageBuffer {
    let n = contour_count.min(landmarks.len() as u32) as usize;
    if n < 8 {
        return buffer.clone();
    }
    let jaw_pts = &landmarks[..n];
    let (cx, cy) = centroid(jaw_pts);
    let strength = jaw * MAX_JAW_SLIM + chin * MAX_CHIN_V;
    radial_warp_at(buffer, cx, cy, 0.22, -strength, 0.75)
}

fn warp_face_slim(
    buffer: &RgbaImageBuffer,
    landmarks: &[Landmark2D],
    contour_count: u32,
    strength: f32,
) -> RgbaImageBuffer {
    let n = contour_count.min(landmarks.len() as u32) as usize;
    if n < 8 {
        return buffer.clone();
    }
    let (cx, cy) = centroid(&landmarks[..n]);
    radial_warp_at(buffer, cx, cy, 0.35, -strength * MAX_FACE_SLIM, 0.9)
}

fn radial_warp(
    buffer: &RgbaImageBuffer,
    landmarks: &[Landmark2D],
    strength: f32,
    radius_norm: f32,
    falloff: f32,
) -> RgbaImageBuffer {
    if landmarks.is_empty() || strength.abs() <= 0.001 {
        return buffer.clone();
    }
    let (cx, cy) = centroid(landmarks);
    radial_warp_at(buffer, cx, cy, radius_norm, strength, falloff)
}

fn radial_warp_at(
    buffer: &RgbaImageBuffer,
    cx_norm: f32,
    cy_norm: f32,
    radius_norm: f32,
    strength: f32,
    falloff: f32,
) -> RgbaImageBuffer {
    let w = buffer.width as f32;
    let h = buffer.height as f32;
    let cx = cx_norm * w;
    let cy = cy_norm * h;
    let radius = radius_norm * w.min(h);
    let src = &buffer.pixels;
    let mut out = src.clone();

    for y in 0..buffer.height as usize {
        for x in 0..buffer.width as usize {
            let fx = x as f32;
            let fy = y as f32;
            let dx = fx - cx;
            let dy = fy - cy;
            let dist = (dx * dx + dy * dy).sqrt();
            if dist > radius || dist < 1.0 {
                continue;
            }
            let t = 1.0 - dist / radius;
            let push = strength * radius * t.powf(falloff);
            let len = dist.max(1.0);
            let sx = (fx - dx / len * push).clamp(0.0, w - 1.0);
            let sy = (fy - dy / len * push).clamp(0.0, h - 1.0);
            let o = (y * buffer.width as usize + x) * 4;
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

fn centroid(pts: &[Landmark2D]) -> (f32, f32) {
    if pts.is_empty() {
        return (0.5, 0.5);
    }
    let n = pts.len() as f32;
    let sx: f32 = pts.iter().map(|p| p.x).sum();
    let sy: f32 = pts.iter().map(|p| p.y).sum();
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
    let idx = |xi: i32, yi: i32| ((yi * w + xi) * 4) as usize;
    let mut out = [0u8; 4];
    for c in 0..4 {
        let v00 = pixels[idx(x0, y0) + c] as f32;
        let v10 = pixels[idx(x1, y0) + c] as f32;
        let v01 = pixels[idx(x0, y1) + c] as f32;
        let v11 = pixels[idx(x1, y1) + c] as f32;
        let v0 = v00 * (1.0 - tx) + v10 * tx;
        let v1 = v01 * (1.0 - tx) + v11 * tx;
        out[c] = (v0 * (1.0 - ty) + v1 * ty).round().clamp(0.0, 255.0) as u8;
    }
    (out[0], out[1], out[2], out[3])
}
