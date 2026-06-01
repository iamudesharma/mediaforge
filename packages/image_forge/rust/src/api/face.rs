use crate::api::image::RgbaImageBuffer;

use crate::face::{
    apply_beauty_rgba, apply_skin_smooth_rgba, build_blush_mask, build_eye_mask, build_lip_mask,
    build_skin_mask, build_under_eye_mask, params_for_look, VISION_MIN_LANDMARKS,
};

/// Normalized 2D landmark (0–1 in image space).
#[derive(Debug, Clone, Copy, Default)]
pub struct Landmark2D {
    /// Horizontal position normalized from 0.0 (left) to 1.0 (right).
    pub x: f32,
    /// Vertical position normalized from 0.0 (top) to 1.0 (bottom).
    pub y: f32,
    /// Depth position (Z coordinate), often 0.0 or estimated from MediaPipe.
    pub z: f32,
}

/// Selfie / face segmentation mask at edit resolution (row-major R8).
#[derive(Debug, Clone)]
pub struct SegmentationMask {
    /// Width of the mask in pixels.
    pub width: u32,
    /// Height of the mask in pixels.
    pub height: u32,
    /// Grayscale pixel values (0–255), representing feathering/opacity.
    pub pixels: Vec<u8>,
}

/// Lip color swatch for regional tint.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum LipTintPreset {
    #[default]
    None,
    Nude,
    Rose,
    Berry,
    Coral,
    Red,
}

/// One-tap beauty look preset (Nexus C).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum BeautyLookPreset {
    Natural,
    Soft,
    Glow,
    Glam,
    Clear,
    Peach,
    Bold,
}

/// Regional beauty parameters (Nexus B) — stored in edit graph.
#[derive(Debug, Clone, Copy, Default)]
pub struct BeautyParams {
    /// 0–1 skin smooth on cheeks/forehead.
    pub skin_smooth: f32,
    /// 0–1 eye luminance lift.
    pub eye_brighten: f32,
    /// Selected lip tint preset.
    pub lip_tint: LipTintPreset,
    /// 0–1 lip tint strength (when lip_tint != None).
    pub lip_tint_strength: f32,
    /// 0–1 lip plump (radial warp).
    pub lip_plump: f32,
    /// 0–1 cheek blush.
    pub blush: f32,
    /// 0–1 under-eye softening (Nexus E).
    pub under_eye: f32,
    /// 0–1 teeth whitening (Nexus E).
    pub teeth_whiten: f32,
    /// 0–1 high-pass skin texture preserve (Glass Skin / Clean Beauty).
    pub skin_preserve_detail: f32,
    /// 0–1 eye enlarge warp.
    pub eye_enlarge: f32,
    /// 0–1 jaw slim warp.
    pub jaw_slim: f32,
    /// 0–1 nose slim warp.
    pub nose_slim: f32,
    /// 0–1 overall face slim.
    pub face_slim: f32,
    /// 0–1 chin V-shape warp.
    pub chin_vshape: f32,
}

impl BeautyParams {
    /// Checks if any beauty parameters are active.
    pub fn is_active(&self) -> bool {
        self.skin_smooth > 0.001
            || self.eye_brighten > 0.001
            || (self.lip_tint != LipTintPreset::None && self.lip_tint_strength > 0.001)
            || self.lip_plump > 0.001
            || self.blush > 0.001
            || self.under_eye > 0.001
            || self.teeth_whiten > 0.001
            || self.eye_enlarge > 0.001
            || self.jaw_slim > 0.001
            || self.nose_slim > 0.001
            || self.face_slim > 0.001
            || self.chin_vshape > 0.001
    }
}

/// Output of native face pipeline (Vision or MediaPipe).
#[derive(Debug, Clone, Default)]
pub struct FaceAnalysisResult {
    /// List of 2D landmark coordinates.
    pub landmarks: Vec<Landmark2D>,
    /// Confidence score (0.0 to 1.0).
    pub confidence: f32,
    /// Optional face/selfie segmentation mask.
    pub segmentation: Option<SegmentationMask>,
    /// Count of leading landmarks that belong to the face contour (Vision); 0 = legacy estimate.
    pub face_contour_count: u32,
    /// Point counts per region after contour (Vision order); empty = built-in fallback.
    pub region_counts: Vec<u32>,
}

/// Build feathered skin mask at edit resolution from native analysis.
#[flutter_rust_bridge::frb(sync)]
pub fn build_skin_mask_from_analysis(
    analysis: FaceAnalysisResult,
    width: u32,
    height: u32,
) -> SegmentationMask {
    build_skin_mask(&analysis, width, height)
}

/// Flattened mask build — avoids serializing full [FaceAnalysisResult] over FFI.
#[flutter_rust_bridge::frb(sync)]
pub fn build_skin_mask_from_landmarks(
    landmarks: Vec<Landmark2D>,
    face_contour_count: u32,
    region_counts: Vec<u32>,
    segmentation: Option<SegmentationMask>,
    width: u32,
    height: u32,
) -> SegmentationMask {
    let analysis = FaceAnalysisResult {
        landmarks,
        confidence: 1.0,
        segmentation,
        face_contour_count,
        region_counts,
    };
    build_skin_mask(&analysis, width, height)
}

/// Builds an eye regional mask from face landmarks.
#[flutter_rust_bridge::frb(sync)]
pub fn build_eye_mask_from_landmarks(
    landmarks: Vec<Landmark2D>,
    face_contour_count: u32,
    region_counts: Vec<u32>,
    width: u32,
    height: u32,
) -> SegmentationMask {
    let analysis = FaceAnalysisResult {
        landmarks,
        confidence: 1.0,
        segmentation: None,
        face_contour_count,
        region_counts,
    };
    build_eye_mask(&analysis, width, height)
}

/// Builds a lip regional mask from face landmarks.
#[flutter_rust_bridge::frb(sync)]
pub fn build_lip_mask_from_landmarks(
    landmarks: Vec<Landmark2D>,
    face_contour_count: u32,
    region_counts: Vec<u32>,
    width: u32,
    height: u32,
) -> SegmentationMask {
    let analysis = FaceAnalysisResult {
        landmarks,
        confidence: 1.0,
        segmentation: None,
        face_contour_count,
        region_counts,
    };
    build_lip_mask(&analysis, width, height)
}

/// Builds a cheek blush regional mask from face landmarks.
#[flutter_rust_bridge::frb(sync)]
pub fn build_blush_mask_from_landmarks(
    landmarks: Vec<Landmark2D>,
    face_contour_count: u32,
    region_counts: Vec<u32>,
    width: u32,
    height: u32,
) -> SegmentationMask {
    let analysis = FaceAnalysisResult {
        landmarks,
        confidence: 1.0,
        segmentation: None,
        face_contour_count,
        region_counts,
    };
    build_blush_mask(&analysis, width, height)
}

/// Builds an under-eye regional mask from face landmarks.
#[flutter_rust_bridge::frb(sync)]
pub fn build_under_eye_mask_from_landmarks(
    landmarks: Vec<Landmark2D>,
    face_contour_count: u32,
    region_counts: Vec<u32>,
    width: u32,
    height: u32,
) -> SegmentationMask {
    let analysis = FaceAnalysisResult {
        landmarks,
        confidence: 1.0,
        segmentation: None,
        face_contour_count,
        region_counts,
    };
    build_under_eye_mask(&analysis, width, height)
}

/// Returns true if the FaceAnalysisResult is valid (sufficient confidence and landmark count).
#[flutter_rust_bridge::frb(sync)]
pub fn face_analysis_is_valid(analysis: FaceAnalysisResult) -> bool {
    analysis.confidence > 0.5
        && analysis.landmarks.len() >= VISION_MIN_LANDMARKS as usize
        && analysis.segmentation.is_some()
}

/// Returns the minimum number of landmarks required by the vision tracker.
#[flutter_rust_bridge::frb(sync)]
pub fn vision_min_landmark_count() -> u32 {
    VISION_MIN_LANDMARKS as u32
}

/// CPU skin smooth for export / non-GPU preview.
#[flutter_rust_bridge::frb(sync)]
pub fn apply_skin_smooth_cpu(
    buffer: RgbaImageBuffer,
    mask: SegmentationMask,
    strength: f32,
) -> RgbaImageBuffer {
    apply_skin_smooth_rgba(&buffer, &mask, strength, 0.0)
}

/// Full regional beauty on still photo (Nexus B).
#[flutter_rust_bridge::frb(sync)]
pub fn apply_beauty_cpu(
    buffer: RgbaImageBuffer,
    landmarks: Vec<Landmark2D>,
    face_contour_count: u32,
    region_counts: Vec<u32>,
    skin_mask: SegmentationMask,
    params: BeautyParams,
    exclude_mask: Option<SegmentationMask>,
) -> RgbaImageBuffer {
    let analysis = FaceAnalysisResult {
        landmarks,
        confidence: 1.0,
        segmentation: None,
        face_contour_count,
        region_counts,
    };
    apply_beauty_rgba(
        &buffer,
        &analysis,
        &skin_mask,
        &params,
        exclude_mask.as_ref(),
    )
}

/// Params for a one-tap beauty look (Nexus C).
#[flutter_rust_bridge::frb(sync)]
pub fn beauty_params_for_look(preset: BeautyLookPreset) -> BeautyParams {
    params_for_look(preset)
}

/// User-facing name for a beauty look chip.
#[flutter_rust_bridge::frb(sync)]
pub fn beauty_look_display_name(preset: BeautyLookPreset) -> String {
    match preset {
        BeautyLookPreset::Natural => "Natural".into(),
        BeautyLookPreset::Soft => "Soft".into(),
        BeautyLookPreset::Glow => "Glow".into(),
        BeautyLookPreset::Glam => "Glam".into(),
        BeautyLookPreset::Clear => "Clear".into(),
        BeautyLookPreset::Peach => "Peach".into(),
        BeautyLookPreset::Bold => "Bold".into(),
    }
}
