use crate::api::face::{BeautyParams, SegmentationMask};
use crate::api::image::{EditOp, ProcessingBackend, RgbaImageBuffer};

#[cfg(feature = "gpu")]
use crate::api::face::FaceAnalysisResult;
#[cfg(feature = "gpu")]
use crate::gpu::{
    apply_surface_beauty, apply_surface_beauty_pipeline, apply_surface_ops, apply_surface_overlay,
    create_surface, destroy_surface, readback_surface, upload_surface,
};
#[cfg(all(feature = "gpu", target_vendor = "apple"))]
use crate::gpu::{
    apply_surface_beauty_pipeline_with_output, attach_output_texture, detach_output_texture,
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

// === Phase 1: zero-copy GPU→Texture display path (Apple Metal only) ===

/// Returns true if the zero-copy beauty path is supported on the current
/// platform (Apple Metal with `Features::BGRA8UNORM_STORAGE`).
#[flutter_rust_bridge::frb(sync)]
pub fn is_zero_copy_beauty_available() -> bool {
    #[cfg(all(feature = "gpu", target_vendor = "apple"))]
    {
        // We require the engine to be up + the feature to be enabled.
        if let Ok(gpu) = crate::gpu::engine() {
            return gpu
                .device
                .features()
                .contains(wgpu::Features::BGRA8UNORM_STORAGE);
        }
        false
    }
    #[cfg(not(all(feature = "gpu", target_vendor = "apple")))]
    {
        false
    }
}

/// Attach a zero-copy output texture backed by a Flutter-side
/// `CVPixelBuffer`'s `MTLTexture`.
///
/// - `id`: the surface handle returned by `create_gpu_preview_surface`.
/// - `mtl_texture_ptr`: the raw Objective-C `MTLTexture*` pointer obtained
///   from the platform plugin's `getMetalTexturePtr` method (a `u64`
///   holding the bit pattern of the pointer).
/// - `pixel_buffer_ptr`: the matching `CVPixelBuffer*` pointer (also `u64`),
///   kept for parity checks / future use.
#[cfg_attr(not(target_vendor = "apple"), allow(unused_variables))]
pub fn attach_zero_copy_output_texture(
    id: i64,
    mtl_texture_ptr: u64,
    pixel_buffer_ptr: u64,
) -> Result<(), String> {
    #[cfg(all(feature = "gpu", target_vendor = "apple"))]
    {
        attach_output_texture(id, mtl_texture_ptr, pixel_buffer_ptr)
    }
    #[cfg(not(all(feature = "gpu", target_vendor = "apple")))]
    {
        let _ = (id, mtl_texture_ptr, pixel_buffer_ptr);
        Err("zero-copy beauty output requires Apple Metal".into())
    }
}

/// Detach the zero-copy output texture (if any). The underlying IOSurface
/// stays valid for the Flutter `Texture` widget; the next beauty dispatch
/// falls back to the CPU-readback path.
pub fn detach_zero_copy_output_texture(id: i64) -> Result<(), String> {
    #[cfg(all(feature = "gpu", target_vendor = "apple"))]
    {
        detach_output_texture(id)
    }
    #[cfg(not(all(feature = "gpu", target_vendor = "apple")))]
    {
        let _ = id;
        Ok(())
    }
}

/// Runs the full GPU beauty pipeline **with zero-copy output** to the
/// attached BGRA8Unorm output texture. Apple only. Falls back to the
/// regular readback path if no output texture is attached.
pub fn apply_gpu_beauty_pipeline_zero_copy(
    id: i64,
    analysis: FaceAnalysisResult,
    skin_mask: SegmentationMask,
    params: BeautyParams,
    exclude_mask: Option<SegmentationMask>,
) -> Result<(), String> {
    #[cfg(all(feature = "gpu", target_vendor = "apple"))]
    {
        apply_surface_beauty_pipeline_with_output(
            id,
            &analysis,
            &skin_mask,
            &params,
            exclude_mask.as_ref(),
        )
    }
    #[cfg(not(all(feature = "gpu", target_vendor = "apple")))]
    {
        let _ = (id, analysis, skin_mask, params, exclude_mask);
        Err("zero-copy beauty pipeline requires Apple Metal".into())
    }
}
