//! Sprint 2 P2 — GPU overlay composite on pipeline cache (normal / multiply / screen).

use bytemuck::{Pod, Zeroable};
use wgpu::util::DeviceExt;

use crate::api::image::RgbaImageBuffer;

use super::engine::GpuEngine;

const OVERLAY_SHADER: &str = include_str!("shaders/overlay_composite.wgsl");

#[repr(C)]
#[derive(Clone, Copy, Pod, Zeroable)]
struct OverlayParams {
    width: u32,
    height: u32,
    opacity: f32,
    blend_mode: u32,
    _pad: u32,
}

pub fn composite_overlay_on_cache(
    gpu: &GpuEngine,
    overlay: &RgbaImageBuffer,
    opacity: f32,
    blend_mode: u32,
) -> Result<(), String> {
    let _gpu = super::engine::gpu_op_lock();
    let (width, height, storage_buf1, storage_buf2, active_is_1) = {
        let cache = gpu.cached_buffers.lock();
        let c = cache
            .as_ref()
            .ok_or("GPU pipeline cache empty — upload first")?;
        if c.width != overlay.width || c.height != overlay.height {
            return Err("overlay size mismatch".into());
        }
        (
            c.width,
            c.height,
            c.storage_buf.clone(),
            c.storage_buf2.clone(),
            c.active_is_1,
        )
    };

    let packed: Vec<u32> = overlay
        .pixels
        .chunks_exact(4)
        .map(|p| u32::from_le_bytes([p[0], p[1], p[2], p[3]]))
        .collect();

    let overlay_buf = gpu
        .device
        .create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some("overlay_rgba"),
            contents: bytemuck::cast_slice(&packed),
            usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST,
        });

    let params = OverlayParams {
        width,
        height,
        opacity: opacity.clamp(0.0, 1.0),
        blend_mode,
        _pad: 0,
    };
    let params_buf = gpu
        .device
        .create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some("overlay_params"),
            contents: bytemuck::bytes_of(&params),
            usage: wgpu::BufferUsages::UNIFORM,
        });

    let shader = gpu
        .device
        .create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("overlay_composite_shader"),
            source: wgpu::ShaderSource::Wgsl(OVERLAY_SHADER.into()),
        });
    let pipeline = gpu
        .device
        .create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
            label: Some("overlay_composite_pipeline"),
            layout: None,
            module: &shader,
            entry_point: Some("main"),
            compilation_options: Default::default(),
            cache: None,
        });

    let (input, output) = if active_is_1 {
        (&storage_buf1, &storage_buf2)
    } else {
        (&storage_buf2, &storage_buf1)
    };

    let bind_group = gpu.device.create_bind_group(&wgpu::BindGroupDescriptor {
        label: Some("overlay_bind"),
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
                resource: overlay_buf.as_entire_binding(),
            },
            wgpu::BindGroupEntry {
                binding: 3,
                resource: output.as_entire_binding(),
            },
        ],
    });

    let mut encoder = gpu
        .device
        .create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("overlay_composite_encoder"),
        });
    {
        let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("overlay_composite_pass"),
            timestamp_writes: None,
        });
        pass.set_pipeline(&pipeline);
        pass.set_bind_group(0, &bind_group, &[]);
        pass.dispatch_workgroups((width + 15) / 16, (height + 15) / 16, 1);
    }
    gpu.queue.submit(Some(encoder.finish()));

    if let Some(c) = gpu.cached_buffers.lock().as_mut() {
        c.active_is_1 = !active_is_1;
    }
    Ok(())
}
