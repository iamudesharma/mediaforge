use super::{FaceAnalysisResult, Landmark2D, SegmentationMask};

/// Exponential moving average for landmarks and optional segmentation mask.
#[derive(Debug, Clone)]
pub struct TemporalSmoother {
    alpha: f32,
    prev_landmarks: Option<Vec<Landmark2D>>,
    prev_mask: Option<SegmentationMask>,
}

impl TemporalSmoother {
    pub fn new(alpha: f32) -> Self {
        Self {
            alpha: alpha.clamp(0.05, 1.0),
            prev_landmarks: None,
            prev_mask: None,
        }
    }

    pub fn smooth(&mut self, raw: FaceAnalysisResult) -> FaceAnalysisResult {
        let landmarks = match (&self.prev_landmarks, raw.landmarks.is_empty()) {
            (Some(prev), false) if prev.len() == raw.landmarks.len() => {
                let a = self.alpha;
                let b = 1.0 - a;
                prev.iter()
                    .zip(raw.landmarks.iter())
                    .map(|(p, n)| Landmark2D {
                        x: p.x * b + n.x * a,
                        y: p.y * b + n.y * a,
                        z: p.z * b + n.z * a,
                    })
                    .collect()
            }
            _ => raw.landmarks.clone(),
        };

        let segmentation = match (&self.prev_mask, &raw.segmentation) {
            (Some(prev), Some(next)) if prev.width == next.width && prev.height == next.height => {
                let a = self.alpha;
                let b = 1.0 - a;
                let pixels = prev
                    .pixels
                    .iter()
                    .zip(next.pixels.iter())
                    .map(|(p, n)| (*p as f32 * b + *n as f32 * a).round().clamp(0.0, 255.0) as u8)
                    .collect();
                Some(SegmentationMask {
                    width: next.width,
                    height: next.height,
                    pixels,
                })
            }
            _ => raw.segmentation.clone(),
        };

        self.prev_landmarks = Some(landmarks.clone());
        self.prev_mask = segmentation.clone();

        FaceAnalysisResult {
            landmarks,
            confidence: raw.confidence,
            segmentation,
            face_contour_count: raw.face_contour_count,
            region_counts: raw.region_counts.clone(),
        }
    }

    pub fn reset(&mut self) {
        self.prev_landmarks = None;
        self.prev_mask = None;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::face::Landmark2D;

    #[test]
    fn ema_converges_toward_new_sample() {
        let mut s = TemporalSmoother::new(0.5);
        let first = FaceAnalysisResult {
            landmarks: vec![Landmark2D {
                x: 0.0,
                y: 0.0,
                z: 0.0,
            }],
            confidence: 1.0,
            segmentation: None,
            face_contour_count: 0,
            region_counts: vec![],
        };
        let _ = s.smooth(first);
        let second = FaceAnalysisResult {
            landmarks: vec![Landmark2D {
                x: 1.0,
                y: 1.0,
                z: 0.0,
            }],
            confidence: 1.0,
            segmentation: None,
            face_contour_count: 0,
            region_counts: vec![],
        };
        let out = s.smooth(second);
        assert!((out.landmarks[0].x - 0.5).abs() < 0.01);
    }
}
