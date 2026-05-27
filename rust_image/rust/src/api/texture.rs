use crate::api::face::{BeautyParams, SegmentationMask};
use crate::api::image::{EditOp, ProcessingBackend, RgbaImageBuffer};

#[cfg(feature = "gpu")]
use crate::api::face::FaceAnalysisResult;
#[cfg(feature = "gpu")]
use crate::gpu::{
    apply_surface_beauty, apply_surface_beauty_pipeline, apply_surface_ops, apply_surface_overlay,
    create_surface, destroy_surface, readback_surface, upload_surface,
};

/// Create a GPU-resident preview surface handle (Sprint 11b.2).
/// Returns the surface ID.
#[flutter_rust_bridge::frb(sync)]
pub fn create_gpu_preview_surface(width: u32, height: u32) -> Result<i64, String> {
    #[cfg(feature = "gpu")]
    {
        return create_surface(width, height);
    }
    #[cfg(not(feature = "gpu"))]
    {
        let _ = (width, height);
        Err("GPU feature disabled".into())
    }
}

/// Destroys the GPU-resident preview surface and releases its textures/buffers.
#[flutter_rust_bridge::frb(sync)]
pub fn destroy_gpu_preview_surface(id: i64) {
    #[cfg(feature = "gpu")]
    {
        destroy_surface(id);
    }
    #[cfg(not(feature = "gpu"))]
    {
        let _ = id;
    }
}

/// Uploads an RGBA buffer to the GPU texture associated with the surface ID.
pub fn upload_gpu_preview_surface(id: i64, buffer: RgbaImageBuffer) -> Result<(), String> {
    #[cfg(feature = "gpu")]
    {
        return upload_surface(id, buffer);
    }
    #[cfg(not(feature = "gpu"))]
    {
        let _ = (id, buffer);
        Err("GPU feature disabled".into())
    }
}

/// Applies a list of edit operations directly on the GPU texture preview cache.
pub fn apply_gpu_preview_ops(
    id: i64,
    ops: Vec<EditOp>,
    backend: ProcessingBackend,
) -> Result<(), String> {
    #[cfg(feature = "gpu")]
    {
        return apply_surface_ops(id, ops, backend);
    }
    #[cfg(not(feature = "gpu"))]
    {
        let _ = (id, ops, backend);
        Err("GPU feature disabled".into())
    }
}

/// Reads the current GPU preview texture pixels back into a host RGBA buffer.
pub fn readback_gpu_preview_surface(id: i64) -> Result<RgbaImageBuffer, String> {
    #[cfg(feature = "gpu")]
    {
        return readback_surface(id);
    }
    #[cfg(not(feature = "gpu"))]
    {
        let _ = id;
        Err("GPU feature disabled".into())
    }
}

/// Applies a GPU-accelerated regional skin smooth pass (Sprint 12 / Nexus D WGSL).
pub fn apply_gpu_beauty_pass(id: i64, mask: SegmentationMask, strength: f32) -> Result<(), String> {
    #[cfg(feature = "gpu")]
    {
        return apply_surface_beauty(id, mask, strength);
    }
    #[cfg(not(feature = "gpu"))]
    {
        let _ = (id, mask, strength);
        Err("GPU feature disabled".into())
    }
}

/// Runs the full GPU beauty pipeline (skin/eye/lip/blush WGSL; lip plump CPU warp fallback).
pub fn apply_gpu_beauty_pipeline(
    id: i64,
    analysis: FaceAnalysisResult,
    skin_mask: SegmentationMask,
    params: BeautyParams,
    exclude_mask: Option<SegmentationMask>,
) -> Result<(), String> {
    #[cfg(feature = "gpu")]
    {
        return apply_surface_beauty_pipeline(
            id,
            &analysis,
            &skin_mask,
            &params,
            exclude_mask.as_ref(),
        );
    }
    #[cfg(not(feature = "gpu"))]
    {
        let _ = (id, analysis, skin_mask, params, exclude_mask);
        Err("GPU feature disabled".into())
    }
}

/// Composites an overlay RGBA buffer on the GPU texture using the specified blend mode.
pub fn apply_gpu_overlay_blend(
    id: i64,
    overlay: RgbaImageBuffer,
    opacity: f32,
    blend_mode: u32,
) -> Result<(), String> {
    #[cfg(feature = "gpu")]
    {
        return apply_surface_overlay(id, overlay, opacity, blend_mode);
    }
    #[cfg(not(feature = "gpu"))]
    {
        let _ = (id, overlay, opacity, blend_mode);
        Err("GPU feature disabled".into())
    }
}

/// Returns true if GPU texture preview is available on the current host.
#[flutter_rust_bridge::frb(sync)]
pub fn is_gpu_texture_preview_available() -> bool {
    #[cfg(feature = "gpu")]
    {
        return crate::gpu::is_available();
    }
    #[cfg(not(feature = "gpu"))]
    {
        false
    }
}
