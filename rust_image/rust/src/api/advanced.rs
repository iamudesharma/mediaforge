use crate::api::image::{
    BlendMode, DrawCircle, DrawLine, GpuComputeInfo, ImageFilter, ImageInfo, OutputFormat,
    ProcessingBackend, ProgressiveDecodeResult, ResizeAlgorithm, RgbaImageBuffer, TextOverlay,
    PreviewQuality,
};
use crate::{backend, buffer, decode, overlay, pool};

#[flutter_rust_bridge::frb(sync)]
pub fn probe_image(bytes: Vec<u8>) -> Result<ImageInfo, String> {
    decode::probe(&bytes)
}

#[flutter_rust_bridge::frb(sync)]
pub fn gpu_compute_info() -> GpuComputeInfo {
    let available = backend::gpu_available();
    if !available {
        return GpuComputeInfo {
            available: false,
            api: String::new(),
            device: String::new(),
        };
    }
    #[cfg(feature = "gpu")]
    {
        let (_, api, device) = crate::gpu::capabilities();
        GpuComputeInfo {
            available: true,
            api,
            device,
        }
    }
    #[cfg(not(feature = "gpu"))]
    {
        GpuComputeInfo {
            available: false,
            api: String::new(),
            device: String::new(),
        }
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn is_gpu_compute_available() -> bool {
    backend::gpu_available()
}

#[flutter_rust_bridge::frb(sync)]
pub fn decode_to_rgba_buffer(
    bytes: Vec<u8>,
    fix_exif: bool,
    max_edge: Option<u32>,
) -> Result<RgbaImageBuffer, String> {
    buffer::decode_to_rgba(&bytes, fix_exif, max_edge)
}

#[flutter_rust_bridge::frb(sync)]
pub fn encode_rgba_buffer(
    buffer: RgbaImageBuffer,
    format: OutputFormat,
    quality: u8,
) -> Result<Vec<u8>, String> {
    buffer::encode_from_rgba(buffer, format, quality)
}

#[flutter_rust_bridge::frb(sync)]
pub fn resize_rgba_buffer(
    buffer: RgbaImageBuffer,
    width: u32,
    height: u32,
    algorithm: ResizeAlgorithm,
    backend: ProcessingBackend,
) -> Result<RgbaImageBuffer, String> {
    buffer::resize_rgba(buffer, width, height, algorithm, backend)
}

#[flutter_rust_bridge::frb(sync)]
pub fn crop_rgba_buffer(
    buffer: RgbaImageBuffer,
    x: u32,
    y: u32,
    width: u32,
    height: u32,
) -> Result<RgbaImageBuffer, String> {
    buffer::crop_rgba(buffer, x, y, width, height)
}

/// Arbitrary straighten rotation (degrees), expanding canvas with transparency.
#[flutter_rust_bridge::frb(sync)]
pub fn rotate_rgba_arbitrary(buffer: RgbaImageBuffer, degrees: f32) -> Result<RgbaImageBuffer, String> {
    crate::rotate::rotate_rgba_arbitrary(buffer, degrees)
}

#[flutter_rust_bridge::frb(sync)]
pub fn filter_rgba_buffer(
    buffer: RgbaImageBuffer,
    filter: ImageFilter,
    backend: ProcessingBackend,
) -> Result<RgbaImageBuffer, String> {
    buffer::filter_rgba_with_backend(buffer, filter, backend)
}

#[flutter_rust_bridge::frb(sync)]
pub fn fit_max_edge_rgba_buffer(
    buffer: RgbaImageBuffer,
    max_edge: u32,
    preview_quality: PreviewQuality,
) -> Result<RgbaImageBuffer, String> {
    buffer::fit_max_edge_rgba(buffer, max_edge, preview_quality)
}

#[flutter_rust_bridge::frb(sync)]
pub fn filter_execution_path_name(
    filter: ImageFilter,
    backend: ProcessingBackend,
) -> String {
    crate::perf::filter_execution_path(&filter, backend).to_string()
}

#[flutter_rust_bridge::frb(sync)]
pub fn draw_line_rgba_buffer(
    buffer: RgbaImageBuffer,
    line: DrawLine,
) -> Result<RgbaImageBuffer, String> {
    buffer::draw_line_rgba(buffer, line)
}

#[flutter_rust_bridge::frb(sync)]
pub fn draw_circle_rgba_buffer(
    buffer: RgbaImageBuffer,
    circle: DrawCircle,
) -> Result<RgbaImageBuffer, String> {
    buffer::draw_circle_rgba(buffer, circle)
}

#[flutter_rust_bridge::frb(sync)]
pub fn draw_text_rgba_buffer(
    buffer: RgbaImageBuffer,
    overlay: TextOverlay,
) -> Result<RgbaImageBuffer, String> {
    buffer::draw_text_rgba(buffer, overlay)
}

#[flutter_rust_bridge::frb(sync)]
pub fn encode_rgba_preview_buffer(
    buffer: RgbaImageBuffer,
    max_edge: u32,
    quality: u8,
    preview_quality: PreviewQuality,
) -> Result<Vec<u8>, String> {
    buffer::encode_rgba_preview(buffer, max_edge, quality, preview_quality)
}

#[flutter_rust_bridge::frb(sync)]
pub fn overlay_on_rgba_buffer(
    base: RgbaImageBuffer,
    overlay_bytes: Vec<u8>,
    x: i32,
    y: i32,
    blend_mode: BlendMode,
    overlay_width: u32,
    overlay_height: u32,
) -> Result<RgbaImageBuffer, String> {
    overlay::composite(
        base,
        &overlay_bytes,
        x,
        y,
        blend_mode,
        overlay_width,
        overlay_height,
    )
}

#[flutter_rust_bridge::frb(sync)]
pub fn decode_progressive_image(
    bytes: Vec<u8>,
    preview_max_edge: u32,
    fix_exif: bool,
) -> Result<ProgressiveDecodeResult, String> {
    decode::decode_progressive(&bytes, preview_max_edge, fix_exif)
}

#[flutter_rust_bridge::frb(sync)]
pub fn buffer_pool_release(buf: Vec<u8>) {
    pool::release_buffer(buf);
}

#[flutter_rust_bridge::frb(sync)]
pub fn buffer_pool_acquire(min_capacity: u32) -> Vec<u8> {
    pool::acquire_buffer(min_capacity as usize)
}

#[flutter_rust_bridge::frb(sync)]
pub fn buffer_pool_stats() -> (usize, usize) {
    pool::pool_stats()
}

#[flutter_rust_bridge::frb(sync)]
pub fn processing_backend_name(backend: ProcessingBackend) -> String {
    backend::active_api_name(backend)
}
