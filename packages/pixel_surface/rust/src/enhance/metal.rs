//! Apple Metal enhancement backend (wgpu over the Metal HAL).
//!
//! Decoded `CVPixelBuffer` (IOSurface, BGRA) → imported MTLTexture → wgpu
//! compute passes → IOSurface-backed output `CVPixelBuffer` that
//! `pixel_surface` hands to Flutter's `Texture` widget. Nothing is copied
//! through the CPU, and the shader works in logical RGBA on `bgra8unorm`
//! textures, so no channel swizzle round-trip is needed either.
//!
//! Only available with `--features gpu` on Apple targets.

use std::ffi::c_void;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, OnceLock};
use std::time::Instant;

use bytemuck::{Pod, Zeroable};

use super::plan::{EnhancementPlan, Scaler};
use super::{
    EnhancementBackend, EnhancementCapabilities, EnhancementError, EnhancementFrame,
    EnhancementMode, FrameHandle, FrameSize,
};
use crate::metal_iosurface::{self, IosurfacePixelBuffer};
use crate::wgpu_metal_import::wrap_metal_texture_as_wgpu_bgra;

/// Backend identity reported through diagnostics.
pub const BACKEND_NAME: &str = "metal_wgpu";

const SHADER_SOURCE: &str = include_str!("shaders/enhance.wgsl");

/// Compute workgroup edge (see `@workgroup_size(8, 8)` in the shader).
const WORKGROUP: u32 = 8;

/// Output surfaces kept in rotation. Three matches the depth of the Darwin
/// `PixelBufferPool`: deep enough that a buffer being scanned out is never
/// overwritten by the next frame, shallow enough to stay cheap.
const OUTPUT_RING: usize = 3;

const FILTER_CATMULL_ROM: u32 = 1;
const FILTER_LANCZOS3: u32 = 2;

/// Uncaptured wgpu errors seen since process start.
///
/// Playback must never crash because the enhancement stage misbehaved, so the
/// device installs a logging handler instead of the default panic handler and
/// bumps this counter. [`MetalEnhancementBackend::process`] turns a growing
/// counter into a normal `Err`, which the caller degrades through its
/// failure ladder.
static GPU_ERRORS: OnceLock<AtomicU64> = OnceLock::new();

fn gpu_error_counter() -> &'static AtomicU64 {
    GPU_ERRORS.get_or_init(|| AtomicU64::new(0))
}

#[repr(C)]
#[derive(Clone, Copy, Pod, Zeroable)]
struct Params {
    src_w: u32,
    src_h: u32,
    dst_w: u32,
    dst_h: u32,
    filter_kind: u32,
    sharpen: f32,
    dither: f32,
    _pad: f32,
}

/// Process-wide wgpu device + pipelines. Device creation costs tens of
/// milliseconds and the pipelines are mode-independent, so one per process is
/// cheaper and more predictable than one per player instance.
struct GpuContext {
    device: wgpu::Device,
    queue: wgpu::Queue,
    adapter_name: String,
    metal_device: metal::Device,
    layout: wgpu::BindGroupLayout,
    scale_h: wgpu::ComputePipeline,
    scale_v: wgpu::ComputePipeline,
    sharpen: wgpu::ComputePipeline,
}

static CONTEXT: OnceLock<Result<Arc<GpuContext>, String>> = OnceLock::new();

fn context() -> Result<Arc<GpuContext>, String> {
    CONTEXT
        .get_or_init(build_context)
        .as_ref()
        .map(Arc::clone)
        .map_err(|e| e.clone())
}

fn build_context() -> Result<Arc<GpuContext>, String> {
    let instance = wgpu::Instance::new(&wgpu::InstanceDescriptor {
        backends: wgpu::Backends::METAL,
        ..Default::default()
    });
    let adapter = pollster::block_on(instance.request_adapter(&wgpu::RequestAdapterOptions {
        power_preference: wgpu::PowerPreference::HighPerformance,
        compatible_surface: None,
        force_fallback_adapter: false,
    }))
    .ok_or_else(|| "no Metal adapter available".to_string())?;

    let info = adapter.get_info();
    if info.backend != wgpu::Backend::Metal {
        return Err(format!("expected a Metal adapter, got {:?}", info.backend));
    }
    if !adapter
        .features()
        .contains(wgpu::Features::BGRA8UNORM_STORAGE)
    {
        return Err("Metal adapter does not expose BGRA8UNORM_STORAGE".to_string());
    }
    // The IOSurface textures come from `CVMetalTextureCache`, which is bound to
    // a `MTLDevice`. Using a texture from a different device is undefined in
    // Metal, so require the same device wgpu selected.
    let metal_device = metal_device_named(&info.name).ok_or_else(|| {
        format!(
            "no MTLDevice named {:?} for the wgpu adapter (device mismatch)",
            info.name
        )
    })?;

    let (device, queue) = pollster::block_on(adapter.request_device(
        &wgpu::DeviceDescriptor {
            label: Some("pixel_surface_video_enhance"),
            required_features: wgpu::Features::BGRA8UNORM_STORAGE,
            required_limits: wgpu::Limits::default(),
            memory_hints: wgpu::MemoryHints::Performance,
        },
        None,
    ))
    .map_err(|e| format!("enhancement device request failed: {e}"))?;

    // A GPU error must degrade the feature, never the app: log + count instead
    // of wgpu's default panic handler.
    device.on_uncaptured_error(Box::new(|error| {
        gpu_error_counter().fetch_add(1, Ordering::Relaxed);
        eprintln!("[VideoEnhance] wgpu error (degrading): {error}");
    }));

    // Compile the shader inside a validation scope so a broken pipeline is a
    // reported capability gap rather than a crash.
    device.push_error_scope(wgpu::ErrorFilter::Validation);
    let module = device.create_shader_module(wgpu::ShaderModuleDescriptor {
        label: Some("video_enhance_shader"),
        source: wgpu::ShaderSource::Wgsl(SHADER_SOURCE.into()),
    });

    // Every pass shares one layout: params, source texture, BGRA storage target.
    let layout = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
        label: Some("video_enhance_bgl"),
        entries: &[
            wgpu::BindGroupLayoutEntry {
                binding: 0,
                visibility: wgpu::ShaderStages::COMPUTE,
                ty: wgpu::BindingType::Buffer {
                    ty: wgpu::BufferBindingType::Uniform,
                    has_dynamic_offset: false,
                    min_binding_size: None,
                },
                count: None,
            },
            wgpu::BindGroupLayoutEntry {
                binding: 1,
                visibility: wgpu::ShaderStages::COMPUTE,
                ty: wgpu::BindingType::Texture {
                    sample_type: wgpu::TextureSampleType::Float { filterable: false },
                    view_dimension: wgpu::TextureViewDimension::D2,
                    multisampled: false,
                },
                count: None,
            },
            wgpu::BindGroupLayoutEntry {
                binding: 2,
                visibility: wgpu::ShaderStages::COMPUTE,
                ty: wgpu::BindingType::StorageTexture {
                    access: wgpu::StorageTextureAccess::WriteOnly,
                    format: wgpu::TextureFormat::Bgra8Unorm,
                    view_dimension: wgpu::TextureViewDimension::D2,
                },
                count: None,
            },
        ],
    });
    let pipeline_layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
        label: Some("video_enhance_pl"),
        bind_group_layouts: &[&layout],
        push_constant_ranges: &[],
    });
    let pipeline = |label: &str, entry: &str| {
        device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
            label: Some(label),
            layout: Some(&pipeline_layout),
            module: &module,
            entry_point: Some(entry),
            compilation_options: Default::default(),
            cache: None,
        })
    };
    let scale_h = pipeline("video_enhance_scale_h", "scale_h");
    let scale_v = pipeline("video_enhance_scale_v", "scale_v");
    let sharpen = pipeline("video_enhance_sharpen", "sharpen");

    // Pipeline creation is asynchronous on some backends; sync once so the
    // validation scope below has seen everything before we read it.
    device.poll(wgpu::Maintain::Wait);
    if let Some(error) = pollster::block_on(device.pop_error_scope()) {
        return Err(format!("enhancement pipeline validation failed: {error}"));
    }

    Ok(Arc::new(GpuContext {
        scale_h,
        scale_v,
        sharpen,
        device,
        queue,
        adapter_name: info.name,
        metal_device,
        layout,
    }))
}

/// The `MTLDevice` whose name matches the wgpu adapter, so the IOSurface
/// textures and the wgpu device are guaranteed to be the same GPU.
fn metal_device_named(name: &str) -> Option<metal::Device> {
    if let Some(default) = metal::Device::system_default() {
        if default.name() == name {
            return Some(default);
        }
    }
    metal::Device::all().into_iter().find(|d| d.name() == name)
}

/// A wgpu texture plus the Metal resource it borrows.
///
/// Declaration order matters: `texture` is dropped before `metal_texture`, so
/// the wgpu HAL never releases a Metal object that a command buffer still
/// references.
struct GpuSurface {
    /// Owns the wgpu texture. Never read directly — `view` is what every pass
    /// binds — but it must outlive the view and be dropped first.
    #[allow(dead_code)]
    texture: wgpu::Texture,
    view: wgpu::TextureView,
    /// `None` for textures wgpu allocated itself (scratch).
    #[allow(dead_code)]
    metal_texture: Option<metal::Texture>,
    width: u32,
    height: u32,
}

impl GpuSurface {
    /// Import an existing `MTLTexture` (from a `CVPixelBuffer`) as a wgpu
    /// `Bgra8Unorm` texture. Takes ownership of `mtl`'s retain.
    fn from_metal(
        device: &wgpu::Device,
        mtl: metal::Texture,
        width: u32,
        height: u32,
    ) -> Result<Self, EnhancementError> {
        if width == 0 || height == 0 {
            return Err(EnhancementError::InputUnavailable(format!(
                "invalid texture size {width}x{height}"
            )));
        }
        // The importer consumes one retain; `mtl` kept below holds the other,
        // so both the wgpu texture and this struct stay valid independently.
        //
        // SAFETY: `mtl` is a +1-retained BGRA8Unorm 2D MTLTexture created on
        // the same MTLDevice wgpu uses (enforced at context creation), and it
        // is stored after `texture` so it outlives every wgpu submission.
        let texture =
            unsafe { wrap_metal_texture_as_wgpu_bgra(device, mtl.clone(), width, height) };
        let view = texture.create_view(&wgpu::TextureViewDescriptor::default());
        Ok(Self {
            texture,
            view,
            metal_texture: Some(mtl),
            width,
            height,
        })
    }

    /// Scratch texture owned entirely by wgpu (never handed to Flutter).
    fn scratch(device: &wgpu::Device, width: u32, height: u32) -> Self {
        let texture = device.create_texture(&wgpu::TextureDescriptor {
            label: Some("video_enhance_scratch"),
            size: wgpu::Extent3d {
                width,
                height,
                depth_or_array_layers: 1,
            },
            mip_level_count: 1,
            sample_count: 1,
            dimension: wgpu::TextureDimension::D2,
            format: wgpu::TextureFormat::Bgra8Unorm,
            usage: wgpu::TextureUsages::STORAGE_BINDING | wgpu::TextureUsages::TEXTURE_BINDING,
            view_formats: &[],
        });
        let view = texture.create_view(&wgpu::TextureViewDescriptor::default());
        Self {
            texture,
            view,
            metal_texture: None,
            width,
            height,
        }
    }

    fn size(&self) -> (u32, u32) {
        (self.width, self.height)
    }
}

/// An enhancement output: the pooled IOSurface plus its wgpu import.
struct OutputSurface {
    /// Dropped before `owner`, releasing the wgpu import first.
    gpu: GpuSurface,
    owner: IosurfacePixelBuffer,
}

impl OutputSurface {
    fn new(
        device: &wgpu::Device,
        metal_device: &metal::Device,
        size: FrameSize,
    ) -> Result<Self, EnhancementError> {
        let owner = metal_iosurface::create_bgra_iosurface_pixel_buffer_metal(
            metal_device,
            size.width,
            size.height,
        )
        .map_err(EnhancementError::OutputUnavailable)?;
        let mtl = owner.metal_texture.clone_metal_texture();
        let gpu = GpuSurface::from_metal(device, mtl, size.width, size.height)?;
        Ok(Self { gpu, owner })
    }

    fn pixel_buffer(&self) -> *mut c_void {
        self.owner.pixel_buffer
    }
}

/// Cached scratch textures, recreated only when the geometry changes.
#[derive(Default)]
struct ScratchSet {
    /// `(dst_w × src_h)` — horizontal-pass output when the row count changes.
    mid: Option<GpuSurface>,
    /// `(dst_w × dst_h)` — the final scaled image.
    full: Option<GpuSurface>,
}

pub struct MetalEnhancementBackend {
    ctx: Arc<GpuContext>,
    params: [wgpu::Buffer; 3],
    outputs: Vec<OutputSurface>,
    output_size: FrameSize,
    next_output: usize,
    scratch: ScratchSet,
    last_allocated_fresh: bool,
}

impl MetalEnhancementBackend {
    pub fn new() -> Result<Self, String> {
        let ctx = context()?;
        let params = std::array::from_fn(|i| {
            ctx.device.create_buffer(&wgpu::BufferDescriptor {
                label: Some(match i {
                    0 => "video_enhance_params_h",
                    1 => "video_enhance_params_v",
                    _ => "video_enhance_params_sharpen",
                }),
                size: std::mem::size_of::<Params>() as u64,
                usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
                mapped_at_creation: false,
            })
        });
        Ok(Self {
            ctx,
            params,
            outputs: Vec::new(),
            output_size: FrameSize::new(0, 0),
            next_output: 0,
            scratch: ScratchSet::default(),
            last_allocated_fresh: false,
        })
    }

    /// Rotate the output ring at `size`, rebuilding it when the geometry
    /// changes. Rebuilding happens on mode / output-size changes only, never
    /// per frame.
    fn acquire_output(&mut self, size: FrameSize) -> Result<usize, EnhancementError> {
        if self.output_size != size || self.outputs.len() != OUTPUT_RING {
            let mut ring = Vec::with_capacity(OUTPUT_RING);
            for _ in 0..OUTPUT_RING {
                ring.push(OutputSurface::new(
                    &self.ctx.device,
                    &self.ctx.metal_device,
                    size,
                )?);
            }
            self.outputs = ring;
            self.output_size = size;
            self.next_output = 0;
            self.scratch = ScratchSet::default();
            self.last_allocated_fresh = true;
        } else {
            self.last_allocated_fresh = false;
        }
        let index = self.next_output % self.outputs.len();
        self.next_output = index + 1;
        Ok(index)
    }

    fn ensure_scratch(&mut self, plan: &EnhancementPlan) {
        let (src, dst) = (plan.source, plan.target);
        if self.scratch.full.as_ref().map(GpuSurface::size) != Some(dst.size_tuple()) {
            self.scratch.full = Some(GpuSurface::scratch(&self.ctx.device, dst.width, dst.height));
        }
        if dst.height != src.height {
            if self.scratch.mid.as_ref().map(GpuSurface::size)
                != Some((dst.width, src.height))
            {
                self.scratch.mid =
                    Some(GpuSurface::scratch(&self.ctx.device, dst.width, src.height));
            }
        } else {
            self.scratch.mid = None;
        }
    }

    #[allow(clippy::too_many_arguments)]
    fn dispatch(
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        encoder: &mut wgpu::CommandEncoder,
        layout: &wgpu::BindGroupLayout,
        pipeline: &wgpu::ComputePipeline,
        params: &wgpu::Buffer,
        params_value: Params,
        source: &wgpu::TextureView,
        target: &wgpu::TextureView,
        target_size: (u32, u32),
        label: &str,
    ) {
        queue.write_buffer(params, 0, bytemuck::bytes_of(&params_value));
        let bind_group = device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some(label),
            layout,
            entries: &[
                wgpu::BindGroupEntry {
                    binding: 0,
                    resource: params.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 1,
                    resource: wgpu::BindingResource::TextureView(source),
                },
                wgpu::BindGroupEntry {
                    binding: 2,
                    resource: wgpu::BindingResource::TextureView(target),
                },
            ],
        });
        let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some(label),
            timestamp_writes: None,
        });
        pass.set_pipeline(pipeline);
        pass.set_bind_group(0, &bind_group, &[]);
        pass.dispatch_workgroups(
            target_size.0.div_ceil(WORKGROUP),
            target_size.1.div_ceil(WORKGROUP),
            1,
        );
    }

    fn scaler_filter(plan: &EnhancementPlan) -> u32 {
        match plan.scaler {
            Scaler::Lanczos3 => FILTER_LANCZOS3,
            _ => FILTER_CATMULL_ROM,
        }
    }

    fn path_name(plan: &EnhancementPlan) -> &'static str {
        match plan.scaler {
            Scaler::Lanczos3 => "metal_lanczos_cas",
            Scaler::CatmullRom => "metal_catmull_cas",
            Scaler::None => "metal_cas",
        }
    }
}

impl EnhancementBackend for MetalEnhancementBackend {
    fn backend_name(&self) -> String {
        BACKEND_NAME.to_string()
    }

    fn capabilities(&self) -> EnhancementCapabilities {
        EnhancementCapabilities {
            supported: true,
            backend: BACKEND_NAME.to_string(),
            modes: EnhancementMode::ALL.to_vec(),
            max_output_edge: super::plan::HIGH_QUALITY_MAX_EDGE,
            reason: self.ctx.adapter_name.clone(),
        }
    }

    fn process(
        &mut self,
        input: FrameHandle,
        input_size: FrameSize,
        plan: &EnhancementPlan,
    ) -> Result<EnhancementFrame, EnhancementError> {
        if !plan.is_active() {
            return Err(EnhancementError::Unsupported("plan is inactive".to_string()));
        }
        let raw = match input {
            FrameHandle::CvPixelBuffer(p) | FrameHandle::Raw(p) => p as *mut c_void,
        };
        if raw.is_null() {
            return Err(EnhancementError::InputUnavailable(
                "null frame handle".to_string(),
            ));
        }

        let started = Instant::now();
        let errors_before = gpu_error_counter().load(Ordering::Relaxed);
        let ctx = Arc::clone(&self.ctx);
        let scaling = plan.is_scaling();

        // SAFETY: the caller guarantees `raw` is a live CVPixelBuffer for the
        // duration of this call. The view keeps its own retain, and it is
        // dropped after the GPU work below has completed.
        let input_view = unsafe {
            metal_iosurface::metal_texture_view_for_pixel_buffer(
                &ctx.metal_device,
                raw,
                input_size.width,
                input_size.height,
            )
        }
        .map_err(EnhancementError::InputUnavailable)?;
        let input_surface = GpuSurface::from_metal(
            &ctx.device,
            input_view.clone_metal_texture(),
            input_size.width,
            input_size.height,
        )?;

        let output_index = self.acquire_output(plan.target)?;
        if scaling {
            self.ensure_scratch(plan);
        }

        let mut encoder = ctx
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("video_enhance_encoder"),
            });
        let mut passes = 0u32;

        if scaling {
            let filter = Self::scaler_filter(plan);
            // Horizontal: (src_w × src_h) → (dst_w × src_h). Written straight
            // into `full` when the row count is unchanged.
            let horizontal_target = if plan.target.height != plan.source.height {
                self.scratch.mid.as_ref()
            } else {
                self.scratch.full.as_ref()
            }
            .ok_or_else(|| EnhancementError::OutputUnavailable("scratch missing".to_string()))?;
            Self::dispatch(
                &ctx.device,
                &ctx.queue,
                &mut encoder,
                &ctx.layout,
                &ctx.scale_h,
                &self.params[0],
                Params {
                    src_w: plan.source.width,
                    src_h: plan.source.height,
                    dst_w: plan.target.width,
                    dst_h: plan.source.height,
                    filter_kind: filter,
                    sharpen: 0.0,
                    dither: 0.0,
                    _pad: 0.0,
                },
                &input_surface.view,
                &horizontal_target.view,
                (plan.target.width, plan.source.height),
                "video_enhance_scale_h",
            );
            passes += 1;

            // Vertical: (dst_w × src_h) → (dst_w × dst_h).
            if plan.target.height != plan.source.height {
                let full = self
                    .scratch
                    .full
                    .as_ref()
                    .ok_or_else(|| {
                        EnhancementError::OutputUnavailable("scratch missing".to_string())
                    })?;
                Self::dispatch(
                    &ctx.device,
                    &ctx.queue,
                    &mut encoder,
                    &ctx.layout,
                    &ctx.scale_v,
                    &self.params[1],
                    Params {
                        src_w: plan.target.width,
                        src_h: plan.source.height,
                        dst_w: plan.target.width,
                        dst_h: plan.target.height,
                        filter_kind: filter,
                        sharpen: 0.0,
                        dither: 0.0,
                        _pad: 0.0,
                    },
                    &horizontal_target.view,
                    &full.view,
                    (plan.target.width, plan.target.height),
                    "video_enhance_scale_v",
                );
                passes += 1;
            }
        }

        // Sharpen always reads a target-sized image: the scaler output when
        // scaling, otherwise the decoded frame itself.
        let sharpen_source = if scaling {
            &self
                .scratch
                .full
                .as_ref()
                .ok_or_else(|| EnhancementError::OutputUnavailable("scratch missing".to_string()))?
                .view
        } else {
            &input_surface.view
        };
        let output = &self.outputs[output_index];
        Self::dispatch(
            &ctx.device,
            &ctx.queue,
            &mut encoder,
            &ctx.layout,
            &ctx.sharpen,
            &self.params[2],
            Params {
                src_w: plan.target.width,
                src_h: plan.target.height,
                dst_w: plan.target.width,
                dst_h: plan.target.height,
                filter_kind: 0,
                sharpen: plan.sharpen,
                dither: plan.dither,
                _pad: 0.0,
            },
            sharpen_source,
            &output.gpu.view,
            (plan.target.width, plan.target.height),
            "video_enhance_sharpen",
        );
        passes += 1;

        ctx.queue.submit(Some(encoder.finish()));
        // One frame in flight: waiting here makes the measurement below the
        // real GPU cost, and guarantees a slow device can never queue up work
        // that would later surface as A/V drift.
        ctx.device.poll(wgpu::Maintain::Wait);
        let frame_ms = started.elapsed().as_secs_f32() * 1000.0;

        // The caller's +1 on the decoded frame is consumed by a successful
        // pass (see the trait contract). The Metal views above hold their own
        // retains, so dropping them first keeps the release order obvious.
        drop(input_surface);
        drop(input_view);
        if let FrameHandle::CvPixelBuffer(_) = input {
            metal_iosurface::release_pixel_buffer(raw);
        }

        let errors_after = gpu_error_counter().load(Ordering::Relaxed);
        if errors_after > errors_before {
            return Err(EnhancementError::OutputUnavailable(format!(
                "{} wgpu error(s) during the pass",
                errors_after - errors_before
            )));
        }

        // +1 for the caller; the presentation layer consumes it.
        let handoff = metal_iosurface::retain_pixel_buffer(output.pixel_buffer());

        Ok(EnhancementFrame {
            handle: FrameHandle::CvPixelBuffer(handoff as usize),
            size: plan.target,
            path: Self::path_name(plan),
            passes,
            scaler: plan.scaler,
            frame_ms,
            fresh_surface: self.last_allocated_fresh,
        })
    }

    fn release_pooled_resources(&mut self) {
        self.outputs.clear();
        self.output_size = FrameSize::new(0, 0);
        self.next_output = 0;
        self.scratch = ScratchSet::default();
    }
}
