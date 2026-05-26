//! MediaPipe-compatible landmark region indices (for future mesh shaders).

use super::FaceAnalysisResult;
use crate::face::Landmark2D;

/// Minimum landmarks from Apple Vision fallback for [FaceAnalysisResult::is_valid].
pub const VISION_MIN_LANDMARKS: usize = 68;

/// Full MediaPipe Face Landmarker mesh count.
pub const MEDIAPIPE_LANDMARK_COUNT: usize = 468;

/// MediaPipe left eye contour indices.
pub const MP_LEFT_EYE_INDICES: &[usize] = &[
    33, 7, 163, 144, 145, 153, 154, 155, 133, 173, 157, 158, 159, 160, 161, 246,
];

/// MediaPipe right eye contour indices.
pub const MP_RIGHT_EYE_INDICES: &[usize] = &[
    362, 382, 381, 380, 374, 373, 390, 249, 263, 466, 388, 387, 386, 385, 384, 398,
];

/// MediaPipe outer lip indices.
pub const MP_OUTER_LIP_INDICES: &[usize] = &[
    61, 146, 91, 181, 84, 17, 314, 405, 321, 375, 291, 409, 270, 269, 267, 0, 37, 39, 40, 185,
];

/// MediaPipe inner lip indices.
pub const MP_INNER_LIP_INDICES: &[usize] = &[
    78, 95, 88, 178, 87, 14, 317, 402, 318, 324, 308, 415, 310, 311, 312, 13, 82, 81, 80, 191,
];

/// Teeth region — lower inner lip + mouth interior (whiten mask).
pub const MP_TEETH_INDICES: &[usize] = &[
    78, 81, 80, 82, 13, 312, 311, 310, 415, 308, 324, 318, 402, 317, 14, 87, 178, 88, 95,
];

/// Indices used to build a soft face oval when segmenter mask is weak (subset of MP mesh).
pub const FACE_OVAL_INDICES: &[usize] = &[
    10, 338, 297, 332, 284, 251, 389, 356, 454, 323, 361, 288, 397, 365, 379, 378, 400, 377, 152,
    148, 176, 149, 150, 136, 172, 58, 132, 93, 234, 127, 162, 21, 54, 103, 67, 109,
];

/// Vision region order after face contour (matches `RustImageFacePlugin` addRegion order).
const VISION_FALLBACK_COUNTS: [usize; 11] = [8, 8, 8, 8, 9, 4, 9, 12, 8, 1, 1];

/// Byte ranges into [FaceAnalysisResult::landmarks] for regional masks.
#[derive(Debug, Clone, Copy)]
pub struct LandmarkRegions {
    pub left_eye: (usize, usize),
    pub right_eye: (usize, usize),
    pub outer_lips: (usize, usize),
    pub inner_lips: (usize, usize),
}

impl LandmarkRegions {
    /// Resolve region slices from native analysis (region_counts or Vision fallback).
    pub fn from_analysis(analysis: &FaceAnalysisResult) -> Option<Self> {
        if analysis.landmarks.len() >= MEDIAPIPE_LANDMARK_COUNT {
            return Self::from_mediapipe_indices(analysis);
        }
        if let Some(regions) = Self::from_region_counts(analysis) {
            if Self::regions_plausible(analysis, &regions) {
                return Some(regions);
            }
        }
        Self::vision_87_fallback(analysis)
    }

    /// MP 468 mesh — regions resolved via fixed index tables (not contiguous slices).
    fn from_mediapipe_indices(analysis: &FaceAnalysisResult) -> Option<Self> {
        let n = analysis.landmarks.len();
        if n < MEDIAPIPE_LANDMARK_COUNT {
            return None;
        }
        // Placeholder contiguous ranges — mask builders use MP index gather when len == 468.
        Some(Self {
            left_eye: (0, MP_LEFT_EYE_INDICES.len()),
            right_eye: (0, MP_RIGHT_EYE_INDICES.len()),
            outer_lips: (0, MP_OUTER_LIP_INDICES.len()),
            inner_lips: (0, MP_INNER_LIP_INDICES.len()),
        })
    }

    pub fn is_mediapipe_mesh(analysis: &FaceAnalysisResult) -> bool {
        analysis.landmarks.len() >= MEDIAPIPE_LANDMARK_COUNT
    }

    /// Gather landmarks by MP index table.
    pub fn gather_mp_indices(lm: &[Landmark2D], indices: &[usize]) -> Vec<Landmark2D> {
        indices
            .iter()
            .filter_map(|&i| lm.get(i).copied())
            .collect()
    }

    fn from_region_counts(analysis: &FaceAnalysisResult) -> Option<Self> {
        let contour = Self::contour_len(analysis);
        if analysis.landmarks.len() <= contour {
            return None;
        }
        let counts: Vec<usize> = Self::feature_region_counts(analysis)?;
        let mut idx = contour;
        let left_eye = (idx, counts[0]);
        idx += counts[0];
        let right_eye = (idx, counts[1]);
        idx += counts[1];
        idx += counts[2] + counts[3] + counts[4] + counts[5] + counts[6];
        if idx + counts[7] + counts[8] > analysis.landmarks.len() {
            return None;
        }
        let outer_lips = (idx, counts[7]);
        idx += counts[7];
        let inner_lips = (idx, counts[8]);
        Some(Self {
            left_eye,
            right_eye,
            outer_lips,
            inner_lips,
        })
    }

    /// Fixed layout when Vision returns the standard ~87-point bundle.
    fn vision_87_fallback(analysis: &FaceAnalysisResult) -> Option<Self> {
        let contour = Self::contour_len(analysis);
        let n = analysis.landmarks.len();
        if n < contour + 40 {
            return None;
        }
        let counts: [usize; 11] = Self::feature_region_counts(analysis)
            .and_then(|v| v.try_into().ok())
            .unwrap_or(VISION_FALLBACK_COUNTS);
        let mut idx = contour;
        let left_eye = (idx, counts[0]);
        idx += counts[0];
        let right_eye = (idx, counts[1]);
        idx += counts[1];
        idx += counts[2] + counts[3] + counts[4] + counts[5] + counts[6];
        if idx + counts[7] + counts[8] > n {
            return None;
        }
        let outer_lips = (idx, counts[7]);
        let inner_lips = (idx + counts[7], counts[8]);
        let regions = Self {
            left_eye,
            right_eye,
            outer_lips,
            inner_lips,
        };
        if Self::regions_plausible(analysis, &regions) {
            Some(regions)
        } else {
            None
        }
    }

    fn feature_region_counts(analysis: &FaceAnalysisResult) -> Option<Vec<usize>> {
        if analysis.region_counts.is_empty() {
            return Some(VISION_FALLBACK_COUNTS.to_vec());
        }
        if analysis.region_counts.len() == 11 {
            return Some(
                analysis
                    .region_counts
                    .iter()
                    .map(|&c| c as usize)
                    .collect(),
            );
        }
        // Legacy: Swift once bundled face contour as regionCounts[0].
        if analysis.region_counts.len() == 12 {
            return Some(
                analysis
                    .region_counts
                    .iter()
                    .skip(1)
                    .map(|&c| c as usize)
                    .collect(),
            );
        }
        None
    }

    fn contour_len(analysis: &FaceAnalysisResult) -> usize {
        if analysis.face_contour_count > 0 {
            analysis.face_contour_count as usize
        } else {
            17
        }
    }

    /// Lips must sit below eyes in image space (top-left origin).
    fn regions_plausible(analysis: &FaceAnalysisResult, regions: &Self) -> bool {
        let lm = &analysis.landmarks;
        let avg_y = |range: (usize, usize)| -> f32 {
            let (s, c) = range;
            if c == 0 || s + c > lm.len() {
                return 0.5;
            }
            lm[s..s + c].iter().map(|p| p.y).sum::<f32>() / c as f32
        };
        let eye_y = (avg_y(regions.left_eye) + avg_y(regions.right_eye)) * 0.5;
        let lip_y = (avg_y(regions.outer_lips) + avg_y(regions.inner_lips)) * 0.5;
        if regions.outer_lips.1 < 3 || regions.inner_lips.1 < 3 {
            return false;
        }
        lip_y > eye_y + 0.03
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::face::Landmark2D;

    fn sample_vision_analysis() -> FaceAnalysisResult {
        let mut landmarks = Vec::new();
        // contour 17
        for i in 0..17 {
            landmarks.push(Landmark2D {
                x: 0.2 + i as f32 * 0.02,
                y: 0.2 + (i as f32 * 0.01),
                z: 0.0,
            });
        }
        // eyes at y~0.42
        for _ in 0..16 {
            landmarks.push(Landmark2D { x: 0.4, y: 0.42, z: 0.0 });
        }
        // brows + nose + median 38 pts
        for _ in 0..38 {
            landmarks.push(Landmark2D { x: 0.5, y: 0.48, z: 0.0 });
        }
        // lips at y~0.62
        for _ in 0..20 {
            landmarks.push(Landmark2D { x: 0.5, y: 0.62, z: 0.0 });
        }
        // pupils
        for _ in 0..2 {
            landmarks.push(Landmark2D { x: 0.5, y: 0.42, z: 0.0 });
        }
        FaceAnalysisResult {
            landmarks,
            confidence: 1.0,
            segmentation: None,
            face_contour_count: 17,
            region_counts: VISION_FALLBACK_COUNTS.iter().map(|&c| c as u32).collect(),
        }
    }

    #[test]
    fn resolves_lips_below_eyes() {
        let analysis = sample_vision_analysis();
        let r = LandmarkRegions::from_analysis(&analysis).expect("regions");
        assert!(r.outer_lips.1 >= 3);
    }

    #[test]
    fn legacy_region_counts_skip_contour_entry() {
        let mut analysis = sample_vision_analysis();
        let contour = analysis.face_contour_count as u32;
        let mut legacy = vec![contour];
        legacy.extend(analysis.region_counts.iter().copied());
        analysis.region_counts = legacy;
        assert_eq!(analysis.region_counts.len(), 12);
        let r = LandmarkRegions::from_analysis(&analysis).expect("regions");
        assert!(r.outer_lips.1 >= 3);
    }
}
