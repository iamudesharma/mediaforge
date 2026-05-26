use std::collections::HashMap;
use std::sync::atomic::{AtomicI64, Ordering};
use std::sync::{Mutex, OnceLock};

use crate::api::face::{BeautyParams, SegmentationMask};
use crate::api::image::{EditOp, ProcessingBackend, RgbaImageBuffer};
use crate::face::{
    apply_beauty_rgba, build_blush_mask, build_eye_mask, build_lip_mask, build_teeth_mask,
    FaceAnalysisResult,
};

use super::engine;

static SURFACES: OnceLock<Mutex<HashMap<i64, GpuEditSurface>>> = OnceLock::new();
static NEXT_SURFACE_ID: AtomicI64 = AtomicI64::new(1);

fn surfaces() -> &'static Mutex<HashMap<i64, GpuEditSurface>> {
    SURFACES.get_or_init(|| Mutex::new(HashMap::new()))
}

pub struct GpuEditSurface {
    pub width: u32,
    pub height: u32,
}

/// Create a GPU-resident preview surface (Sprint 11b.2).
pub fn create_surface(width: u32, height: u32) -> Result<i64, String> {
    if width == 0 || height == 0 {
        return Err("surface dimensions must be > 0".into());
    }
    #[cfg(not(feature = "gpu"))]
    {
        let _ = (width, height);
        return Err("GPU feature disabled".into());
    }
    #[cfg(feature = "gpu")]
    {
        let _ = engine::engine()?;
        let id = NEXT_SURFACE_ID.fetch_add(1, Ordering::Relaxed);
        surfaces()
            .lock()
            .map_err(|_| "surface registry poisoned".to_string())?
            .insert(id, GpuEditSurface { width, height });
        Ok(id)
    }
}

pub fn destroy_surface(id: i64) {
    if let Ok(mut map) = surfaces().lock() {
        map.remove(&id);
    }
}

pub fn upload_surface(id: i64, buffer: RgbaImageBuffer) -> Result<(), String> {
    let surface = surface_for(id)?;
    if buffer.width != surface.width || buffer.height != surface.height {
        return Err(format!(
            "upload size {}×{} does not match surface {}×{}",
            buffer.width, buffer.height, surface.width, surface.height
        ));
    }
    #[cfg(feature = "gpu")]
    {
        let gpu = engine::engine()?;
        gpu.upload_pipeline_cache(buffer)?;
    }
    Ok(())
}

pub fn apply_surface_ops(
    id: i64,
    ops: Vec<EditOp>,
    backend: ProcessingBackend,
) -> Result<(), String> {
    let _surface = surface_for(id)?;
    #[cfg(feature = "gpu")]
    {
        let gpu = engine::engine()?;
        gpu.apply_pipeline_ops(&ops, backend)?;
    }
    #[cfg(not(feature = "gpu"))]
    {
        let _ = (ops, backend);
        return Err("GPU feature disabled".into());
    }
    Ok(())
}

/// Masked skin smooth on cached GPU pixels (Nexus D — GPU WGSL).
pub fn apply_surface_beauty(
    id: i64,
    mask: SegmentationMask,
    strength: f32,
) -> Result<(), String> {
    let _surface = surface_for(id)?;
    #[cfg(feature = "gpu")]
    {
        let gpu = engine::engine()?;
        let params = BeautyParams {
            skin_smooth: strength,
            ..Default::default()
        };
        return gpu.apply_beauty_on_cache(
            gpu.beauty_pipelines(),
            &params,
            &mask,
            None,
            None,
            None,
            None,
            None,
        );
    }
    #[cfg(not(feature = "gpu"))]
    {
        let _ = (id, mask, strength);
        Err("GPU feature disabled".into())
    }
}

/// Full regional beauty on GPU surface (Nexus D). Lip plump falls back to CPU warp after GPU passes.
pub fn apply_surface_beauty_pipeline(
    id: i64,
    analysis: &FaceAnalysisResult,
    skin_mask: &SegmentationMask,
    params: &BeautyParams,
    exclude: Option<&SegmentationMask>,
) -> Result<(), String> {
    let surface = surface_for(id)?;
    #[cfg(feature = "gpu")]
    {
        let gpu = engine::engine()?;
        let w = surface.width;
        let h = surface.height;
        let eye_mask = if params.eye_brighten > 0.001 {
            Some(build_eye_mask(analysis, w, h))
        } else {
            None
        };
        let lip_mask = if params.lip_tint_strength > 0.001 {
            Some(build_lip_mask(analysis, w, h))
        } else {
            None
        };
        let blush_mask = if params.blush > 0.001 {
            Some(build_blush_mask(analysis, w, h))
        } else {
            None
        };
        let teeth_mask = if params.teeth_whiten > 0.001 {
            Some(build_teeth_mask(analysis, w, h))
        } else {
            None
        };

        let mut gpu_params = *params;
        gpu_params.lip_plump = 0.0;
        gpu_params.under_eye = 0.0;

        gpu.apply_beauty_on_cache(
            gpu.beauty_pipelines(),
            &gpu_params,
            skin_mask,
            eye_mask.as_ref(),
            lip_mask.as_ref(),
            blush_mask.as_ref(),
            teeth_mask.as_ref(),
            exclude,
        )?;

        if params.lip_plump > 0.001 || params.under_eye > 0.001 {
            let mut buf = gpu.readback_pipeline_cache(w, h)?;
            let cpu_only = BeautyParams {
                lip_plump: params.lip_plump,
                under_eye: params.under_eye,
                ..Default::default()
            };
            buf = apply_beauty_rgba(&buf, analysis, skin_mask, &cpu_only, exclude);
            gpu.upload_pipeline_cache(buf)?;
        }

        return Ok(());
    }
    #[cfg(not(feature = "gpu"))]
    {
        let _ = (id, analysis, skin_mask, params, exclude);
        Err("GPU feature disabled".into())
    }
}

/// Composite one RGBA overlay layer on the GPU preview cache (Sprint 2 P2).
pub fn apply_surface_overlay(
    id: i64,
    overlay: RgbaImageBuffer,
    opacity: f32,
    blend_mode: u32,
) -> Result<(), String> {
    let _surface = surface_for(id)?;
    #[cfg(feature = "gpu")]
    {
        let gpu = engine::engine()?;
        return super::overlay_pass::composite_overlay_on_cache(gpu, &overlay, opacity, blend_mode);
    }
    #[cfg(not(feature = "gpu"))]
    {
        let _ = (id, overlay, opacity, blend_mode);
        Err("GPU feature disabled".into())
    }
}

pub fn readback_surface(id: i64) -> Result<RgbaImageBuffer, String> {
    let surface = surface_for(id)?;
    #[cfg(feature = "gpu")]
    {
        let gpu = engine::engine()?;
        return gpu.readback_pipeline_cache(surface.width, surface.height);
    }
    #[cfg(not(feature = "gpu"))]
    {
        let _ = surface;
        Err("GPU feature disabled".into())
    }
}

fn surface_for(id: i64) -> Result<GpuEditSurface, String> {
    surfaces()
        .lock()
        .map_err(|_| "surface registry poisoned".to_string())?
        .get(&id)
        .copied()
        .ok_or_else(|| format!("unknown GPU surface {id}"))
}

impl Copy for GpuEditSurface {}

impl Clone for GpuEditSurface {
    fn clone(&self) -> Self {
        *self
    }
}
