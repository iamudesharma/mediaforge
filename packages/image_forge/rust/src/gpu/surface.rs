use std::collections::HashMap;
use std::sync::atomic::{AtomicI64, Ordering};
use std::sync::{Mutex, OnceLock};
use wgpu::util::DeviceExt;

use super::beauty_pass::pack_mask_r8;
use crate::api::face::{BeautyParams, SegmentationMask};
use crate::api::image::{EditOp, ProcessingBackend, RgbaImageBuffer};
use crate::face::apply_exclude_mask;
use crate::face::warp_mesh::collect_gpu_warp_specs;
use crate::face::{
    beauty::lip_center_norm, build_blush_mask, build_eye_mask, build_lip_mask, build_teeth_mask,
    build_under_eye_mask, FaceAnalysisResult,
};

use super::engine;

static SURFACES: OnceLock<Mutex<HashMap<i64, GpuEditSurface>>> = OnceLock::new();
static NEXT_SURFACE_ID: AtomicI64 = AtomicI64::new(1);

fn surfaces() -> &'static Mutex<HashMap<i64, GpuEditSurface>> {
    SURFACES.get_or_init(|| Mutex::new(HashMap::new()))
}

pub struct CachedMasks {
    pub landmarks: Vec<crate::api::face::Landmark2D>,
    pub width: u32,
    pub height: u32,
    pub exclude_pixels: Option<Vec<u8>>,
    pub skin_mask_buf: wgpu::Buffer,
    pub eye_mask_buf: Option<wgpu::Buffer>,
    pub lip_mask_buf: Option<wgpu::Buffer>,
    pub blush_mask_buf: Option<wgpu::Buffer>,
    pub teeth_mask_buf: Option<wgpu::Buffer>,
    pub under_eye_mask_buf: Option<wgpu::Buffer>,
}

/// Zero-copy output target: a BGRA8Unorm wgpu `Texture` that the beauty
/// compute writes into directly. On Apple, this wraps a `MTLTexture` that
/// itself views the same IOSurface as the Flutter display `CVPixelBuffer`,
/// so the next `textureFrameAvailable` on the Swift side picks up the new
/// pixels. On benchmark or test paths, there is no Flutter `CVPixelBuffer`
/// to adopt — the wgpu texture is a plain storage texture and the variant
/// is [`OutputTexture::Benchmark`].
#[cfg(target_vendor = "apple")]
pub enum OutputTexture {
    /// Adopted Flutter-side zero-copy target. Owns the +1 on the
    /// `CVPixelBuffer` and the +1 on the `MTLTexture` via the
    /// [`pixel_surface::metal_iosurface::BeautyOutputTarget`] wrapper;
    /// the wgpu `Texture` borrows the Metal resource. The wrapper's
    /// `Drop` releases the `CVPixelBuffer` in the right order relative
    /// to the wgpu `Texture` borrow.
    Adopted(pixel_surface::metal_iosurface::BeautyOutputTarget),
    /// Benchmark-only path. The wgpu texture is a pure storage texture
    /// with no Flutter `CVPixelBuffer` backing. There are no Core
    /// Foundation or Objective-C resources to release.
    Benchmark {
        wgpu_texture: wgpu::Texture,
        width: u32,
        height: u32,
    },
}

#[cfg(target_vendor = "apple")]
impl OutputTexture {
    /// Borrow the inner wgpu `Texture` for use as a compute pass output.
    pub fn wgpu_texture(&self) -> &wgpu::Texture {
        match self {
            OutputTexture::Adopted(t) => t.wgpu_texture(),
            OutputTexture::Benchmark { wgpu_texture, .. } => wgpu_texture,
        }
    }
    /// Output texture width in pixels. Exposed for diagnostics; not on
    /// the hot path.
    #[allow(dead_code)]
    pub fn width(&self) -> u32 {
        match self {
            OutputTexture::Adopted(t) => t.width(),
            OutputTexture::Benchmark { width, .. } => *width,
        }
    }
    /// Output texture height in pixels. Exposed for diagnostics; not on
    /// the hot path.
    #[allow(dead_code)]
    pub fn height(&self) -> u32 {
        match self {
            OutputTexture::Adopted(t) => t.height(),
            OutputTexture::Benchmark { height, .. } => *height,
        }
    }
}

pub struct GpuEditSurface {
    pub width: u32,
    pub height: u32,
    pub cached_masks: std::sync::Arc<Mutex<Option<CachedMasks>>>,
    /// Optional zero-copy output texture (Apple only). When present, beauty
    /// compute writes directly into the Flutter display's IOSurface.
    #[cfg(target_vendor = "apple")]
    pub output_texture: std::sync::Arc<Mutex<Option<OutputTexture>>>,
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
            .insert(
                id,
                GpuEditSurface {
                    width,
                    height,
                    cached_masks: std::sync::Arc::new(Mutex::new(None)),
                    #[cfg(target_vendor = "apple")]
                    output_texture: std::sync::Arc::new(Mutex::new(None)),
                },
            );
        Ok(id)
    }
}

pub fn destroy_surface(id: i64) {
    if let Ok(mut map) = surfaces().lock() {
        map.remove(&id);
    }
}

/// Attach a zero-copy output texture backed by a Flutter-side
/// `CVPixelBuffer`'s `MTLTexture`. The `mtl_texture_ptr` is the raw
/// Objective-C `MTLTexture*` obtained from the platform plugin's
/// `getMetalTexturePtr` method; the caller is responsible for keeping the
/// CVPixelBuffer alive on the Dart/Swift side. Rust retains +1 the
/// MTLTexture and releases it when the surface is destroyed.
#[cfg(target_vendor = "apple")]
pub fn attach_output_texture(
    id: i64,
    mtl_texture_ptr: u64,
    pixel_buffer_ptr: u64,
) -> Result<(), String> {
    use pixel_surface::metal_iosurface;

    let surface = surface_for(id)?;
    let gpu = engine::engine()?;

    if mtl_texture_ptr == 0 || pixel_buffer_ptr == 0 {
        return Err("mtl_texture_ptr and pixel_buffer_ptr must be non-zero".into());
    }

    // Adopt both +1 retains into the safe `BeautyOutputTarget` wrapper.
    // The wrapper validates the pointers, takes the +1 on the
    // `CVPixelBuffer`, and produces the wgpu import in a single call.
    // On validation failure, the just-adopted +1s are released by the
    // wrapper's `Drop` and the function returns `None` — no leak.
    //
    // SAFETY: caller guarantees mtl_texture_ptr is a valid +1-retained
    // `MTLTexture*` backed by the same Metal device as `gpu.device`,
    // BGRA8Unorm + 2D + ShaderRead/Write usage. pixel_buffer_ptr is
    // a valid +1-retained `CVPixelBuffer` of the same dimensions.
    let target = unsafe {
        metal_iosurface::BeautyOutputTarget::from_adopted(
            &gpu.device,
            mtl_texture_ptr as *mut metal::MTLTexture,
            pixel_buffer_ptr as metal_iosurface::CVPixelBufferRef,
        )
    };
    let Some(target) = target else {
        return Err("output texture adoption rejected (see logs)".into());
    };
    let width = target.width();
    let height = target.height();
    if width != surface.width || height != surface.height {
        return Err(format!(
            "output texture {width}x{height} does not match surface {}x{}",
            surface.width, surface.height
        ));
    }
    let ot = OutputTexture::Adopted(target);
    *surface
        .output_texture
        .lock()
        .map_err(|_| "output texture lock poisoned".to_string())? = Some(ot);
    log::info!(
        "[ZeroCopy] attached output texture id={id} ptr=0x{mtl_texture_ptr:x} {width}x{height}"
    );
    Ok(())
}

/// Attach a pure-wgpu BGRA8Unorm storage texture as the zero-copy output.
/// This is the **benchmark-only** path — it has no Flutter CVPixelBuffer
/// backing, so the result is not visible on screen. It exists so the
/// benchmark can measure beauty compute + swizzle shader without the
/// cost of a CPU readback.
#[cfg(target_vendor = "apple")]
pub fn attach_output_texture_wgpu(
    id: i64,
    wgpu_texture: wgpu::Texture,
    width: u32,
    height: u32,
) -> Result<(), String> {
    let surface = surface_for(id)?;
    if width != surface.width || height != surface.height {
        return Err(format!(
            "output texture {width}x{height} does not match surface {}x{}",
            surface.width, surface.height
        ));
    }
    let ot = OutputTexture::Benchmark {
        wgpu_texture,
        width,
        height,
    };
    *surface
        .output_texture
        .lock()
        .map_err(|_| "output texture lock poisoned".to_string())? = Some(ot);
    log::info!("[ZeroCopy] attached wgpu-only output texture id={id} {width}x{height}");
    Ok(())
}

/// Detach the output texture (if any) and drop it. Called automatically on
/// `destroy_surface`.
#[cfg(target_vendor = "apple")]
pub fn detach_output_texture(id: i64) -> Result<(), String> {
    // If the surface does not exist, it has already been destroyed, so detaching is a no-op.
    let surface = match surface_for(id) {
        Ok(s) => s,
        Err(_) => return Ok(()),
    };
    let mut guard = surface
        .output_texture
        .lock()
        .map_err(|_| "output texture lock poisoned".to_string())?;
    if guard.take().is_some() {
        log::info!("[ZeroCopy] detached output texture id={id}");
    }
    Ok(())
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
pub fn apply_surface_beauty(id: i64, mask: SegmentationMask, strength: f32) -> Result<(), String> {
    let _surface = surface_for(id)?;
    #[cfg(feature = "gpu")]
    {
        let gpu = engine::engine()?;
        let params = BeautyParams {
            skin_smooth: strength,
            ..Default::default()
        };
        let effective = apply_exclude_mask(&mask, None);
        let mask_packed = pack_mask_r8(&effective.pixels);
        let mask_buf = gpu
            .device
            .create_buffer_init(&wgpu::util::BufferInitDescriptor {
                label: Some("beauty_mask"),
                contents: bytemuck::cast_slice(&mask_packed),
                usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST,
            });
        return gpu.apply_beauty_on_cache(
            gpu.beauty_pipelines(),
            &params,
            &mask_buf,
            None,
            None,
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

/// Full regional beauty on GPU surface (Sprint 22 — all passes on WGSL).
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
        let beauty = gpu.beauty_pipelines();

        let warp_specs = collect_gpu_warp_specs(analysis, params);
        if !warp_specs.is_empty() {
            gpu.apply_face_warp_on_cache(beauty, &warp_specs)?;
        }

        // Cache lookup or rebuild
        let (skin_buf, eye_buf, lip_buf, blush_buf, teeth_buf, under_eye_buf) = {
            let mut cached_opt = surface.cached_masks.lock().unwrap();
            let is_cache_valid = if let Some(ref c) = *cached_opt {
                c.width == w
                    && c.height == h
                    && c.landmarks.len() == analysis.landmarks.len()
                    && c.landmarks
                        .iter()
                        .zip(analysis.landmarks.iter())
                        .all(|(l1, l2)| l1.x == l2.x && l1.y == l2.y && l1.z == l2.z)
                    && c.exclude_pixels == exclude.map(|m| m.pixels.clone())
            } else {
                false
            };

            if !is_cache_valid {
                eprintln!(
                    "[GpuBeauty] Cache miss: rebuilding mask buffers for size={}x{}",
                    w, h
                );
                let new_skin = apply_exclude_mask(skin_mask, exclude);
                let skin_packed = pack_mask_r8(&new_skin.pixels);
                let skin_mask_buf =
                    gpu.device
                        .create_buffer_init(&wgpu::util::BufferInitDescriptor {
                            label: Some("beauty_skin_mask"),
                            contents: bytemuck::cast_slice(&skin_packed),
                            usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST,
                        });

                let eye_mask = build_eye_mask(analysis, w, h);
                let eye_effective = apply_exclude_mask(&eye_mask, exclude);
                let eye_packed = pack_mask_r8(&eye_effective.pixels);
                let eye_mask_buf =
                    gpu.device
                        .create_buffer_init(&wgpu::util::BufferInitDescriptor {
                            label: Some("beauty_eye_mask"),
                            contents: bytemuck::cast_slice(&eye_packed),
                            usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST,
                        });

                let lip_mask = build_lip_mask(analysis, w, h);
                let lip_effective = apply_exclude_mask(&lip_mask, exclude);
                let lip_packed = pack_mask_r8(&lip_effective.pixels);
                let lip_mask_buf =
                    gpu.device
                        .create_buffer_init(&wgpu::util::BufferInitDescriptor {
                            label: Some("beauty_lip_mask"),
                            contents: bytemuck::cast_slice(&lip_packed),
                            usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST,
                        });

                let blush_mask = build_blush_mask(analysis, w, h);
                let blush_effective = apply_exclude_mask(&blush_mask, exclude);
                let blush_packed = pack_mask_r8(&blush_effective.pixels);
                let blush_mask_buf =
                    gpu.device
                        .create_buffer_init(&wgpu::util::BufferInitDescriptor {
                            label: Some("beauty_blush_mask"),
                            contents: bytemuck::cast_slice(&blush_packed),
                            usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST,
                        });

                let teeth_mask = build_teeth_mask(analysis, w, h);
                let teeth_effective = apply_exclude_mask(&teeth_mask, exclude);
                let teeth_packed = pack_mask_r8(&teeth_effective.pixels);
                let teeth_mask_buf =
                    gpu.device
                        .create_buffer_init(&wgpu::util::BufferInitDescriptor {
                            label: Some("beauty_teeth_mask"),
                            contents: bytemuck::cast_slice(&teeth_packed),
                            usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST,
                        });

                let under_eye_mask = build_under_eye_mask(analysis, w, h);
                let under_eye_effective = apply_exclude_mask(&under_eye_mask, exclude);
                let under_eye_packed = pack_mask_r8(&under_eye_effective.pixels);
                let under_eye_mask_buf =
                    gpu.device
                        .create_buffer_init(&wgpu::util::BufferInitDescriptor {
                            label: Some("beauty_under_eye_mask"),
                            contents: bytemuck::cast_slice(&under_eye_packed),
                            usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST,
                        });

                *cached_opt = Some(CachedMasks {
                    landmarks: analysis.landmarks.clone(),
                    width: w,
                    height: h,
                    exclude_pixels: exclude.map(|m| m.pixels.clone()),
                    skin_mask_buf,
                    eye_mask_buf: Some(eye_mask_buf),
                    lip_mask_buf: Some(lip_mask_buf),
                    blush_mask_buf: Some(blush_mask_buf),
                    teeth_mask_buf: Some(teeth_mask_buf),
                    under_eye_mask_buf: Some(under_eye_mask_buf),
                });
            }

            let c = cached_opt.as_ref().unwrap();
            (
                c.skin_mask_buf.clone(),
                c.eye_mask_buf.clone(),
                c.lip_mask_buf.clone(),
                c.blush_mask_buf.clone(),
                c.teeth_mask_buf.clone(),
                c.under_eye_mask_buf.clone(),
            )
        };

        let lip_center = if params.lip_plump > 0.001 {
            Some(lip_center_norm(analysis))
        } else {
            None
        };

        gpu.apply_beauty_on_cache(
            beauty,
            params,
            &skin_buf,
            eye_buf.as_ref(),
            lip_buf.as_ref(),
            blush_buf.as_ref(),
            teeth_buf.as_ref(),
            under_eye_buf.as_ref(),
            lip_buf.as_ref(), // lip plump uses lip mask as ref
            lip_center,
        )?;

        return Ok(());
    }
    #[cfg(not(feature = "gpu"))]
    {
        let _ = (id, analysis, skin_mask, params, exclude);
        Err("GPU feature disabled".into())
    }
}

/// Full regional beauty on GPU surface **with zero-copy output** to an
/// attached BGRA8Unorm output texture. Apple only. Falls back to the
/// non-output path if no output texture is attached.
#[cfg(target_vendor = "apple")]
pub fn apply_surface_beauty_pipeline_with_output(
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
        let beauty = gpu.beauty_pipelines();

        let warp_specs = collect_gpu_warp_specs(analysis, params);
        if !warp_specs.is_empty() {
            gpu.apply_face_warp_on_cache(beauty, &warp_specs)?;
        }

        let (skin_buf, eye_buf, lip_buf, blush_buf, teeth_buf, under_eye_buf) = {
            let mut cached_opt = surface.cached_masks.lock().unwrap();
            let is_cache_valid = if let Some(ref c) = *cached_opt {
                c.width == w
                    && c.height == h
                    && c.landmarks.len() == analysis.landmarks.len()
                    && c.landmarks
                        .iter()
                        .zip(analysis.landmarks.iter())
                        .all(|(l1, l2)| l1.x == l2.x && l1.y == l2.y && l1.z == l2.z)
                    && c.exclude_pixels == exclude.map(|m| m.pixels.clone())
            } else {
                false
            };

            if !is_cache_valid {
                eprintln!(
                    "[GpuBeauty] Cache miss: rebuilding mask buffers for size={}x{}",
                    w, h
                );
                let new_skin = apply_exclude_mask(skin_mask, exclude);
                let skin_packed = pack_mask_r8(&new_skin.pixels);
                let skin_mask_buf =
                    gpu.device
                        .create_buffer_init(&wgpu::util::BufferInitDescriptor {
                            label: Some("beauty_skin_mask"),
                            contents: bytemuck::cast_slice(&skin_packed),
                            usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST,
                        });

                let eye_mask = build_eye_mask(analysis, w, h);
                let eye_effective = apply_exclude_mask(&eye_mask, exclude);
                let eye_packed = pack_mask_r8(&eye_effective.pixels);
                let eye_mask_buf =
                    gpu.device
                        .create_buffer_init(&wgpu::util::BufferInitDescriptor {
                            label: Some("beauty_eye_mask"),
                            contents: bytemuck::cast_slice(&eye_packed),
                            usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST,
                        });

                let lip_mask = build_lip_mask(analysis, w, h);
                let lip_effective = apply_exclude_mask(&lip_mask, exclude);
                let lip_packed = pack_mask_r8(&lip_effective.pixels);
                let lip_mask_buf =
                    gpu.device
                        .create_buffer_init(&wgpu::util::BufferInitDescriptor {
                            label: Some("beauty_lip_mask"),
                            contents: bytemuck::cast_slice(&lip_packed),
                            usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST,
                        });

                let blush_mask = build_blush_mask(analysis, w, h);
                let blush_effective = apply_exclude_mask(&blush_mask, exclude);
                let blush_packed = pack_mask_r8(&blush_effective.pixels);
                let blush_mask_buf =
                    gpu.device
                        .create_buffer_init(&wgpu::util::BufferInitDescriptor {
                            label: Some("beauty_blush_mask"),
                            contents: bytemuck::cast_slice(&blush_packed),
                            usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST,
                        });

                let teeth_mask = build_teeth_mask(analysis, w, h);
                let teeth_effective = apply_exclude_mask(&teeth_mask, exclude);
                let teeth_packed = pack_mask_r8(&teeth_effective.pixels);
                let teeth_mask_buf =
                    gpu.device
                        .create_buffer_init(&wgpu::util::BufferInitDescriptor {
                            label: Some("beauty_teeth_mask"),
                            contents: bytemuck::cast_slice(&teeth_packed),
                            usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST,
                        });

                let under_eye_mask = build_under_eye_mask(analysis, w, h);
                let under_eye_effective = apply_exclude_mask(&under_eye_mask, exclude);
                let under_eye_packed = pack_mask_r8(&under_eye_effective.pixels);
                let under_eye_mask_buf =
                    gpu.device
                        .create_buffer_init(&wgpu::util::BufferInitDescriptor {
                            label: Some("beauty_under_eye_mask"),
                            contents: bytemuck::cast_slice(&under_eye_packed),
                            usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST,
                        });

                *cached_opt = Some(CachedMasks {
                    landmarks: analysis.landmarks.clone(),
                    width: w,
                    height: h,
                    exclude_pixels: exclude.map(|m| m.pixels.clone()),
                    skin_mask_buf,
                    eye_mask_buf: Some(eye_mask_buf),
                    lip_mask_buf: Some(lip_mask_buf),
                    blush_mask_buf: Some(blush_mask_buf),
                    teeth_mask_buf: Some(teeth_mask_buf),
                    under_eye_mask_buf: Some(under_eye_mask_buf),
                });
            }

            let c = cached_opt.as_ref().unwrap();
            (
                c.skin_mask_buf.clone(),
                c.eye_mask_buf.clone(),
                c.lip_mask_buf.clone(),
                c.blush_mask_buf.clone(),
                c.teeth_mask_buf.clone(),
                c.under_eye_mask_buf.clone(),
            )
        };

        let lip_center = if params.lip_plump > 0.001 {
            Some(lip_center_norm(analysis))
        } else {
            None
        };

        // Try the zero-copy output path. If no output texture is attached,
        // fall back to the regular apply_beauty_on_cache.
        let output_guard = surface
            .output_texture
            .lock()
            .map_err(|_| "output lock poisoned")?;
        if let Some(ot) = output_guard.as_ref() {
            gpu.apply_beauty_on_cache_with_output(
                beauty,
                params,
                &skin_buf,
                eye_buf.as_ref(),
                lip_buf.as_ref(),
                blush_buf.as_ref(),
                teeth_buf.as_ref(),
                under_eye_buf.as_ref(),
                lip_buf.as_ref(),
                lip_center,
                ot.wgpu_texture(),
            )?;
        } else {
            drop(output_guard);
            gpu.apply_beauty_on_cache(
                beauty,
                params,
                &skin_buf,
                eye_buf.as_ref(),
                lip_buf.as_ref(),
                blush_buf.as_ref(),
                teeth_buf.as_ref(),
                under_eye_buf.as_ref(),
                lip_buf.as_ref(),
                lip_center,
            )?;
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
        .cloned()
        .ok_or_else(|| format!("unknown GPU surface {id}"))
}

impl Clone for GpuEditSurface {
    fn clone(&self) -> Self {
        Self {
            width: self.width,
            height: self.height,
            cached_masks: std::sync::Arc::clone(&self.cached_masks),
            #[cfg(target_vendor = "apple")]
            output_texture: std::sync::Arc::clone(&self.output_texture),
        }
    }
}
