//! Nexus D + Sprint 22 — GPU regional beauty on the pipeline cache (no CPU readback).

use bytemuck::{Pod, Zeroable};
use wgpu::util::DeviceExt;

use crate::api::face::{BeautyParams, LipTintPreset};
use crate::face::warp_mesh::GpuWarpSpec;

use super::engine::GpuEngine;

const SKIN_SMOOTH_H_SHADER: &str = include_str!("shaders/skin_smooth_h.wgsl");
const SKIN_SMOOTH_V_SHADER: &str = include_str!("shaders/skin_smooth_v.wgsl");
const EYE_BRIGHTEN_SHADER: &str = include_str!("shaders/eye_brighten.wgsl");
const LIP_TINT_SHADER: &str = include_str!("shaders/lip_tint.wgsl");
const BLUSH_SHADER: &str = include_str!("shaders/blush.wgsl");
const TEETH_WHITEN_SHADER: &str = include_str!("shaders/teeth_whiten.wgsl");
const UNDER_EYE_SHADER: &str = include_str!("shaders/under_eye.wgsl");
const LIP_PLUMP_SHADER: &str = include_str!("shaders/lip_plump.wgsl");
const FACE_WARP_SHADER: &str = include_str!("shaders/face_warp.wgsl");
const BEAUTY_OUTPUT_SWIZZLE_SHADER: &str = include_str!("shaders/beauty_output_swizzle.wgsl");

#[repr(C)]
#[derive(Clone, Copy, Pod, Zeroable)]
struct SwizzleParams {
    width: u32,
    height: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Pod, Zeroable)]
struct SkinSmoothParams {
    width: u32,
    height: u32,
    radius: u32,
    strength: f32,
    preserve_detail: f32,
}

#[repr(C)]
#[derive(Clone, Copy, Pod, Zeroable)]
struct EyeBrightenParams {
    width: u32,
    height: u32,
    strength: f32,
    _pad: f32,
}

#[repr(C)]
#[derive(Clone, Copy, Pod, Zeroable)]
struct LipTintParams {
    width: u32,
    height: u32,
    strength: f32,
    target_r: f32,
    target_g: f32,
    target_b: f32,
}

#[repr(C)]
#[derive(Clone, Copy, Pod, Zeroable)]
struct BlushParams {
    width: u32,
    height: u32,
    strength: f32,
    _pad: f32,
}

#[repr(C)]
#[derive(Clone, Copy, Pod, Zeroable)]
struct LipPlumpParams {
    width: u32,
    height: u32,
    strength: f32,
    lip_cx: f32,
    lip_cy: f32,
}

#[repr(C)]
#[derive(Clone, Copy, Pod, Zeroable)]
struct FaceWarpParams {
    width: u32,
    height: u32,
    cx: f32,
    cy: f32,
    radius_norm: f32,
    strength: f32,
    falloff: f32,
}

pub(crate) struct BeautyGpuPipelines {
    pub skin_smooth_h: wgpu::ComputePipeline,
    pub skin_smooth_v: wgpu::ComputePipeline,
    pub eye_brighten: wgpu::ComputePipeline,
    pub lip_tint: wgpu::ComputePipeline,
    pub blush: wgpu::ComputePipeline,
    pub teeth_whiten: wgpu::ComputePipeline,
    pub under_eye: wgpu::ComputePipeline,
    pub lip_plump: wgpu::ComputePipeline,
    pub face_warp: wgpu::ComputePipeline,
    pub output_swizzle: wgpu::ComputePipeline,
}

impl BeautyGpuPipelines {
    pub fn new(device: &wgpu::Device) -> Self {
        let mk = |label: &str, src: &str| {
            let shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
                label: Some(label),
                source: wgpu::ShaderSource::Wgsl(src.into()),
            });
            device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
                label: Some(label),
                layout: None,
                module: &shader,
                entry_point: Some("main"),
                compilation_options: Default::default(),
                cache: None,
            })
        };
        Self {
            skin_smooth_h: mk("skin_smooth_h_pipeline", SKIN_SMOOTH_H_SHADER),
            skin_smooth_v: mk("skin_smooth_v_pipeline", SKIN_SMOOTH_V_SHADER),
            eye_brighten: mk("eye_brighten_pipeline", EYE_BRIGHTEN_SHADER),
            lip_tint: mk("lip_tint_pipeline", LIP_TINT_SHADER),
            blush: mk("blush_pipeline", BLUSH_SHADER),
            teeth_whiten: mk("teeth_whiten_pipeline", TEETH_WHITEN_SHADER),
            under_eye: mk("under_eye_pipeline", UNDER_EYE_SHADER),
            lip_plump: mk("lip_plump_pipeline", LIP_PLUMP_SHADER),
            face_warp: mk("face_warp_pipeline", FACE_WARP_SHADER),
            output_swizzle: mk(
                "beauty_output_swizzle_pipeline",
                BEAUTY_OUTPUT_SWIZZLE_SHADER,
            ),
        }
    }
}

fn lip_tint_rgb(preset: LipTintPreset) -> Option<(f32, f32, f32)> {
    match preset {
        LipTintPreset::None => None,
        LipTintPreset::Nude => Some((210.0, 170.0, 150.0)),
        LipTintPreset::Rose => Some((200.0, 110.0, 125.0)),
        LipTintPreset::Berry => Some((170.0, 60.0, 90.0)),
        LipTintPreset::Coral => Some((230.0, 120.0, 90.0)),
        LipTintPreset::Red => Some((210.0, 50.0, 55.0)),
    }
}

pub(crate) fn pack_mask_r8(pixels: &[u8]) -> Vec<u32> {
    pixels.iter().map(|&p| p as u32).collect()
}

impl GpuEngine {
    /// Landmark-driven radial warps on the pipeline cache (Sprint 22).
    pub(crate) fn apply_face_warp_on_cache(
        &self,
        beauty: &BeautyGpuPipelines,
        specs: &[GpuWarpSpec],
    ) -> Result<(), String> {
        let _gpu = super::engine::gpu_op_lock();
        if specs.is_empty() {
            return Ok(());
        }

        let (width, height, storage_buf1, storage_buf2, mut active_is_1) = {
            let cache = self.cached_buffers.lock();
            let c = cache
                .as_ref()
                .ok_or("GPU pipeline cache empty — upload first")?;
            (
                c.width,
                c.height,
                c.storage_buf.clone(),
                c.storage_buf2.clone(),
                c.active_is_1,
            )
        };

        let mut encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("face_warp_gpu_encoder"),
            });

        for spec in specs {
            let p = FaceWarpParams {
                width,
                height,
                cx: spec.cx,
                cy: spec.cy,
                radius_norm: spec.radius_norm,
                strength: spec.strength,
                falloff: spec.falloff,
            };
            let params_buf = self
                .device
                .create_buffer_init(&wgpu::util::BufferInitDescriptor {
                    label: Some("face_warp_params"),
                    contents: bytemuck::bytes_of(&p),
                    usage: wgpu::BufferUsages::UNIFORM,
                });
            let (input, output) = if active_is_1 {
                (&storage_buf1, &storage_buf2)
            } else {
                (&storage_buf2, &storage_buf1)
            };
            let bind_group = self.device.create_bind_group(&wgpu::BindGroupDescriptor {
                label: Some("face_warp_pass"),
                layout: &beauty.face_warp.get_bind_group_layout(0),
                entries: &[
                    wgpu::BindGroupEntry {
                        binding: 0,
                        resource: params_buf.as_entire_binding(),
                    },
                    wgpu::BindGroupEntry {
                        binding: 1,
                        resource: input.as_entire_binding(),
                    },
                    wgpu::BindGroupEntry {
                        binding: 2,
                        resource: output.as_entire_binding(),
                    },
                ],
            });
            let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("face_warp_pass"),
                timestamp_writes: None,
            });
            pass.set_pipeline(&beauty.face_warp);
            pass.set_bind_group(0, &bind_group, &[]);
            pass.dispatch_workgroups((width + 15) / 16, (height + 15) / 16, 1);
            active_is_1 = !active_is_1;
        }

        self.queue.submit(Some(encoder.finish()));

        if let Some(c) = self.cached_buffers.lock().as_mut() {
            c.active_is_1 = active_is_1;
        }

        Ok(())
    }

    /// Apply regional beauty on the persistent pipeline cache (Nexus D + Sprint 22).
    pub(crate) fn apply_beauty_on_cache(
        &self,
        beauty: &BeautyGpuPipelines,
        params: &BeautyParams,
        skin_mask_buf: &wgpu::Buffer,
        eye_mask_buf: Option<&wgpu::Buffer>,
        lip_mask_buf: Option<&wgpu::Buffer>,
        blush_mask_buf: Option<&wgpu::Buffer>,
        teeth_mask_buf: Option<&wgpu::Buffer>,
        under_eye_mask_buf: Option<&wgpu::Buffer>,
        lip_plump_mask_buf: Option<&wgpu::Buffer>,
        lip_center: Option<(f32, f32)>,
    ) -> Result<(), String> {
        let _gpu = super::engine::gpu_op_lock();
        if !params.is_active() {
            return Ok(());
        }

        let (width, height, storage_buf1, storage_buf2, mut active_is_1) = {
            let cache = self.cached_buffers.lock();
            let c = cache
                .as_ref()
                .ok_or("GPU pipeline cache empty — upload first")?;
            (
                c.width,
                c.height,
                c.storage_buf.clone(),
                c.storage_buf2.clone(),
                c.active_is_1,
            )
        };

        let mut encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("beauty_gpu_encoder"),
            });

        let dispatch = |encoder: &mut wgpu::CommandEncoder,
                        pipeline: &wgpu::ComputePipeline,
                        mask_buf: &wgpu::Buffer,
                        label: &str,
                        params_bytes: &[u8],
                        active: bool|
         -> bool {
            let params_buf = self
                .device
                .create_buffer_init(&wgpu::util::BufferInitDescriptor {
                    label: Some("beauty_params"),
                    contents: params_bytes,
                    usage: wgpu::BufferUsages::UNIFORM,
                });
            let (input, output) = if active {
                (&storage_buf1, &storage_buf2)
            } else {
                (&storage_buf2, &storage_buf1)
            };
            let bind_group = self.device.create_bind_group(&wgpu::BindGroupDescriptor {
                label: Some(label),
                layout: &pipeline.get_bind_group_layout(0),
                entries: &[
                    wgpu::BindGroupEntry {
                        binding: 0,
                        resource: params_buf.as_entire_binding(),
                    },
                    wgpu::BindGroupEntry {
                        binding: 1,
                        resource: input.as_entire_binding(),
                    },
                    wgpu::BindGroupEntry {
                        binding: 2,
                        resource: mask_buf.as_entire_binding(),
                    },
                    wgpu::BindGroupEntry {
                        binding: 3,
                        resource: output.as_entire_binding(),
                    },
                ],
            });
            let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some(label),
                timestamp_writes: None,
            });
            pass.set_pipeline(pipeline);
            pass.set_bind_group(0, &bind_group, &[]);
            pass.dispatch_workgroups((width + 15) / 16, (height + 15) / 16, 1);
            !active
        };

        if params.lip_plump > 0.001 {
            if let (Some(lip_buf), Some((cx, cy))) = (lip_plump_mask_buf, lip_center) {
                let p = LipPlumpParams {
                    width,
                    height,
                    strength: params.lip_plump,
                    lip_cx: cx,
                    lip_cy: cy,
                };
                active_is_1 = dispatch(
                    &mut encoder,
                    &beauty.lip_plump,
                    lip_buf,
                    "lip_plump_pass",
                    bytemuck::bytes_of(&p),
                    active_is_1,
                );
            }
        }

        if params.skin_smooth > 0.001 {
            let strength = params.skin_smooth;
            let radius = (1.0 + strength * 3.0).round().max(1.0) as u32;
            let p = SkinSmoothParams {
                width,
                height,
                radius,
                strength,
                preserve_detail: params.skin_preserve_detail,
            };
            let params_buf = self
                .device
                .create_buffer_init(&wgpu::util::BufferInitDescriptor {
                    label: Some("skin_smooth_params"),
                    contents: bytemuck::bytes_of(&p),
                    usage: wgpu::BufferUsages::UNIFORM,
                });

            let (input, temp) = if active_is_1 {
                (&storage_buf1, &storage_buf2)
            } else {
                (&storage_buf2, &storage_buf1)
            };

            // 1. Horizontal Pass
            let bind_group_h = self.device.create_bind_group(&wgpu::BindGroupDescriptor {
                label: Some("skin_smooth_pass_h"),
                layout: &beauty.skin_smooth_h.get_bind_group_layout(0),
                entries: &[
                    wgpu::BindGroupEntry {
                        binding: 0,
                        resource: params_buf.as_entire_binding(),
                    },
                    wgpu::BindGroupEntry {
                        binding: 1,
                        resource: input.as_entire_binding(),
                    },
                    wgpu::BindGroupEntry {
                        binding: 2,
                        resource: temp.as_entire_binding(),
                    },
                ],
            });
            {
                let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                    label: Some("skin_smooth_pass_h"),
                    timestamp_writes: None,
                });
                pass.set_pipeline(&beauty.skin_smooth_h);
                pass.set_bind_group(0, &bind_group_h, &[]);
                pass.dispatch_workgroups((width + 15) / 16, (height + 15) / 16, 1);
            }

            // 2. Vertical Pass and Blend
            let bind_group_v = self.device.create_bind_group(&wgpu::BindGroupDescriptor {
                label: Some("skin_smooth_pass_v"),
                layout: &beauty.skin_smooth_v.get_bind_group_layout(0),
                entries: &[
                    wgpu::BindGroupEntry {
                        binding: 0,
                        resource: params_buf.as_entire_binding(),
                    },
                    wgpu::BindGroupEntry {
                        binding: 1,
                        resource: temp.as_entire_binding(),
                    },
                    wgpu::BindGroupEntry {
                        binding: 2,
                        resource: skin_mask_buf.as_entire_binding(),
                    },
                    wgpu::BindGroupEntry {
                        binding: 3,
                        resource: input.as_entire_binding(),
                    },
                ],
            });
            {
                let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                    label: Some("skin_smooth_pass_v"),
                    timestamp_writes: None,
                });
                pass.set_pipeline(&beauty.skin_smooth_v);
                pass.set_bind_group(0, &bind_group_v, &[]);
                pass.dispatch_workgroups((width + 15) / 16, (height + 15) / 16, 1);
            }
            // active_is_1 remains unchanged after separable pass
        }

        if params.eye_brighten > 0.001 {
            if let Some(eye_buf) = eye_mask_buf {
                let p = EyeBrightenParams {
                    width,
                    height,
                    strength: params.eye_brighten,
                    _pad: 0.0,
                };
                active_is_1 = dispatch(
                    &mut encoder,
                    &beauty.eye_brighten,
                    eye_buf,
                    "eye_brighten_pass",
                    bytemuck::bytes_of(&p),
                    active_is_1,
                );
            }
        }

        if params.lip_tint_strength > 0.001 {
            if let (Some(lip_buf), Some((tr, tg, tb))) =
                (lip_mask_buf, lip_tint_rgb(params.lip_tint))
            {
                let p = LipTintParams {
                    width,
                    height,
                    strength: params.lip_tint_strength,
                    target_r: tr,
                    target_g: tg,
                    target_b: tb,
                };
                active_is_1 = dispatch(
                    &mut encoder,
                    &beauty.lip_tint,
                    lip_buf,
                    "lip_tint_pass",
                    bytemuck::bytes_of(&p),
                    active_is_1,
                );
            }
        }

        if params.blush > 0.001 {
            if let Some(blush_buf) = blush_mask_buf {
                let p = BlushParams {
                    width,
                    height,
                    strength: params.blush,
                    _pad: 0.0,
                };
                active_is_1 = dispatch(
                    &mut encoder,
                    &beauty.blush,
                    blush_buf,
                    "blush_pass",
                    bytemuck::bytes_of(&p),
                    active_is_1,
                );
            }
        }

        if params.under_eye > 0.001 {
            if let Some(ue_buf) = under_eye_mask_buf {
                let p = EyeBrightenParams {
                    width,
                    height,
                    strength: params.under_eye,
                    _pad: 0.0,
                };
                active_is_1 = dispatch(
                    &mut encoder,
                    &beauty.under_eye,
                    ue_buf,
                    "under_eye_pass",
                    bytemuck::bytes_of(&p),
                    active_is_1,
                );
            }
        }

        if params.teeth_whiten > 0.001 {
            if let Some(teeth_buf) = teeth_mask_buf {
                let p = EyeBrightenParams {
                    width,
                    height,
                    strength: params.teeth_whiten,
                    _pad: 0.0,
                };
                active_is_1 = dispatch(
                    &mut encoder,
                    &beauty.teeth_whiten,
                    teeth_buf,
                    "teeth_whiten_pass",
                    bytemuck::bytes_of(&p),
                    active_is_1,
                );
            }
        }

        self.queue.submit(Some(encoder.finish()));

        if let Some(c) = self.cached_buffers.lock().as_mut() {
            c.active_is_1 = active_is_1;
        }

        Ok(())
    }

    /// Apply regional beauty on the persistent pipeline cache AND swizzle
    /// the final result into a BGRA8Unorm storage texture for zero-copy
    /// display via Flutter's `Texture` widget.
    ///
    /// `output_texture` must have been created from a CVPixelBuffer's
    /// IOSurface (i.e. the Flutter display texture). The wgpu texture
    /// borrows the underlying MTLTexture.
    #[allow(clippy::too_many_arguments)]
    pub(crate) fn apply_beauty_on_cache_with_output(
        &self,
        beauty: &BeautyGpuPipelines,
        params: &BeautyParams,
        skin_mask_buf: &wgpu::Buffer,
        eye_mask_buf: Option<&wgpu::Buffer>,
        lip_mask_buf: Option<&wgpu::Buffer>,
        blush_mask_buf: Option<&wgpu::Buffer>,
        teeth_mask_buf: Option<&wgpu::Buffer>,
        under_eye_mask_buf: Option<&wgpu::Buffer>,
        lip_plump_mask_buf: Option<&wgpu::Buffer>,
        lip_center: Option<(f32, f32)>,
        output_texture: &wgpu::Texture,
    ) -> Result<(), String> {
        let _gpu = super::engine::gpu_op_lock();
        if !params.is_active() {
            return Ok(());
        }

        let (width, height, storage_buf1, storage_buf2, mut active_is_1) = {
            let cache = self.cached_buffers.lock();
            let c = cache
                .as_ref()
                .ok_or("GPU pipeline cache empty — upload first")?;
            (
                c.width,
                c.height,
                c.storage_buf.clone(),
                c.storage_buf2.clone(),
                c.active_is_1,
            )
        };

        let mut encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("beauty_gpu_with_output_encoder"),
            });

        let dispatch = |encoder: &mut wgpu::CommandEncoder,
                        pipeline: &wgpu::ComputePipeline,
                        mask_buf: &wgpu::Buffer,
                        label: &str,
                        params_bytes: &[u8],
                        active: bool|
         -> bool {
            let params_buf = self
                .device
                .create_buffer_init(&wgpu::util::BufferInitDescriptor {
                    label: Some("beauty_params"),
                    contents: params_bytes,
                    usage: wgpu::BufferUsages::UNIFORM,
                });
            let (input, output) = if active {
                (&storage_buf1, &storage_buf2)
            } else {
                (&storage_buf2, &storage_buf1)
            };
            let bind_group = self.device.create_bind_group(&wgpu::BindGroupDescriptor {
                label: Some(label),
                layout: &pipeline.get_bind_group_layout(0),
                entries: &[
                    wgpu::BindGroupEntry {
                        binding: 0,
                        resource: params_buf.as_entire_binding(),
                    },
                    wgpu::BindGroupEntry {
                        binding: 1,
                        resource: input.as_entire_binding(),
                    },
                    wgpu::BindGroupEntry {
                        binding: 2,
                        resource: mask_buf.as_entire_binding(),
                    },
                    wgpu::BindGroupEntry {
                        binding: 3,
                        resource: output.as_entire_binding(),
                    },
                ],
            });
            let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some(label),
                timestamp_writes: None,
            });
            pass.set_pipeline(pipeline);
            pass.set_bind_group(0, &bind_group, &[]);
            pass.dispatch_workgroups((width + 15) / 16, (height + 15) / 16, 1);
            !active
        };

        if params.lip_plump > 0.001 {
            if let (Some(lip_buf), Some((cx, cy))) = (lip_plump_mask_buf, lip_center) {
                let p = LipPlumpParams {
                    width,
                    height,
                    strength: params.lip_plump,
                    lip_cx: cx,
                    lip_cy: cy,
                };
                active_is_1 = dispatch(
                    &mut encoder,
                    &beauty.lip_plump,
                    lip_buf,
                    "lip_plump_pass",
                    bytemuck::bytes_of(&p),
                    active_is_1,
                );
            }
        }

        if params.skin_smooth > 0.001 {
            let strength = params.skin_smooth;
            let radius = (1.0 + strength * 3.0).round().max(1.0) as u32;
            let p = SkinSmoothParams {
                width,
                height,
                radius,
                strength,
                preserve_detail: params.skin_preserve_detail,
            };
            let params_buf = self
                .device
                .create_buffer_init(&wgpu::util::BufferInitDescriptor {
                    label: Some("skin_smooth_params"),
                    contents: bytemuck::bytes_of(&p),
                    usage: wgpu::BufferUsages::UNIFORM,
                });

            let (input, temp) = if active_is_1 {
                (&storage_buf1, &storage_buf2)
            } else {
                (&storage_buf2, &storage_buf1)
            };

            let bind_group_h = self.device.create_bind_group(&wgpu::BindGroupDescriptor {
                label: Some("skin_smooth_pass_h"),
                layout: &beauty.skin_smooth_h.get_bind_group_layout(0),
                entries: &[
                    wgpu::BindGroupEntry {
                        binding: 0,
                        resource: params_buf.as_entire_binding(),
                    },
                    wgpu::BindGroupEntry {
                        binding: 1,
                        resource: input.as_entire_binding(),
                    },
                    wgpu::BindGroupEntry {
                        binding: 2,
                        resource: temp.as_entire_binding(),
                    },
                ],
            });
            {
                let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                    label: Some("skin_smooth_pass_h"),
                    timestamp_writes: None,
                });
                pass.set_pipeline(&beauty.skin_smooth_h);
                pass.set_bind_group(0, &bind_group_h, &[]);
                pass.dispatch_workgroups((width + 15) / 16, (height + 15) / 16, 1);
            }

            let bind_group_v = self.device.create_bind_group(&wgpu::BindGroupDescriptor {
                label: Some("skin_smooth_pass_v"),
                layout: &beauty.skin_smooth_v.get_bind_group_layout(0),
                entries: &[
                    wgpu::BindGroupEntry {
                        binding: 0,
                        resource: params_buf.as_entire_binding(),
                    },
                    wgpu::BindGroupEntry {
                        binding: 1,
                        resource: temp.as_entire_binding(),
                    },
                    wgpu::BindGroupEntry {
                        binding: 2,
                        resource: skin_mask_buf.as_entire_binding(),
                    },
                    wgpu::BindGroupEntry {
                        binding: 3,
                        resource: input.as_entire_binding(),
                    },
                ],
            });
            {
                let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                    label: Some("skin_smooth_pass_v"),
                    timestamp_writes: None,
                });
                pass.set_pipeline(&beauty.skin_smooth_v);
                pass.set_bind_group(0, &bind_group_v, &[]);
                pass.dispatch_workgroups((width + 15) / 16, (height + 15) / 16, 1);
            }
        }

        if params.eye_brighten > 0.001 {
            if let Some(eye_buf) = eye_mask_buf {
                let p = EyeBrightenParams {
                    width,
                    height,
                    strength: params.eye_brighten,
                    _pad: 0.0,
                };
                active_is_1 = dispatch(
                    &mut encoder,
                    &beauty.eye_brighten,
                    eye_buf,
                    "eye_brighten_pass",
                    bytemuck::bytes_of(&p),
                    active_is_1,
                );
            }
        }

        if params.lip_tint_strength > 0.001 {
            if let (Some(lip_buf), Some((tr, tg, tb))) =
                (lip_mask_buf, lip_tint_rgb(params.lip_tint))
            {
                let p = LipTintParams {
                    width,
                    height,
                    strength: params.lip_tint_strength,
                    target_r: tr,
                    target_g: tg,
                    target_b: tb,
                };
                active_is_1 = dispatch(
                    &mut encoder,
                    &beauty.lip_tint,
                    lip_buf,
                    "lip_tint_pass",
                    bytemuck::bytes_of(&p),
                    active_is_1,
                );
            }
        }

        if params.blush > 0.001 {
            if let Some(blush_buf) = blush_mask_buf {
                let p = BlushParams {
                    width,
                    height,
                    strength: params.blush,
                    _pad: 0.0,
                };
                active_is_1 = dispatch(
                    &mut encoder,
                    &beauty.blush,
                    blush_buf,
                    "blush_pass",
                    bytemuck::bytes_of(&p),
                    active_is_1,
                );
            }
        }

        if params.under_eye > 0.001 {
            if let Some(ue_buf) = under_eye_mask_buf {
                let p = EyeBrightenParams {
                    width,
                    height,
                    strength: params.under_eye,
                    _pad: 0.0,
                };
                active_is_1 = dispatch(
                    &mut encoder,
                    &beauty.under_eye,
                    ue_buf,
                    "under_eye_pass",
                    bytemuck::bytes_of(&p),
                    active_is_1,
                );
            }
        }

        if params.teeth_whiten > 0.001 {
            if let Some(teeth_buf) = teeth_mask_buf {
                let p = EyeBrightenParams {
                    width,
                    height,
                    strength: params.teeth_whiten,
                    _pad: 0.0,
                };
                active_is_1 = dispatch(
                    &mut encoder,
                    &beauty.teeth_whiten,
                    teeth_buf,
                    "teeth_whiten_pass",
                    bytemuck::bytes_of(&p),
                    active_is_1,
                );
            }
        }

        // Final swizzle: copy the active storage buffer into the output
        // BGRA8Unorm storage texture. The output texture is the IOSurface
        // backing the Flutter display CVPixelBuffer; no CPU readback needed.
        let active_buf = if active_is_1 {
            &storage_buf1
        } else {
            &storage_buf2
        };
        let swizzle_p = SwizzleParams { width, height };
        let swizzle_params_buf =
            self.device
                .create_buffer_init(&wgpu::util::BufferInitDescriptor {
                    label: Some("beauty_output_swizzle_params"),
                    contents: bytemuck::bytes_of(&swizzle_p),
                    usage: wgpu::BufferUsages::UNIFORM,
                });
        let swizzle_bind_group = self.device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("beauty_output_swizzle_pass"),
            layout: &beauty.output_swizzle.get_bind_group_layout(0),
            entries: &[
                wgpu::BindGroupEntry {
                    binding: 0,
                    resource: swizzle_params_buf.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 1,
                    resource: active_buf.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 2,
                    resource: wgpu::BindingResource::TextureView(
                        &output_texture.create_view(&wgpu::TextureViewDescriptor::default()),
                    ),
                },
            ],
        });
        {
            let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("beauty_output_swizzle_pass"),
                timestamp_writes: None,
            });
            pass.set_pipeline(&beauty.output_swizzle);
            pass.set_bind_group(0, &swizzle_bind_group, &[]);
            pass.dispatch_workgroups((width + 15) / 16, (height + 15) / 16, 1);
        }

        self.queue.submit(Some(encoder.finish()));

        if let Some(c) = self.cached_buffers.lock().as_mut() {
            c.active_is_1 = active_is_1;
        }

        Ok(())
    }
}
