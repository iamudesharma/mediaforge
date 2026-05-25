use std::sync::OnceLock;

use bytemuck::{Pod, Zeroable};
use wgpu::util::DeviceExt;

use crate::api::image::{ImageFilter, ResizeAlgorithm, RgbaImageBuffer};

const RESIZE_SHADER: &str = include_str!("shaders/resize.wgsl");
const COLOR_SHADER: &str = include_str!("shaders/color_adjust.wgsl");
const BLUR_SHADER: &str = include_str!("shaders/blur.wgsl");
const SHARPEN_SHADER: &str = include_str!("shaders/sharpen.wgsl");

#[repr(C)]
#[derive(Clone, Copy, Pod, Zeroable)]
struct ResizeParams {
    src_width: u32,
    src_height: u32,
    dst_width: u32,
    dst_height: u32,
    filter_nearest: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Pod, Zeroable)]
struct ColorParams {
    width: u32,
    height: u32,
    brightness: f32,
    contrast: f32,
    saturation: f32,
    hue_degrees: f32,
}

#[repr(C)]
#[derive(Clone, Copy, Pod, Zeroable)]
struct SharpenParams {
    width: u32,
    height: u32,
    strength: f32,
}

#[repr(C)]
#[derive(Clone, Copy, Pod, Zeroable)]
struct BlurParams {
    width: u32,
    height: u32,
    radius: u32,
    dir_x: i32,
    dir_y: i32,
}

struct CachedGpuBuffers {
    width: u32,
    height: u32,
    storage_buf: wgpu::Buffer,
    storage_buf2: wgpu::Buffer,
    readback_buf: wgpu::Buffer,
}

struct CachedResizeBuffers {
    src_width: u32,
    src_height: u32,
    dst_width: u32,
    dst_height: u32,
    src_buf: wgpu::Buffer,
    dst_buf: wgpu::Buffer,
    readback_buf: wgpu::Buffer,
}

pub struct GpuEngine {
    pub api_name: String,
    pub device_name: String,
    device: wgpu::Device,
    queue: wgpu::Queue,
    resize_pipeline: wgpu::ComputePipeline,
    color_pipeline: wgpu::ComputePipeline,
    blur_pipeline: wgpu::ComputePipeline,
    sharpen_pipeline: wgpu::ComputePipeline,
    cached_buffers: parking_lot::Mutex<Option<CachedGpuBuffers>>,
    resize_cache: parking_lot::Mutex<Option<CachedResizeBuffers>>,
}

static ENGINE: OnceLock<Result<GpuEngine, String>> = OnceLock::new();

pub fn engine() -> Result<&'static GpuEngine, String> {
    ENGINE
        .get_or_init(GpuEngine::try_new)
        .as_ref()
        .map_err(|e| e.clone())
}

pub fn is_available() -> bool {
    engine().is_ok()
}

pub fn capabilities() -> (bool, String, String) {
    match engine() {
        Ok(e) => (true, e.api_name.clone(), e.device_name.clone()),
        Err(_) => (false, String::new(), String::new()),
    }
}

impl GpuEngine {
    fn try_new() -> Result<Self, String> {
        pollster::block_on(Self::init_async())
    }

    async fn init_async() -> Result<Self, String> {
        let instance_desc = wgpu::InstanceDescriptor {
            backends: wgpu::Backends::all(),
            ..Default::default()
        };
        let instance = wgpu::Instance::new(&instance_desc);

        let adapter = instance
            .request_adapter(&wgpu::RequestAdapterOptions {
                power_preference: wgpu::PowerPreference::HighPerformance,
                compatible_surface: None,
                force_fallback_adapter: false,
            })
            .await
            .ok_or_else(|| "no GPU adapter found (Metal/Vulkan/DX12)".to_string())?;

        let info = adapter.get_info();
        let api_name = backend_label(info.backend).to_string();
        let device_name = info.name.clone();

        let (device, queue) = adapter
            .request_device(
                &wgpu::DeviceDescriptor {
                    label: Some("rust_image_gpu"),
                    required_features: wgpu::Features::empty(),
                    required_limits: wgpu::Limits::default(),
                    memory_hints: wgpu::MemoryHints::Performance,
                },
                None,
            )
            .await
            .map_err(|e| format!("GPU device request failed: {e}"))?;

        let resize_shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("resize_shader"),
            source: wgpu::ShaderSource::Wgsl(RESIZE_SHADER.into()),
        });
        let color_shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("color_shader"),
            source: wgpu::ShaderSource::Wgsl(COLOR_SHADER.into()),
        });
        let blur_shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("blur_shader"),
            source: wgpu::ShaderSource::Wgsl(BLUR_SHADER.into()),
        });
        let sharpen_shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("sharpen_shader"),
            source: wgpu::ShaderSource::Wgsl(SHARPEN_SHADER.into()),
        });

        let resize_pipeline = device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
            label: Some("resize_pipeline"),
            layout: None,
            module: &resize_shader,
            entry_point: Some("main"),
            compilation_options: Default::default(),
            cache: None,
        });

        let color_pipeline = device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
            label: Some("color_pipeline"),
            layout: None,
            module: &color_shader,
            entry_point: Some("main"),
            compilation_options: Default::default(),
            cache: None,
        });

        let blur_pipeline = device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
            label: Some("blur_pipeline"),
            layout: None,
            module: &blur_shader,
            entry_point: Some("main"),
            compilation_options: Default::default(),
            cache: None,
        });

        let sharpen_pipeline = device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
            label: Some("sharpen_pipeline"),
            layout: None,
            module: &sharpen_shader,
            entry_point: Some("main"),
            compilation_options: Default::default(),
            cache: None,
        });

        Ok(Self {
            api_name,
            device_name,
            device,
            queue,
            resize_pipeline,
            color_pipeline,
            blur_pipeline,
            sharpen_pipeline,
            cached_buffers: parking_lot::Mutex::new(None),
            resize_cache: parking_lot::Mutex::new(None),
        })
    }

    pub fn resize_rgba(
        &self,
        buffer: RgbaImageBuffer,
        width: u32,
        height: u32,
        algorithm: ResizeAlgorithm,
    ) -> Result<RgbaImageBuffer, String> {
        if width == 0 || height == 0 {
            return Err("width and height must be greater than zero".into());
        }
        if buffer.width == width && buffer.height == height {
            return Ok(buffer);
        }

        let src_packed = pack_pixels(&buffer.pixels);
        let dst_len = (width as usize) * (height as usize);

        let params = ResizeParams {
            src_width: buffer.width,
            src_height: buffer.height,
            dst_width: width,
            dst_height: height,
            filter_nearest: if matches!(algorithm, ResizeAlgorithm::Nearest) {
                1
            } else {
                0
            },
        };

        let mut resize_guard = self.resize_cache.lock();
        let cache_hit = resize_guard.as_ref().is_some_and(|c| {
            c.src_width == buffer.width
                && c.src_height == buffer.height
                && c.dst_width == width
                && c.dst_height == height
        });

        let (src_buf, dst_buf, readback_buf) = if cache_hit {
            let cache = resize_guard.as_ref().unwrap();
            self.queue
                .write_buffer(&cache.src_buf, 0, bytemuck::cast_slice(&src_packed));
            (
                cache.src_buf.clone(),
                cache.dst_buf.clone(),
                cache.readback_buf.clone(),
            )
        } else {
            let src_buf = self
                .device
                .create_buffer_init(&wgpu::util::BufferInitDescriptor {
                    label: Some("resize_src"),
                    contents: bytemuck::cast_slice(&src_packed),
                    usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST,
                });

            let dst_buf = self.device.create_buffer(&wgpu::BufferDescriptor {
                label: Some("resize_dst"),
                size: (dst_len * std::mem::size_of::<u32>()) as u64,
                usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
                mapped_at_creation: false,
            });

            let readback_buf = self.device.create_buffer(&wgpu::BufferDescriptor {
                label: Some("resize_readback"),
                size: (dst_len * std::mem::size_of::<u32>()) as u64,
                usage: wgpu::BufferUsages::MAP_READ | wgpu::BufferUsages::COPY_DST,
                mapped_at_creation: false,
            });

            *resize_guard = Some(CachedResizeBuffers {
                src_width: buffer.width,
                src_height: buffer.height,
                dst_width: width,
                dst_height: height,
                src_buf: src_buf.clone(),
                dst_buf: dst_buf.clone(),
                readback_buf: readback_buf.clone(),
            });

            (src_buf, dst_buf, readback_buf)
        };
        drop(resize_guard);

        let params_buf = self
            .device
            .create_buffer_init(&wgpu::util::BufferInitDescriptor {
                label: Some("resize_params"),
                contents: bytemuck::bytes_of(&params),
                usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            });

        let bind_group = self.device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("resize_bind_group"),
            layout: &self.resize_pipeline.get_bind_group_layout(0),
            entries: &[
                wgpu::BindGroupEntry {
                    binding: 0,
                    resource: params_buf.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 1,
                    resource: src_buf.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 2,
                    resource: dst_buf.as_entire_binding(),
                },
            ],
        });

        let mut encoder =
            self.device
                .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                    label: Some("resize_encoder"),
                });

        {
            let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("resize_pass"),
                timestamp_writes: None,
            });
            pass.set_pipeline(&self.resize_pipeline);
            pass.set_bind_group(0, &bind_group, &[]);
            let groups_x = (width + 15) / 16;
            let groups_y = (height + 15) / 16;
            pass.dispatch_workgroups(groups_x, groups_y, 1);
        }

        encoder.copy_buffer_to_buffer(
            &dst_buf,
            0,
            &readback_buf,
            0,
            (dst_len * std::mem::size_of::<u32>()) as u64,
        );

        self.queue.submit(Some(encoder.finish()));
        let packed = self.map_read_u32(&readback_buf, dst_len)?;
        crate::pool::release_buffer(buffer.pixels);
        let pixels = unpack_pixels(&packed, dst_len);
        Ok(RgbaImageBuffer {
            width,
            height,
            pixels,
        })
    }

    pub fn color_adjust_rgba(
        &self,
        mut buffer: RgbaImageBuffer,
        brightness: f32,
        contrast: f32,
        saturation: f32,
        hue_degrees: f32,
    ) -> Result<RgbaImageBuffer, String> {
        let (width, height) = (buffer.width, buffer.height);
        let len = (width as usize) * (height as usize);
        let packed = pack_pixels(&buffer.pixels);

        let params = ColorParams {
            width,
            height,
            brightness,
            contrast,
            saturation,
            hue_degrees,
        };

        let mut cache_guard = self.cached_buffers.lock();
        let use_cache = cache_guard
            .as_ref()
            .is_some_and(|cache| cache.width == width && cache.height == height);

        let (buf, readback_buf) = if use_cache {
            let cache = cache_guard.as_ref().unwrap();
            self.queue.write_buffer(&cache.storage_buf, 0, bytemuck::cast_slice(&packed));
            (cache.storage_buf.clone(), cache.readback_buf.clone())
        } else {
            let new_storage_buf = self.device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
                label: Some("color_rgba"),
                contents: bytemuck::cast_slice(&packed),
                usage: wgpu::BufferUsages::STORAGE
                    | wgpu::BufferUsages::COPY_DST
                    | wgpu::BufferUsages::COPY_SRC,
            });

            let new_storage_buf2 = self.device.create_buffer(&wgpu::BufferDescriptor {
                label: Some("color_rgba_buf2"),
                size: (len * std::mem::size_of::<u32>()) as u64,
                usage: wgpu::BufferUsages::STORAGE
                    | wgpu::BufferUsages::COPY_DST
                    | wgpu::BufferUsages::COPY_SRC,
                mapped_at_creation: false,
            });

            let new_readback_buf = self.device.create_buffer(&wgpu::BufferDescriptor {
                label: Some("color_readback"),
                size: (len * std::mem::size_of::<u32>()) as u64,
                usage: wgpu::BufferUsages::MAP_READ | wgpu::BufferUsages::COPY_DST,
                mapped_at_creation: false,
            });

            let storage = new_storage_buf.clone();
            let readback = new_readback_buf.clone();

            *cache_guard = Some(CachedGpuBuffers {
                width,
                height,
                storage_buf: new_storage_buf,
                storage_buf2: new_storage_buf2,
                readback_buf: new_readback_buf,
            });

            (storage, readback)
        };

        // We can drop the guard now that we've cloned the buffer handles
        drop(cache_guard);

        let params_buf = self
            .device
            .create_buffer_init(&wgpu::util::BufferInitDescriptor {
                label: Some("color_params"),
                contents: bytemuck::bytes_of(&params),
                usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            });

        let bind_group = self.device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("color_bind_group"),
            layout: &self.color_pipeline.get_bind_group_layout(0),
            entries: &[
                wgpu::BindGroupEntry {
                    binding: 0,
                    resource: params_buf.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 1,
                    resource: buf.as_entire_binding(),
                },
            ],
        });

        let mut encoder =
            self.device
                .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                    label: Some("color_encoder"),
                });

        {
            let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("color_pass"),
                timestamp_writes: None,
            });
            pass.set_pipeline(&self.color_pipeline);
            pass.set_bind_group(0, &bind_group, &[]);
            let groups_x = (width + 15) / 16;
            let groups_y = (height + 15) / 16;
            pass.dispatch_workgroups(groups_x, groups_y, 1);
        }

        encoder.copy_buffer_to_buffer(
            &buf,
            0,
            &readback_buf,
            0,
            (len * std::mem::size_of::<u32>()) as u64,
        );

        self.queue.submit(Some(encoder.finish()));
        let packed = self.map_read_u32(&readback_buf, len)?;
        buffer.pixels = unpack_pixels(&packed, len);
        Ok(buffer)
    }

    pub fn blur_rgba(
        &self,
        mut buffer: RgbaImageBuffer,
        radius: u32,
    ) -> Result<RgbaImageBuffer, String> {
        let (width, height) = (buffer.width, buffer.height);
        let len = (width as usize) * (height as usize);
        let packed = pack_pixels(&buffer.pixels);

        let mut cache_guard = self.cached_buffers.lock();
        let use_cache = if let Some(ref cache) = *cache_guard {
            cache.width == width && cache.height == height
        } else {
            false
        };

        let (storage_buf1, storage_buf2, readback_buf) = if use_cache {
            let cache = cache_guard.as_ref().unwrap();
            self.queue.write_buffer(&cache.storage_buf, 0, bytemuck::cast_slice(&packed));
            (cache.storage_buf.clone(), cache.storage_buf2.clone(), cache.readback_buf.clone())
        } else {
            let new_storage_buf1 = self.device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
                label: Some("blur_storage1"),
                contents: bytemuck::cast_slice(&packed),
                usage: wgpu::BufferUsages::STORAGE
                    | wgpu::BufferUsages::COPY_DST
                    | wgpu::BufferUsages::COPY_SRC,
            });

            let new_storage_buf2 = self.device.create_buffer(&wgpu::BufferDescriptor {
                label: Some("blur_storage2"),
                size: (len * std::mem::size_of::<u32>()) as u64,
                usage: wgpu::BufferUsages::STORAGE
                    | wgpu::BufferUsages::COPY_DST
                    | wgpu::BufferUsages::COPY_SRC,
                mapped_at_creation: false,
            });

            let new_readback_buf = self.device.create_buffer(&wgpu::BufferDescriptor {
                label: Some("blur_readback"),
                size: (len * std::mem::size_of::<u32>()) as u64,
                usage: wgpu::BufferUsages::MAP_READ | wgpu::BufferUsages::COPY_DST,
                mapped_at_creation: false,
            });

            let storage1 = new_storage_buf1.clone();
            let storage2 = new_storage_buf2.clone();
            let readback = new_readback_buf.clone();

            *cache_guard = Some(CachedGpuBuffers {
                width,
                height,
                storage_buf: new_storage_buf1,
                storage_buf2: new_storage_buf2,
                readback_buf: new_readback_buf,
            });

            (storage1, storage2, readback)
        };

        drop(cache_guard);

        let params_h = BlurParams {
            width,
            height,
            radius,
            dir_x: 1,
            dir_y: 0,
        };
        let params_buf_h = self.device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some("blur_params_h"),
            contents: bytemuck::bytes_of(&params_h),
            usage: wgpu::BufferUsages::UNIFORM,
        });

        let bind_group_h = self.device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("blur_bind_group_h"),
            layout: &self.blur_pipeline.get_bind_group_layout(0),
            entries: &[
                wgpu::BindGroupEntry {
                    binding: 0,
                    resource: params_buf_h.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 1,
                    resource: storage_buf1.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 2,
                    resource: storage_buf2.as_entire_binding(),
                },
            ],
        });

        let params_v = BlurParams {
            width,
            height,
            radius,
            dir_x: 0,
            dir_y: 1,
        };
        let params_buf_v = self.device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some("blur_params_v"),
            contents: bytemuck::bytes_of(&params_v),
            usage: wgpu::BufferUsages::UNIFORM,
        });

        let bind_group_v = self.device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("blur_bind_group_v"),
            layout: &self.blur_pipeline.get_bind_group_layout(0),
            entries: &[
                wgpu::BindGroupEntry {
                    binding: 0,
                    resource: params_buf_v.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 1,
                    resource: storage_buf2.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 2,
                    resource: storage_buf1.as_entire_binding(),
                },
            ],
        });

        let mut encoder = self.device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("blur_encoder"),
        });

        {
            let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("blur_pass_h"),
                timestamp_writes: None,
            });
            pass.set_pipeline(&self.blur_pipeline);
            pass.set_bind_group(0, &bind_group_h, &[]);
            let groups_x = (width + 15) / 16;
            let groups_y = (height + 15) / 16;
            pass.dispatch_workgroups(groups_x, groups_y, 1);
        }

        {
            let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("blur_pass_v"),
                timestamp_writes: None,
            });
            pass.set_pipeline(&self.blur_pipeline);
            pass.set_bind_group(0, &bind_group_v, &[]);
            let groups_x = (width + 15) / 16;
            let groups_y = (height + 15) / 16;
            pass.dispatch_workgroups(groups_x, groups_y, 1);
        }

        encoder.copy_buffer_to_buffer(
            &storage_buf1,
            0,
            &readback_buf,
            0,
            (len * std::mem::size_of::<u32>()) as u64,
        );

        self.queue.submit(Some(encoder.finish()));
        let packed = self.map_read_u32(&readback_buf, len)?;
        buffer.pixels = unpack_pixels(&packed, len);
        Ok(buffer)
    }

    pub fn sharpen_rgba(
        &self,
        mut buffer: RgbaImageBuffer,
        strength: f32,
    ) -> Result<RgbaImageBuffer, String> {
        let (width, height) = (buffer.width, buffer.height);
        let len = (width as usize) * (height as usize);
        let packed = pack_pixels(&buffer.pixels);

        let mut cache_guard = self.cached_buffers.lock();
        let use_cache = cache_guard
            .as_ref()
            .is_some_and(|cache| cache.width == width && cache.height == height);

        let (storage_buf1, storage_buf2, readback_buf) = if use_cache {
            let cache = cache_guard.as_ref().unwrap();
            self.queue
                .write_buffer(&cache.storage_buf, 0, bytemuck::cast_slice(&packed));
            (
                cache.storage_buf.clone(),
                cache.storage_buf2.clone(),
                cache.readback_buf.clone(),
            )
        } else {
            let new_storage_buf1 = self.device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
                label: Some("sharpen_storage1"),
                contents: bytemuck::cast_slice(&packed),
                usage: wgpu::BufferUsages::STORAGE
                    | wgpu::BufferUsages::COPY_DST
                    | wgpu::BufferUsages::COPY_SRC,
            });

            let new_storage_buf2 = self.device.create_buffer(&wgpu::BufferDescriptor {
                label: Some("sharpen_storage2"),
                size: (len * std::mem::size_of::<u32>()) as u64,
                usage: wgpu::BufferUsages::STORAGE
                    | wgpu::BufferUsages::COPY_DST
                    | wgpu::BufferUsages::COPY_SRC,
                mapped_at_creation: false,
            });

            let new_readback_buf = self.device.create_buffer(&wgpu::BufferDescriptor {
                label: Some("sharpen_readback"),
                size: (len * std::mem::size_of::<u32>()) as u64,
                usage: wgpu::BufferUsages::MAP_READ | wgpu::BufferUsages::COPY_DST,
                mapped_at_creation: false,
            });

            let storage1 = new_storage_buf1.clone();
            let storage2 = new_storage_buf2.clone();
            let readback = new_readback_buf.clone();

            *cache_guard = Some(CachedGpuBuffers {
                width,
                height,
                storage_buf: new_storage_buf1,
                storage_buf2: new_storage_buf2,
                readback_buf: new_readback_buf,
            });

            (storage1, storage2, readback)
        };
        drop(cache_guard);

        let params = SharpenParams {
            width,
            height,
            strength,
        };
        let params_buf = self.device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some("sharpen_params"),
            contents: bytemuck::bytes_of(&params),
            usage: wgpu::BufferUsages::UNIFORM,
        });

        let bind_group = self.device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("sharpen_bind_group"),
            layout: &self.sharpen_pipeline.get_bind_group_layout(0),
            entries: &[
                wgpu::BindGroupEntry {
                    binding: 0,
                    resource: params_buf.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 1,
                    resource: storage_buf1.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 2,
                    resource: storage_buf2.as_entire_binding(),
                },
            ],
        });

        let mut encoder = self.device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("sharpen_encoder"),
        });

        {
            let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("sharpen_pass"),
                timestamp_writes: None,
            });
            pass.set_pipeline(&self.sharpen_pipeline);
            pass.set_bind_group(0, &bind_group, &[]);
            let groups_x = (width + 15) / 16;
            let groups_y = (height + 15) / 16;
            pass.dispatch_workgroups(groups_x, groups_y, 1);
        }

        encoder.copy_buffer_to_buffer(
            &storage_buf2,
            0,
            &readback_buf,
            0,
            (len * std::mem::size_of::<u32>()) as u64,
        );

        self.queue.submit(Some(encoder.finish()));
        let packed = self.map_read_u32(&readback_buf, len)?;
        buffer.pixels = unpack_pixels(&packed, len);
        Ok(buffer)
    }

    pub fn apply_filter_rgba(
        &self,
        buffer: RgbaImageBuffer,
        filter: &ImageFilter,
    ) -> Result<RgbaImageBuffer, String> {
        match filter {
            ImageFilter::Brightness { amount } => {
                let b = (*amount as f32) / 255.0;
                self.color_adjust_rgba(buffer, b, 1.0, 1.0, 0.0)
            }
            ImageFilter::Contrast { amount } => {
                self.color_adjust_rgba(buffer, 0.0, *amount, 1.0, 0.0)
            }
            ImageFilter::Saturation { amount } => {
                self.color_adjust_rgba(buffer, 0.0, 1.0, *amount, 0.0)
            }
            ImageFilter::HueRotate { degrees } => {
                self.color_adjust_rgba(buffer, 0.0, 1.0, 1.0, *degrees)
            }
            ImageFilter::Blur { radius } => {
                self.blur_rgba(buffer, *radius as u32)
            }
            ImageFilter::Sharpen => self.sharpen_rgba(buffer, 1.0),
            _ => Err(
                "this filter is not implemented on GPU; use CPU backend or simpler adjustments"
                    .into(),
            ),
        }
    }

    pub fn process_gpu_pipeline(
        &self,
        mut buffer: RgbaImageBuffer,
        ops: &[crate::api::image::EditOp],
    ) -> Result<RgbaImageBuffer, String> {
        if ops.is_empty() {
            return Ok(buffer);
        }

        let (mut width, mut height) = (buffer.width, buffer.height);
        let mut len = (width as usize) * (height as usize);
        let packed = pack_pixels(&buffer.pixels);

        let mut cache_guard = self.cached_buffers.lock();
        let use_cache = if let Some(ref cache) = *cache_guard {
            cache.width == width && cache.height == height
        } else {
            false
        };

        let (mut storage_buf1, mut storage_buf2, mut readback_buf) = if use_cache {
            let cache = cache_guard.as_ref().unwrap();
            self.queue.write_buffer(&cache.storage_buf, 0, bytemuck::cast_slice(&packed));
            (cache.storage_buf.clone(), cache.storage_buf2.clone(), cache.readback_buf.clone())
        } else {
            let new_storage_buf1 = self.device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
                label: Some("pipeline_storage1"),
                contents: bytemuck::cast_slice(&packed),
                usage: wgpu::BufferUsages::STORAGE
                    | wgpu::BufferUsages::COPY_DST
                    | wgpu::BufferUsages::COPY_SRC,
            });

            let new_storage_buf2 = self.device.create_buffer(&wgpu::BufferDescriptor {
                label: Some("pipeline_storage2"),
                size: (len * std::mem::size_of::<u32>()) as u64,
                usage: wgpu::BufferUsages::STORAGE
                    | wgpu::BufferUsages::COPY_DST
                    | wgpu::BufferUsages::COPY_SRC,
                mapped_at_creation: false,
            });

            let new_readback_buf = self.device.create_buffer(&wgpu::BufferDescriptor {
                label: Some("pipeline_readback"),
                size: (len * std::mem::size_of::<u32>()) as u64,
                usage: wgpu::BufferUsages::MAP_READ | wgpu::BufferUsages::COPY_DST,
                mapped_at_creation: false,
            });

            let storage1 = new_storage_buf1.clone();
            let storage2 = new_storage_buf2.clone();
            let readback = new_readback_buf.clone();

            *cache_guard = Some(CachedGpuBuffers {
                width,
                height,
                storage_buf: new_storage_buf1,
                storage_buf2: new_storage_buf2,
                readback_buf: new_readback_buf,
            });

            (storage1, storage2, readback)
        };

        drop(cache_guard);

        let mut active_is_1 = true;
        let mut encoder = self.device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("pipeline_encoder"),
        });

        for op in ops {
            match op {
                crate::api::image::EditOp::Filter { filter } => {
                    match filter {
                        ImageFilter::Brightness { amount } => {
                            let b = (*amount as f32) / 255.0;
                            let current_buf = if active_is_1 { &storage_buf1 } else { &storage_buf2 };
                            self.dispatch_color_adjust(
                                &mut encoder, current_buf, width, height, b, 1.0, 1.0, 0.0,
                            );
                        }
                        ImageFilter::Contrast { amount } => {
                            let c = *amount as f32;
                            let current_buf = if active_is_1 { &storage_buf1 } else { &storage_buf2 };
                            self.dispatch_color_adjust(
                                &mut encoder, current_buf, width, height, 0.0, c, 1.0, 0.0,
                            );
                        }
                        ImageFilter::Saturation { amount } => {
                            let s = *amount as f32;
                            let current_buf = if active_is_1 { &storage_buf1 } else { &storage_buf2 };
                            self.dispatch_color_adjust(
                                &mut encoder, current_buf, width, height, 0.0, 1.0, s, 0.0,
                            );
                        }
                        ImageFilter::HueRotate { degrees } => {
                            let current_buf = if active_is_1 { &storage_buf1 } else { &storage_buf2 };
                            self.dispatch_color_adjust(
                                &mut encoder, current_buf, width, height, 0.0, 1.0, 1.0, *degrees,
                            );
                        }
                        ImageFilter::Sharpen => {
                            let params = SharpenParams {
                                width,
                                height,
                                strength: 1.0,
                            };
                            let params_buf = self.device.create_buffer_init(
                                &wgpu::util::BufferInitDescriptor {
                                    label: Some("pipeline_sharpen_params"),
                                    contents: bytemuck::bytes_of(&params),
                                    usage: wgpu::BufferUsages::UNIFORM,
                                },
                            );
                            let current_buf = if active_is_1 { &storage_buf1 } else { &storage_buf2 };
                            let next_buf = if active_is_1 { &storage_buf2 } else { &storage_buf1 };
                            let bind_group = self.device.create_bind_group(&wgpu::BindGroupDescriptor {
                                label: Some("pipeline_sharpen_bg"),
                                layout: &self.sharpen_pipeline.get_bind_group_layout(0),
                                entries: &[
                                    wgpu::BindGroupEntry {
                                        binding: 0,
                                        resource: params_buf.as_entire_binding(),
                                    },
                                    wgpu::BindGroupEntry {
                                        binding: 1,
                                        resource: current_buf.as_entire_binding(),
                                    },
                                    wgpu::BindGroupEntry {
                                        binding: 2,
                                        resource: next_buf.as_entire_binding(),
                                    },
                                ],
                            });
                            {
                                let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                                    label: Some("pipeline_sharpen_pass"),
                                    timestamp_writes: None,
                                });
                                pass.set_pipeline(&self.sharpen_pipeline);
                                pass.set_bind_group(0, &bind_group, &[]);
                                let groups_x = (width + 15) / 16;
                                let groups_y = (height + 15) / 16;
                                pass.dispatch_workgroups(groups_x, groups_y, 1);
                            }
                            active_is_1 = !active_is_1;
                        }
                        ImageFilter::Blur { radius } => {
                            let r = *radius as u32;
                            let params_h = BlurParams {
                                width,
                                height,
                                radius: r,
                                dir_x: 1,
                                dir_y: 0,
                            };
                            let params_buf_h = self.device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
                                label: Some("pipeline_blur_params_h"),
                                contents: bytemuck::bytes_of(&params_h),
                                usage: wgpu::BufferUsages::UNIFORM,
                            });

                            let current_buf = if active_is_1 { &storage_buf1 } else { &storage_buf2 };
                            let next_buf = if active_is_1 { &storage_buf2 } else { &storage_buf1 };

                            let bind_group_h = self.device.create_bind_group(&wgpu::BindGroupDescriptor {
                                label: Some("pipeline_blur_bg_h"),
                                layout: &self.blur_pipeline.get_bind_group_layout(0),
                                entries: &[
                                    wgpu::BindGroupEntry {
                                        binding: 0,
                                        resource: params_buf_h.as_entire_binding(),
                                    },
                                    wgpu::BindGroupEntry {
                                        binding: 1,
                                        resource: current_buf.as_entire_binding(),
                                    },
                                    wgpu::BindGroupEntry {
                                        binding: 2,
                                        resource: next_buf.as_entire_binding(),
                                    },
                                ],
                            });

                            {
                                let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                                    label: Some("pipeline_blur_pass_h"),
                                    timestamp_writes: None,
                                });
                                pass.set_pipeline(&self.blur_pipeline);
                                pass.set_bind_group(0, &bind_group_h, &[]);
                                let groups_x = (width + 15) / 16;
                                let groups_y = (height + 15) / 16;
                                pass.dispatch_workgroups(groups_x, groups_y, 1);
                            }

                            let params_v = BlurParams {
                                width,
                                height,
                                radius: r,
                                dir_x: 0,
                                dir_y: 1,
                            };
                            let params_buf_v = self.device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
                                label: Some("pipeline_blur_params_v"),
                                contents: bytemuck::bytes_of(&params_v),
                                usage: wgpu::BufferUsages::UNIFORM,
                            });

                            let bind_group_v = self.device.create_bind_group(&wgpu::BindGroupDescriptor {
                                label: Some("pipeline_blur_bg_v"),
                                layout: &self.blur_pipeline.get_bind_group_layout(0),
                                entries: &[
                                    wgpu::BindGroupEntry {
                                        binding: 0,
                                        resource: params_buf_v.as_entire_binding(),
                                    },
                                    wgpu::BindGroupEntry {
                                        binding: 1,
                                        resource: next_buf.as_entire_binding(),
                                    },
                                    wgpu::BindGroupEntry {
                                        binding: 2,
                                        resource: current_buf.as_entire_binding(),
                                    },
                                ],
                            });

                            {
                                let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                                    label: Some("pipeline_blur_pass_v"),
                                    timestamp_writes: None,
                                });
                                pass.set_pipeline(&self.blur_pipeline);
                                pass.set_bind_group(0, &bind_group_v, &[]);
                                let groups_x = (width + 15) / 16;
                                let groups_y = (height + 15) / 16;
                                pass.dispatch_workgroups(groups_x, groups_y, 1);
                            }
                        }
                        _ => return Err("Unsupported filter in GPU pipeline".into()),
                    }
                }
                crate::api::image::EditOp::Resize { width: w, height: h, algorithm } => {
                    let (dst_w, dst_h) = (*w, *h);
                    let dst_len = (dst_w as usize) * (dst_h as usize);

                    let params = ResizeParams {
                        src_width: width,
                        src_height: height,
                        dst_width: dst_w,
                        dst_height: dst_h,
                        filter_nearest: if matches!(algorithm, ResizeAlgorithm::Nearest) { 1 } else { 0 },
                    };
                    let params_buf = self.device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
                        label: Some("pipeline_resize_params"),
                        contents: bytemuck::bytes_of(&params),
                        usage: wgpu::BufferUsages::UNIFORM,
                    });

                    let dst_buf = self.device.create_buffer(&wgpu::BufferDescriptor {
                        label: Some("pipeline_resize_dst"),
                        size: (dst_len * std::mem::size_of::<u32>()) as u64,
                        usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC | wgpu::BufferUsages::COPY_DST,
                        mapped_at_creation: false,
                    });

                    let current_buf = if active_is_1 { &storage_buf1 } else { &storage_buf2 };
                    let bind_group = self.device.create_bind_group(&wgpu::BindGroupDescriptor {
                        label: Some("pipeline_resize_bg"),
                        layout: &self.resize_pipeline.get_bind_group_layout(0),
                        entries: &[
                            wgpu::BindGroupEntry {
                                binding: 0,
                                resource: params_buf.as_entire_binding(),
                            },
                            wgpu::BindGroupEntry {
                                binding: 1,
                                resource: current_buf.as_entire_binding(),
                            },
                            wgpu::BindGroupEntry {
                                binding: 2,
                                resource: dst_buf.as_entire_binding(),
                            },
                        ],
                    });

                    {
                        let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                            label: Some("pipeline_resize_pass"),
                            timestamp_writes: None,
                        });
                        pass.set_pipeline(&self.resize_pipeline);
                        pass.set_bind_group(0, &bind_group, &[]);
                        let groups_x = (dst_w + 15) / 16;
                        let groups_y = (dst_h + 15) / 16;
                        pass.dispatch_workgroups(groups_x, groups_y, 1);
                    }

                    storage_buf1 = dst_buf;
                    storage_buf2 = self.device.create_buffer(&wgpu::BufferDescriptor {
                        label: Some("pipeline_storage2_resized"),
                        size: (dst_len * std::mem::size_of::<u32>()) as u64,
                        usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC | wgpu::BufferUsages::COPY_DST,
                        mapped_at_creation: false,
                    });
                    readback_buf = self.device.create_buffer(&wgpu::BufferDescriptor {
                        label: Some("pipeline_readback_resized"),
                        size: (dst_len * std::mem::size_of::<u32>()) as u64,
                        usage: wgpu::BufferUsages::MAP_READ | wgpu::BufferUsages::COPY_DST,
                        mapped_at_creation: false,
                    });
                    active_is_1 = true;
                    width = dst_w;
                    height = dst_h;
                    len = dst_len;
                }
                _ => return Err("Unsupported operation in GPU pipeline".into()),
            }
        }

        let active_buf = if active_is_1 { &storage_buf1 } else { &storage_buf2 };
        encoder.copy_buffer_to_buffer(
            active_buf,
            0,
            &readback_buf,
            0,
            (len * std::mem::size_of::<u32>()) as u64,
        );

        self.queue.submit(Some(encoder.finish()));
        let packed = self.map_read_u32(&readback_buf, len)?;
        buffer.width = width;
        buffer.height = height;
        buffer.pixels = unpack_pixels(&packed, len);
        Ok(buffer)
    }

    fn map_read_u32(&self, readback: &wgpu::Buffer, len: usize) -> Result<Vec<u32>, String> {
        let slice = readback.slice(..);
        let (sender, receiver) = std::sync::mpsc::channel();
        slice.map_async(wgpu::MapMode::Read, move |r| {
            let _ = sender.send(r);
        });
        self.device.poll(wgpu::Maintain::Wait);
        receiver
            .recv()
            .map_err(|_| "GPU readback channel closed".to_string())?
            .map_err(|e| format!("GPU map failed: {e:?}"))?;

        let data = slice.get_mapped_range();
        let bytes = &data[..len * std::mem::size_of::<u32>()];
        let out = bytemuck::cast_slice::<u8, u32>(bytes).to_vec();
        drop(data);
        readback.unmap();
        Ok(out)
    }

    fn dispatch_color_adjust(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        current_buf: &wgpu::Buffer,
        width: u32,
        height: u32,
        b: f32,
        c: f32,
        s: f32,
        hue_degrees: f32,
    ) {
        let params = ColorParams {
            width,
            height,
            brightness: b,
            contrast: c,
            saturation: s,
            hue_degrees,
        };
        let params_buf = self.device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some("color_params"),
            contents: bytemuck::bytes_of(&params),
            usage: wgpu::BufferUsages::UNIFORM,
        });

        let bind_group = self.device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("color_bind_group"),
            layout: &self.color_pipeline.get_bind_group_layout(0),
            entries: &[
                wgpu::BindGroupEntry {
                    binding: 0,
                    resource: params_buf.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 1,
                    resource: current_buf.as_entire_binding(),
                },
            ],
        });

        let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("color_pass"),
            timestamp_writes: None,
        });
        pass.set_pipeline(&self.color_pipeline);
        pass.set_bind_group(0, &bind_group, &[]);
        let groups_x = (width + 15) / 16;
        let groups_y = (height + 15) / 16;
        pass.dispatch_workgroups(groups_x, groups_y, 1);
    }
}

fn pack_pixels(rgba: &[u8]) -> Vec<u32> {
    match bytemuck::try_cast_slice::<u8, u32>(rgba) {
        Ok(cast) => cast.to_vec(),
        Err(_) => {
            rgba.chunks_exact(4)
                .map(|c| u32::from_le_bytes([c[0], c[1], c[2], c[3]]))
                .collect()
        }
    }
}

fn unpack_pixels(packed: &[u32], pixel_count: usize) -> Vec<u8> {
    let slice = if packed.len() > pixel_count {
        &packed[..pixel_count]
    } else {
        packed
    };
    match bytemuck::try_cast_slice::<u32, u8>(slice) {
        Ok(cast) => cast.to_vec(),
        Err(_) => {
            let mut out = Vec::with_capacity(pixel_count * 4);
            for p in slice.iter() {
                let bytes = p.to_le_bytes();
                out.extend_from_slice(&bytes);
            }
            out
        }
    }
}

fn backend_label(backend: wgpu::Backend) -> &'static str {
    match backend {
        wgpu::Backend::Metal => "metal",
        wgpu::Backend::Vulkan => "vulkan",
        wgpu::Backend::Dx12 => "dx12",
        wgpu::Backend::Gl => "opengl",
        wgpu::Backend::BrowserWebGpu => "webgpu",
        _ => "unknown",
    }
}
