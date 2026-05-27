use crate::api::image::{
    BlendMode, DrawCircle, DrawLine, GpuComputeInfo, ImageFilter, ImageInfo, OutputFormat,
    ProcessingBackend, ProgressiveDecodeResult, ResizeAlgorithm, RgbaImageBuffer, TextOverlay,
    PreviewQuality,
};
use crate::{backend, buffer, decode, overlay, pool};

/// Probes an image file to extract dimensions, format, and EXIF orientation without decoding full pixels.
#[flutter_rust_bridge::frb(sync)]
pub fn probe_image(bytes: Vec<u8>) -> Result<ImageInfo, String> {
    decode::probe(&bytes)
}

/// Retrieves metadata about the active GPU device and compute API (Metal/Vulkan etc.).
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

/// Returns true if GPU compute capability is supported on the current platform/device.
#[flutter_rust_bridge::frb(sync)]
pub fn is_gpu_compute_available() -> bool {
    backend::gpu_available()
}

/// Decodes an image file (JPEG, PNG, etc.) to raw 32-bit RGBA pixel buffers.
#[flutter_rust_bridge::frb(sync)]
pub fn decode_to_rgba_buffer(
    bytes: Vec<u8>,
    fix_exif: bool,
    max_edge: Option<u32>,
) -> Result<RgbaImageBuffer, String> {
    buffer::decode_to_rgba(&bytes, fix_exif, max_edge)
}

/// Encodes a raw RGBA buffer into compressed image bytes (such as JPEG/PNG).
#[flutter_rust_bridge::frb(sync)]
pub fn encode_rgba_buffer(
    buffer: RgbaImageBuffer,
    format: OutputFormat,
    quality: u8,
) -> Result<Vec<u8>, String> {
    buffer::encode_from_rgba(buffer, format, quality)
}

/// Resizes a raw RGBA buffer using the specified algorithm (with optional GPU acceleration).
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

/// Crops a rectangular region of a raw RGBA buffer.
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

/// Performs an arbitrary rotation (in degrees) on a raw RGBA buffer, expanding canvas size.
#[flutter_rust_bridge::frb(sync)]
pub fn rotate_rgba_arbitrary(buffer: RgbaImageBuffer, degrees: f32) -> Result<RgbaImageBuffer, String> {
    crate::rotate::rotate_rgba_arbitrary(buffer, degrees)
}

/// Applies a filter preset or adjustment (brightness/blur etc.) to a raw RGBA buffer.
#[flutter_rust_bridge::frb(sync)]
pub fn filter_rgba_buffer(
    buffer: RgbaImageBuffer,
    filter: ImageFilter,
    backend: ProcessingBackend,
) -> Result<RgbaImageBuffer, String> {
    buffer::filter_rgba_with_backend(buffer, filter, backend)
}

/// Resizes a raw RGBA buffer so its longest side fits within `max_edge`.
#[flutter_rust_bridge::frb(sync)]
pub fn fit_max_edge_rgba_buffer(
    buffer: RgbaImageBuffer,
    max_edge: u32,
    preview_quality: PreviewQuality,
) -> Result<RgbaImageBuffer, String> {
    buffer::fit_max_edge_rgba(buffer, max_edge, preview_quality)
}

/// Returns a string identifier for the filter execution path (e.g. "gpu_adjust" or "cpu_photon").
#[flutter_rust_bridge::frb(sync)]
pub fn filter_execution_path_name(
    filter: ImageFilter,
    backend: ProcessingBackend,
) -> String {
    crate::perf::filter_execution_path(&filter, backend).to_string()
}

/// Draws a vector line onto a raw RGBA buffer.
#[flutter_rust_bridge::frb(sync)]
pub fn draw_line_rgba_buffer(
    buffer: RgbaImageBuffer,
    line: DrawLine,
) -> Result<RgbaImageBuffer, String> {
    buffer::draw_line_rgba(buffer, line)
}

/// Draws a vector circle onto a raw RGBA buffer.
#[flutter_rust_bridge::frb(sync)]
pub fn draw_circle_rgba_buffer(
    buffer: RgbaImageBuffer,
    circle: DrawCircle,
) -> Result<RgbaImageBuffer, String> {
    buffer::draw_circle_rgba(buffer, circle)
}

/// Draws text onto a raw RGBA buffer.
#[flutter_rust_bridge::frb(sync)]
pub fn draw_text_rgba_buffer(
    buffer: RgbaImageBuffer,
    overlay: TextOverlay,
) -> Result<RgbaImageBuffer, String> {
    buffer::draw_text_rgba(buffer, overlay)
}

/// Encodes an RGBA buffer to preview JPEG bytes, optimized for performance over visual quality.
#[flutter_rust_bridge::frb(sync)]
pub fn encode_rgba_preview_buffer(
    buffer: RgbaImageBuffer,
    max_edge: u32,
    quality: u8,
    preview_quality: PreviewQuality,
) -> Result<Vec<u8>, String> {
    buffer::encode_rgba_preview(buffer, max_edge, quality, preview_quality)
}

/// Composites raw overlay pixels onto a base RGBA buffer at the specified position.
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

/// Performs progressive decoding of image bytes, yielding both a low-res preview and a full buffer.
#[flutter_rust_bridge::frb(sync)]
pub fn decode_progressive_image(
    bytes: Vec<u8>,
    preview_max_edge: u32,
    fix_exif: bool,
) -> Result<ProgressiveDecodeResult, String> {
    decode::decode_progressive(&bytes, preview_max_edge, fix_exif)
}

/// Releases a buffer (such as a rented `Vec<u8>`) back to the buffer pool (Phase 3).
#[flutter_rust_bridge::frb(sync)]
pub fn buffer_pool_release(buf: Vec<u8>) {
    pool::release_buffer(buf);
}

/// Rents or acquires a `Vec<u8>` from the pool with at least `min_capacity` to prevent allocations (Phase 3).
#[flutter_rust_bridge::frb(sync)]
pub fn buffer_pool_acquire(min_capacity: u32) -> Vec<u8> {
    pool::acquire_buffer(min_capacity as usize)
}

/// Returns the current statistics of the buffer pool `(count of buffers, total size in bytes)`.
#[flutter_rust_bridge::frb(sync)]
pub fn buffer_pool_stats() -> (usize, usize) {
    pool::pool_stats()
}

/// Returns a string representation of the active processing backend.
#[flutter_rust_bridge::frb(sync)]
pub fn processing_backend_name(backend: ProcessingBackend) -> String {
    backend::active_api_name(backend)
}
