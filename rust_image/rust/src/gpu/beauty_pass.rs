//! Nexus D — GPU regional beauty passes on the pipeline cache (no CPU readback).

use bytemuck::{Pod, Zeroable};
use wgpu::util::DeviceExt;

use crate::api::face::{BeautyParams, LipTintPreset, SegmentationMask};
use crate::face::apply_exclude_mask;

use super::engine::GpuEngine;

const SKIN_SMOOTH_SHADER: &str = include_str!("shaders/skin_smooth.wgsl");
const EYE_BRIGHTEN_SHADER: &str = include_str!("shaders/eye_brighten.wgsl");
const LIP_TINT_SHADER: &str = include_str!("shaders/lip_tint.wgsl");
const BLUSH_SHADER: &str = include_str!("shaders/blush.wgsl");

#[repr(C)]
#[derive(Clone, Copy, Pod, Zeroable)]
struct SkinSmoothParams {
    width: u32,
    height: u32,
    radius: u32,
    strength: f32,
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

pub(crate) struct BeautyGpuPipelines {
    pub skin_smooth: wgpu::ComputePipeline,
    pub eye_brighten: wgpu::ComputePipeline,
    pub lip_tint: wgpu::ComputePipeline,
    pub blush: wgpu::ComputePipeline,
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
            skin_smooth: mk("skin_smooth_pipeline", SKIN_SMOOTH_SHADER),
            eye_brighten: mk("eye_brighten_pipeline", EYE_BRIGHTEN_SHADER),
            lip_tint: mk("lip_tint_pipeline", LIP_TINT_SHADER),
            blush: mk("blush_pipeline", BLUSH_SHADER),
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

fn pack_mask_r8(pixels: &[u8]) -> Vec<u32> {
    pixels.iter().map(|&p| p as u32).collect()
}

impl GpuEngine {
    /// Apply regional beauty on the persistent pipeline cache (Nexus D).
    pub fn apply_beauty_on_cache(
        &self,
        beauty: &BeautyGpuPipelines,
        params: &BeautyParams,
        skin_mask: &SegmentationMask,
        eye_mask: Option<&SegmentationMask>,
        lip_mask: Option<&SegmentationMask>,
        blush_mask: Option<&SegmentationMask>,
        exclude: Option<&SegmentationMask>,
    ) -> Result<(), String> {
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

        let mut encoder = self.device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("beauty_gpu_encoder"),
        });

        let mut dispatch = |encoder: &mut wgpu::CommandEncoder,
                            pipeline: &wgpu::ComputePipeline,
                            mask: &SegmentationMask,
                            label: &str,
                            params_bytes: &[u8],
                            active: bool|
         -> bool {
            let effective = apply_exclude_mask(mask, exclude);
            let mask_packed = pack_mask_r8(&effective.pixels);
            let mask_buf = self.device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
                label: Some("beauty_mask"),
                contents: bytemuck::cast_slice(&mask_packed),
                usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST,
            });
            let params_buf = self.device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
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

        if params.skin_smooth > 0.001 {
            let strength = params.skin_smooth;
            let radius = (1.0 + strength * 3.0).round().max(1.0) as u32;
            let p = SkinSmoothParams {
                width,
                height,
                radius,
                strength,
            };
            active_is_1 = dispatch(
                &mut encoder,
                &beauty.skin_smooth,
                skin_mask,
                "skin_smooth_pass",
                bytemuck::bytes_of(&p),
                active_is_1,
            );
        }

        if params.eye_brighten > 0.001 {
            if let Some(eye) = eye_mask {
                let p = EyeBrightenParams {
                    width,
                    height,
                    strength: params.eye_brighten,
                    _pad: 0.0,
                };
                active_is_1 = dispatch(
                    &mut encoder,
                    &beauty.eye_brighten,
                    eye,
                    "eye_brighten_pass",
                    bytemuck::bytes_of(&p),
                    active_is_1,
                );
            }
        }

        if params.lip_tint_strength > 0.001 {
            if let (Some(lip), Some((tr, tg, tb))) =
                (lip_mask, lip_tint_rgb(params.lip_tint))
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
                    lip,
                    "lip_tint_pass",
                    bytemuck::bytes_of(&p),
                    active_is_1,
                );
            }
        }

        if params.blush > 0.001 {
            if let Some(blush) = blush_mask {
                let p = BlushParams {
                    width,
                    height,
                    strength: params.blush,
                    _pad: 0.0,
                };
                active_is_1 = dispatch(
                    &mut encoder,
                    &beauty.blush,
                    blush,
                    "blush_pass",
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
}
