//! Sprint 12 — face mesh + segmentation (types in `api::face`).

pub use crate::api::face::{FaceAnalysisResult, Landmark2D, SegmentationMask};

mod beauty;
pub mod landmark;
mod looks;
mod makeup;
mod regions;
mod smoothing;
mod warp;

pub use beauty::{apply_beauty_rgba, apply_skin_smooth_rgba};
pub use landmark::{LandmarkRegions, MEDIAPIPE_LANDMARK_COUNT, VISION_MIN_LANDMARKS};
pub use looks::{params_for_look, recipe_for, BeautyRecipe};
pub use regions::{
    apply_exclude_mask, build_blush_mask, build_eye_mask, build_lip_mask, build_skin_mask,
    build_under_eye_mask,
};
pub use smoothing::TemporalSmoother;

impl FaceAnalysisResult {
    /// Valid for beauty pipeline (Vision fallback or full MediaPipe mesh).
    pub fn is_valid(&self) -> bool {
        self.confidence > 0.5
            && self.landmarks.len() >= VISION_MIN_LANDMARKS
            && self.segmentation.is_some()
    }

    pub fn is_mediapipe_complete(&self) -> bool {
        self.landmarks.len() >= MEDIAPIPE_LANDMARK_COUNT
    }
}
