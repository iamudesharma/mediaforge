use super::landmark::LandmarkRegions;
use super::{FaceAnalysisResult, Landmark2D, SegmentationMask};

const FEATHER_PX: i32 = 6;
const ERODE_PX: i32 = 3;
const LIP_ERODE_PX: i32 = 2;
const EYE_ERODE_PX: i32 = 1;

/// Multiply a regional mask by `(255 - exclude) / 255` (beauty eraser).
pub fn apply_exclude_mask(
    mask: &SegmentationMask,
    exclude: Option<&SegmentationMask>,
) -> SegmentationMask {
    let Some(ex) = exclude else {
        return mask.clone();
    };
    if ex.width != mask.width
        || ex.height != mask.height
        || ex.pixels.len() != mask.pixels.len()
    {
        return mask.clone();
    }
    let pixels: Vec<u8> = mask
        .pixels
        .iter()
        .zip(ex.pixels.iter())
        .map(|(&m, &e)| ((m as u16 * (255 - e as u16)) / 255) as u8)
        .collect();
    SegmentationMask {
        width: mask.width,
        height: mask.height,
        pixels,
    }
}

/// Build edit-resolution skin mask: face oval (contour landmarks) ∩ segmenter, minus features.
pub fn build_skin_mask(
    analysis: &FaceAnalysisResult,
    width: u32,
    height: u32,
) -> SegmentationMask {
    let w = width as usize;
    let h = height as usize;
    let mut skin = vec![0u8; w * h];

    if !analysis.landmarks.is_empty() {
        let contour_n = if analysis.face_contour_count > 0 {
            analysis.face_contour_count as usize
        } else {
            // Legacy: estimate Vision face contour (~first 17–22 of ~87).
            analysis.landmarks.len().min(22)
        };
        fill_skin_oval(
            &analysis.landmarks[..contour_n.min(analysis.landmarks.len())],
            width,
            height,
            &mut skin,
        );
    }

    if let Some(seg) = &analysis.segmentation {
        if seg.width == width && seg.height == height && seg.pixels.len() == w * h {
            for i in 0..w * h {
                skin[i] = ((seg.pixels[i] as u16 * skin[i] as u16) / 255) as u8;
            }
        }
    }

    if analysis.landmarks.len() >= 20 {
        exclude_eyes_mouth_nose(analysis, width, height, &mut skin);
    }

    if ERODE_PX > 0 && w >= 32 && h >= 32 {
        erode_mask(&mut skin, w, h, ERODE_PX);
    }
    feather_mask(&mut skin, w, h, FEATHER_PX);

    SegmentationMask {
        width,
        height,
        pixels: skin,
    }
}

/// Soft eye-region mask from left/right eye landmarks.
pub fn build_eye_mask(
    analysis: &FaceAnalysisResult,
    width: u32,
    height: u32,
) -> SegmentationMask {
    let w = width as usize;
    let h = height as usize;
    let mut pixels = vec![0u8; w * h];
    if let Some(regions) = LandmarkRegions::from_analysis(analysis) {
        fill_landmark_ellipse(
            &analysis.landmarks,
            regions.left_eye,
            width,
            height,
            &mut pixels,
            1.12,
        );
        fill_landmark_ellipse(
            &analysis.landmarks,
            regions.right_eye,
            width,
            height,
            &mut pixels,
            1.12,
        );
    } else if analysis.landmarks.len() >= 20 {
        let (min_x, max_x, min_y, max_y) = landmark_bounds(&analysis.landmarks);
        let fw = (max_x - min_x).max(0.05);
        let fh = (max_y - min_y).max(0.05);
        let cx = (min_x + max_x) * 0.5;
        let cy = (min_y + max_y) * 0.5;
        fill_ellipse(
            &mut pixels,
            width,
            height,
            cx - fw * 0.19,
            cy - fh * 0.08,
            fw * 0.14,
            fh * 0.09,
            255,
        );
        fill_ellipse(
            &mut pixels,
            width,
            height,
            cx + fw * 0.19,
            cy - fh * 0.08,
            fw * 0.14,
            fh * 0.09,
            255,
        );
    }
    if EYE_ERODE_PX > 0 && w >= 16 && h >= 16 {
        erode_mask(&mut pixels, w, h, EYE_ERODE_PX);
    }
    feather_mask(&mut pixels, w, h, 3);
    SegmentationMask {
        width,
        height,
        pixels,
    }
}

/// Soft crescents below each eye (Nexus E — separate from iris brighten).
pub fn build_under_eye_mask(
    analysis: &FaceAnalysisResult,
    width: u32,
    height: u32,
) -> SegmentationMask {
    let w = width as usize;
    let h = height as usize;
    let mut pixels = vec![0u8; w * h];
    if let Some(regions) = LandmarkRegions::from_analysis(analysis) {
        fill_under_eye_from_eye_region(
            &analysis.landmarks,
            regions.left_eye,
            width,
            height,
            &mut pixels,
        );
        fill_under_eye_from_eye_region(
            &analysis.landmarks,
            regions.right_eye,
            width,
            height,
            &mut pixels,
        );
    } else if analysis.landmarks.len() >= 20 {
        let (min_x, max_x, min_y, max_y) = face_contour_bounds(analysis);
        let fw = (max_x - min_x).max(0.05);
        let fh = (max_y - min_y).max(0.05);
        let cx = (min_x + max_x) * 0.5;
        let eye_y = min_y + fh * 0.38;
        fill_ellipse(
            &mut pixels,
            width,
            height,
            cx - fw * 0.19,
            eye_y + fh * 0.06,
            fw * 0.15,
            fh * 0.055,
            255,
        );
        fill_ellipse(
            &mut pixels,
            width,
            height,
            cx + fw * 0.19,
            eye_y + fh * 0.06,
            fw * 0.15,
            fh * 0.055,
            255,
        );
    }
    feather_mask(&mut pixels, w, h, 4);
    SegmentationMask {
        width,
        height,
        pixels,
    }
}

fn fill_under_eye_from_eye_region(
    lm: &[Landmark2D],
    (start, count): (usize, usize),
    width: u32,
    height: u32,
    pixels: &mut [u8],
) {
    if count < 2 || start + count > lm.len() {
        return;
    }
    let slice = &lm[start..start + count];
    let (min_x, max_x, min_y, max_y) = landmark_bounds(slice);
    let fw = (max_x - min_x).max(0.02);
    let fh = (max_y - min_y).max(0.015);
    let cx = (min_x + max_x) * 0.5;
    let cy = max_y + fh * 0.55;
    fill_ellipse(
        pixels,
        width,
        height,
        cx,
        cy,
        fw * 1.05,
        fh * 0.95,
        255,
    );
}

/// Lip mask — inner lip polygon primary; trimmed outer ring; clip above cupid's bow.
pub fn build_lip_mask(
    analysis: &FaceAnalysisResult,
    width: u32,
    height: u32,
) -> SegmentationMask {
    let w = width as usize;
    let h = height as usize;
    let mut pixels = vec![0u8; w * h];
    if let Some(regions) = LandmarkRegions::from_analysis(analysis) {
        let lm = &analysis.landmarks;
        let (is, ic) = regions.inner_lips;
        let (os, oc) = regions.outer_lips;

        if ic >= 3 && is + ic <= lm.len() {
            let inner = &lm[is..is + ic];
            fill_landmark_polygon(lm, regions.inner_lips, width, height, &mut pixels);

            let (_, _, inner_min_y, inner_max_y) = landmark_bounds(inner);
            let lip_span = (inner_max_y - inner_min_y).max(0.008);
            // Cupid's bow line — keep tint below upper 30% of inner lip (avoids mustache bleed).
            let cupid_y = inner_min_y + lip_span * 0.28;

            if oc >= 3 && os + oc <= lm.len() {
                let trimmed: Vec<Landmark2D> = lm[os..os + oc]
                    .iter()
                    .filter(|p| p.y >= cupid_y - lip_span * 0.08)
                    .copied()
                    .collect();
                if trimmed.len() >= 3 {
                    fill_landmark_polygon_slice(&trimmed, width, height, &mut pixels);
                }
            }

            clear_above_normalized_y(&mut pixels, width, height, cupid_y - lip_span * 0.05);
        } else if oc >= 3 && os + oc <= lm.len() {
            fill_lip_ellipse_from_landmarks(lm, regions.outer_lips, width, height, &mut pixels, 0.92);
        }
    } else if analysis.landmarks.len() >= 20 {
        let (min_x, max_x, min_y, max_y) = face_contour_bounds(analysis);
        let fw = (max_x - min_x).max(0.05);
        let fh = (max_y - min_y).max(0.05);
        let cx = (min_x + max_x) * 0.5;
        let cy = min_y + fh * 0.68;
        fill_ellipse(
            &mut pixels,
            width,
            height,
            cx,
            cy,
            fw * 0.12,
            fh * 0.06,
            255,
        );
    }
    if LIP_ERODE_PX > 0 && w >= 16 && h >= 16 {
        erode_mask(&mut pixels, w, h, LIP_ERODE_PX);
    }
    feather_mask(&mut pixels, w, h, 2);
    SegmentationMask {
        width,
        height,
        pixels,
    }
}

/// Cheek blush ellipses aligned to face contour (not jaw-heavy full landmark bounds).
pub fn build_blush_mask(
    analysis: &FaceAnalysisResult,
    width: u32,
    height: u32,
) -> SegmentationMask {
    let w = width as usize;
    let h = height as usize;
    let mut pixels = vec![0u8; w * h];
    if analysis.landmarks.is_empty() {
        return SegmentationMask {
            width,
            height,
            pixels,
        };
    }
    let (min_x, max_x, min_y, max_y) = face_contour_bounds(analysis);
    let fw = (max_x - min_x).max(0.05);
    let fh = (max_y - min_y).max(0.05);
    let cx = (min_x + max_x) * 0.5;
    let cy = min_y + fh * 0.50;
    fill_ellipse(
        &mut pixels,
        width,
        height,
        cx - fw * 0.20,
        cy,
        fw * 0.12,
        fh * 0.09,
        255,
    );
    fill_ellipse(
        &mut pixels,
        width,
        height,
        cx + fw * 0.20,
        cy,
        fw * 0.12,
        fh * 0.09,
        255,
    );
    // Keep blush off eyes, nose, and mouth.
    if let Some(regions) = LandmarkRegions::from_analysis(analysis) {
        let lm = &analysis.landmarks;
        for range in [regions.left_eye, regions.right_eye] {
            let (s, c) = range;
            if c > 0 && s + c <= lm.len() {
                let (ex0, ex1, ey0, ey1) = landmark_bounds_tuple(&lm[s..s + c]);
                clear_ellipse(
                    &mut pixels,
                    width,
                    height,
                    (ex0 + ex1) * 0.5,
                    (ey0 + ey1) * 0.5,
                    ((ex1 - ex0) * 0.5 * 1.5).max(0.012),
                    ((ey1 - ey0) * 0.5 * 1.5).max(0.01),
                );
            }
        }
        let (ls, lc) = regions.outer_lips;
        if lc > 0 && ls + lc <= lm.len() {
            let (lx0, lx1, ly0, ly1) = landmark_bounds_tuple(&lm[ls..ls + lc]);
            clear_ellipse(
                &mut pixels,
                width,
                height,
                (lx0 + lx1) * 0.5,
                (ly0 + ly1) * 0.5,
                ((lx1 - lx0) * 0.5 * 1.3).max(0.012),
                ((ly1 - ly0) * 0.5 * 1.3).max(0.01),
            );
        }
    }
    feather_mask(&mut pixels, w, h, 8);
    SegmentationMask {
        width,
        height,
        pixels,
    }
}

/// Face oval bounds from contour landmarks only.
fn face_contour_bounds(analysis: &FaceAnalysisResult) -> (f32, f32, f32, f32) {
    let contour = if analysis.face_contour_count > 0 {
        analysis.face_contour_count as usize
    } else {
        analysis.landmarks.len().min(22)
    };
    let slice = &analysis.landmarks[..contour.min(analysis.landmarks.len())];
    if slice.len() >= 3 {
        landmark_bounds(slice)
    } else {
        landmark_bounds(&analysis.landmarks)
    }
}

fn fill_landmark_ellipse(
    landmarks: &[Landmark2D],
    range: (usize, usize),
    width: u32,
    height: u32,
    mask: &mut [u8],
    pad: f32,
) {
    let (start, count) = range;
    if count == 0 || start + count > landmarks.len() {
        return;
    }
    let slice = &landmarks[start..start + count];
    let (min_x, max_x, min_y, max_y) = landmark_bounds(slice);
    let cx = (min_x + max_x) * 0.5;
    let cy = (min_y + max_y) * 0.5;
    let rx = ((max_x - min_x) * 0.5 * pad).max(0.01);
    let ry = ((max_y - min_y) * 0.5 * pad).max(0.01);
    fill_ellipse(mask, width, height, cx, cy, rx, ry, 255);
}

fn fill_lip_ellipse_from_landmarks(
    landmarks: &[Landmark2D],
    range: (usize, usize),
    width: u32,
    height: u32,
    mask: &mut [u8],
    pad: f32,
) {
    let (start, count) = range;
    if count == 0 || start + count > landmarks.len() {
        return;
    }
    let slice = &landmarks[start..start + count];
    let (min_x, max_x, min_y, max_y) = landmark_bounds(slice);
    let cx = (min_x + max_x) * 0.5;
    let cy = (min_y + max_y) * 0.5;
    let rx = ((max_x - min_x) * 0.5 * pad).max(0.012);
    let ry = ((max_y - min_y) * 0.5 * pad).max(0.008);
    fill_ellipse(mask, width, height, cx, cy, rx, ry, 255);
}

fn fill_landmark_polygon(
    landmarks: &[Landmark2D],
    range: (usize, usize),
    width: u32,
    height: u32,
    mask: &mut [u8],
) {
    let (start, count) = range;
    if count < 3 || start + count > landmarks.len() {
        return;
    }
    fill_landmark_polygon_slice(&landmarks[start..start + count], width, height, mask);
}

fn fill_landmark_polygon_slice(
    landmarks: &[Landmark2D],
    width: u32,
    height: u32,
    mask: &mut [u8],
) {
    if landmarks.len() < 3 {
        return;
    }
    let w = width as i32;
    let h = height as i32;
    let pts: Vec<(i32, i32)> = landmarks
        .iter()
        .map(|p| {
            (
                (p.x * width as f32).round() as i32,
                (p.y * height as f32).round() as i32,
            )
        })
        .collect();
    let (min_y, max_y) = pts.iter().map(|p| p.1).fold((h, 0), |(a, b), y| (a.min(y), b.max(y)));
    for y in min_y.max(0)..=max_y.min(h - 1) {
        let mut xs = Vec::new();
        for i in 0..pts.len() {
            let (x0, y0) = pts[i];
            let (x1, y1) = pts[(i + 1) % pts.len()];
            if (y0 <= y && y1 > y) || (y1 <= y && y0 > y) {
                let t = (y - y0) as f32 / (y1 - y0) as f32;
                xs.push((x0 as f32 + t * (x1 - x0) as f32).round() as i32);
            }
        }
        xs.sort_unstable();
        let mut i = 0;
        while i + 1 < xs.len() {
            let x0 = xs[i].max(0);
            let x1 = xs[i + 1].min(w - 1);
            for x in x0..=x1 {
                mask[y as usize * width as usize + x as usize] = 255;
            }
            i += 2;
        }
    }
}

/// Zero mask pixels above a normalized y (top-left origin).
fn clear_above_normalized_y(pixels: &mut [u8], width: u32, height: u32, y_cut: f32) {
    let y_px = (y_cut * height as f32).round() as i32;
    if y_px <= 0 {
        return;
    }
    let w = width as usize;
    let rows = (y_px as usize).min(height as usize);
    for y in 0..rows {
        let row = y * w;
        for x in 0..w {
            pixels[row + x] = 0;
        }
    }
}

/// Cheek/forehead oval from face-contour bounds (not convex hull of all landmarks).
fn fill_skin_oval(landmarks: &[Landmark2D], width: u32, height: u32, mask: &mut [u8]) {
    if landmarks.len() < 3 {
        return;
    }
    let (min_x, max_x, min_y, max_y) = landmark_bounds(landmarks);
    let fw = (max_x - min_x).max(0.08);
    let fh = (max_y - min_y).max(0.08);
    let cx = (min_x + max_x) * 0.5;
    // Bias oval upward slightly — cheeks + forehead, less jaw/chin.
    let cy = min_y + fh * 0.46;
    fill_ellipse(
        mask,
        width,
        height,
        cx,
        cy,
        fw * 0.34,
        fh * 0.36,
        255,
    );
}

fn fill_ellipse(
    mask: &mut [u8],
    width: u32,
    height: u32,
    cx: f32,
    cy: f32,
    rx: f32,
    ry: f32,
    value: u8,
) {
    if rx <= 0.0 || ry <= 0.0 {
        return;
    }
    let w = width as i32;
    let h = height as i32;
    let icx = (cx * width as f32) as i32;
    let icy = (cy * height as f32) as i32;
    let irx = (rx * width as f32).max(2.0) as i32;
    let iry = (ry * height as f32).max(2.0) as i32;
    let rx2 = (irx * irx) as f32;
    let ry2 = (iry * iry) as f32;
    let y0 = (icy - iry).clamp(0, h - 1);
    let y1 = (icy + iry).clamp(0, h - 1);
    let x0 = (icx - irx).clamp(0, w - 1);
    let x1 = (icx + irx).clamp(0, w - 1);
    for y in y0..=y1 {
        for x in x0..=x1 {
            let dx = (x - icx) as f32;
            let dy = (y - icy) as f32;
            if (dx * dx) / rx2 + (dy * dy) / ry2 <= 1.0 {
                mask[y as usize * width as usize + x as usize] = value;
            }
        }
    }
}

fn exclude_eyes_mouth_nose(
    analysis: &FaceAnalysisResult,
    width: u32,
    height: u32,
    mask: &mut [u8],
) {
    let (min_x, max_x, min_y, max_y) = face_contour_bounds(analysis);
    let fw = (max_x - min_x).max(0.05);
    let fh = (max_y - min_y).max(0.05);
    let cx = (min_x + max_x) * 0.5;

    if let Some(regions) = LandmarkRegions::from_analysis(analysis) {
        let lm = &analysis.landmarks;
        for range in [regions.left_eye, regions.right_eye] {
            let (s, c) = range;
            if c > 0 && s + c <= lm.len() {
                let (ex0, ex1, ey0, ey1) = landmark_bounds_tuple(&lm[s..s + c]);
                let ecx = (ex0 + ex1) * 0.5;
                let ecy = (ey0 + ey1) * 0.5;
                let erx = ((ex1 - ex0) * 0.5 * 1.4).max(0.01);
                let ery = ((ey1 - ey0) * 0.5 * 1.4).max(0.01);
                clear_ellipse(mask, width, height, ecx, ecy, erx, ery);
            }
        }
        let (ls, lc) = regions.outer_lips;
        if lc > 0 && ls + lc <= lm.len() {
            let (lx0, lx1, ly0, ly1) = landmark_bounds_tuple(&lm[ls..ls + lc]);
            let lcx = (lx0 + lx1) * 0.5;
            let lcy = (ly0 + ly1) * 0.5;
            clear_ellipse(
                mask,
                width,
                height,
                lcx,
                lcy,
                ((lx1 - lx0) * 0.5 * 1.2).max(0.012),
                ((ly1 - ly0) * 0.5 * 1.2).max(0.008),
            );
        }
        return;
    }

    let cy = min_y + fh * 0.48;
    clear_ellipse(
        mask,
        width,
        height,
        cx - fw * 0.19,
        cy - fh * 0.08,
        fw * 0.13,
        fh * 0.08,
    );
    clear_ellipse(
        mask,
        width,
        height,
        cx + fw * 0.19,
        cy - fh * 0.08,
        fw * 0.13,
        fh * 0.08,
    );
    // Eyebrow band
    clear_ellipse(
        mask,
        width,
        height,
        cx,
        cy - fh * 0.18,
        fw * 0.28,
        fh * 0.06,
    );
    // Nose bridge + tip
    clear_ellipse(
        mask,
        width,
        height,
        cx,
        cy + fh * 0.02,
        fw * 0.07,
        fh * 0.16,
    );
    // Mouth
    clear_ellipse(
        mask,
        width,
        height,
        cx,
        cy + fh * 0.20,
        fw * 0.15,
        fh * 0.09,
    );
}

fn landmark_bounds(landmarks: &[Landmark2D]) -> (f32, f32, f32, f32) {
    let (min_x, max_x, min_y, max_y) = landmark_bounds_tuple(landmarks);
    (min_x, max_x, min_y, max_y)
}

fn landmark_bounds_tuple(landmarks: &[Landmark2D]) -> (f32, f32, f32, f32) {
    let mut min_x = 1.0f32;
    let mut max_x = 0.0f32;
    let mut min_y = 1.0f32;
    let mut max_y = 0.0f32;
    for p in landmarks {
        min_x = min_x.min(p.x);
        max_x = max_x.max(p.x);
        min_y = min_y.min(p.y);
        max_y = max_y.max(p.y);
    }
    (min_x, max_x, min_y, max_y)
}

fn clear_ellipse(
    mask: &mut [u8],
    width: u32,
    height: u32,
    cx: f32,
    cy: f32,
    rx: f32,
    ry: f32,
) {
    fill_ellipse(mask, width, height, cx, cy, rx, ry, 0);
}

fn erode_mask(pixels: &mut [u8], width: usize, height: usize, radius: i32) {
    if radius <= 0 {
        return;
    }
    let r = radius as usize;
    let src = pixels.to_vec();
    for y in 0..height {
        for x in 0..width {
            let mut min_v = 255u8;
            for dy in 0..=r {
                let yy = y.saturating_sub(dy);
                let yy2 = (y + dy).min(height - 1);
                for xx in x.saturating_sub(dy)..=(x + dy).min(width - 1) {
                    min_v = min_v.min(src[yy * width + xx]);
                    if yy != yy2 {
                        min_v = min_v.min(src[yy2 * width + xx]);
                    }
                }
            }
            pixels[y * width + x] = min_v;
        }
    }
}

fn feather_mask(pixels: &mut [u8], width: usize, height: usize, radius: i32) {
    if radius <= 0 {
        return;
    }
    let r = radius as usize;
    let tmp = pixels.to_vec();
    for y in 0..height {
        for x in 0..width {
            let mut sum = 0u32;
            let mut count = 0u32;
            for dy in 0..=r {
                let yy = y.saturating_sub(dy);
                let yy2 = (y + dy).min(height - 1);
                for xx in x.saturating_sub(dy)..=(x + dy).min(width - 1) {
                    sum += tmp[yy * width + xx] as u32;
                    count += 1;
                    if yy != yy2 {
                        sum += tmp[yy2 * width + xx] as u32;
                        count += 1;
                    }
                }
            }
            pixels[y * width + x] = (sum / count.max(1)) as u8;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::face::Landmark2D;

    #[test]
    fn build_mask_dimensions() {
        let analysis = FaceAnalysisResult {
            landmarks: vec![
                Landmark2D { x: 0.2, y: 0.2, z: 0.0 },
                Landmark2D { x: 0.8, y: 0.2, z: 0.0 },
                Landmark2D { x: 0.5, y: 0.8, z: 0.0 },
            ],
            confidence: 1.0,
            segmentation: Some(SegmentationMask {
                width: 4,
                height: 4,
                pixels: vec![255; 16],
            }),
            face_contour_count: 3,
            region_counts: vec![],
        };
        let m = build_skin_mask(&analysis, 4, 4);
        assert_eq!(m.width, 4);
        assert!(m.pixels.iter().any(|&p| p > 0));
    }

    #[test]
    fn feature_exclusion_zeros_eye_region() {
        let mut landmarks = Vec::new();
        for i in 0..30 {
            landmarks.push(Landmark2D {
                x: 0.2 + (i as f32 * 0.02),
                y: 0.25 + (i as f32 * 0.015),
                z: 0.0,
            });
        }
        let analysis = FaceAnalysisResult {
            landmarks,
            confidence: 1.0,
            segmentation: None,
            face_contour_count: 10,
            region_counts: vec![],
        };
        let m = build_skin_mask(&analysis, 64, 64);
        let (min_x, max_x, min_y, max_y) = landmark_bounds(&analysis.landmarks);
        let cx = ((min_x + max_x) * 0.5 * 64.0) as usize;
        let cy = ((min_y + max_y) * 0.5 * 64.0) as usize;
        let eye_idx = cy * 64 + cx;
        assert!(m.pixels[eye_idx] < 128);
    }
}
