use fast_image_resize::{FilterType, ResizeAlg};
use rayon::prelude::*;

use crate::{
    buffer, crop, draw, exif, filters, overlay, resize, rotate, thumbnail, utils,
};

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    crate::runtime::configure_runtime();
    flutter_rust_bridge::setup_default_user_utils();
}

/// The image format for output compression.
#[derive(Debug, Clone, Copy)]
pub enum OutputFormat {
    Jpeg,
    Png,
    WebP,
    Avif,
}

/// Image resizing algorithms, ranging from fast/nearest-neighbor to high-quality Lanczos.
#[derive(Debug, Clone, Copy)]
pub enum ResizeAlgorithm {
    Nearest,
    Box,
    Hamming,
    CatmullRom,
    Mitchell,
    Lanczos3,
}

impl From<ResizeAlgorithm> for ResizeAlg {
    fn from(value: ResizeAlgorithm) -> Self {
        match value {
            ResizeAlgorithm::Nearest => ResizeAlg::Nearest,
            ResizeAlgorithm::Box => ResizeAlg::Convolution(FilterType::Box),
            ResizeAlgorithm::Hamming => ResizeAlg::Convolution(FilterType::Hamming),
            ResizeAlgorithm::CatmullRom => ResizeAlg::Convolution(FilterType::CatmullRom),
            ResizeAlgorithm::Mitchell => ResizeAlg::Convolution(FilterType::Mitchell),
            ResizeAlgorithm::Lanczos3 => ResizeAlg::Convolution(FilterType::Lanczos3),
        }
    }
}

/// Rotations and mirror/flip transformations.
#[derive(Debug, Clone, Copy)]
pub enum Rotation {
    Rotate90,
    Rotate180,
    Rotate270,
    FlipHorizontal,
    FlipVertical,
}

/// Dynamic filters and adjustments applied to the image.
#[derive(Debug, Clone)]
pub enum ImageFilter {
    /// Gaussian or box blur.
    Blur { radius: u32 },
    /// High-pass sharpening.
    Sharpen,
    /// Adjust brightness (range: -255 to 255).
    Brightness { amount: i16 },
    /// Adjust contrast (range: 0.0 to 10.0, 1.0 is identity).
    Contrast { amount: f32 },
    /// Adjust color saturation (range: 0.0 to 10.0, 1.0 is identity).
    Saturation { amount: f32 },
    /// Rotate hue in degrees (range: 0.0 to 360.0).
    HueRotate { degrees: f32 },
    /// Artistic oil painting effect.
    Oil { radius: u32, intensity: f64 },
    /// Frosted glass blurring effect.
    FrostedGlass,
    /// Pixelation effect with custom cell size.
    Pixelize { size: u32 },
    /// Invert colors based on threshold/solarization.
    Solarize,
    /// Classic presets (Neue, Lofi, Firenze, etc.) with custom strength (0.0 to 1.0).
    Preset {
        preset: FilterPreset,
        strength: f32,
    },
    /// Color temperature shift (-100 cool ... +100 warm).
    Warmth { amount: f32 },
    /// Blend toward neutral gray (0 = none, 1 = max fade).
    Fade { amount: f32 },
    /// Radial edge darkening (0 = none, 1 = strong).
    Vignette { amount: f32 },
    /// Recover/compress bright tones (-100 ... +100).
    Highlights { amount: f32 },
    /// Lift/crush dark tones (-100 ... +100).
    Shadows { amount: f32 },
    /// Local clarity / micro-contrast (-100 ... +100).
    Structure { amount: f32 },
    /// Swipe mood filter (Instagram-style global grade) — requires image_forge.
    Mood {
        preset: MoodFilterPreset,
        strength: f32,
    },
    /// Combo swipe look (global grade from [SwipeLookPreset] — beauty in separate slot) — requires image_forge.
    SwipeLook {
        preset: SwipeLookPreset,
        strength: f32,
    },
    /// Authentic 3D LUT PNG filter (Hald CLUT representation) — requires image_forge.
    LutPng {
        png_bytes: Vec<u8>,
        strength: f32,
    },
    /// Regional skin smooth (mask applied separately in session / GPU pass) — requires image_forge.
    SkinSmooth {
        strength: f32,
    },
    /// Regional beauty (skin, eyes, lips, blush) — mask + landmarks in session — requires image_forge.
    Beauty {
        params: BeautyParams,
    },
}

/// Lip color swatch for regional tint.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum LipTintPreset {
    #[default]
    None,
    Nude,
    Rose,
    Berry,
    Coral,
    Red,
}

/// Regional beauty parameters — used by face beauty pipeline in image_forge.
#[derive(Debug, Clone, Copy, Default)]
pub struct BeautyParams {
    pub skin_smooth: f32,
    pub eye_brighten: f32,
    pub lip_tint: LipTintPreset,
    pub lip_tint_strength: f32,
    pub lip_plump: f32,
    pub blush: f32,
    pub under_eye: f32,
    pub teeth_whiten: f32,
    pub skin_preserve_detail: f32,
    pub eye_enlarge: f32,
    pub jaw_slim: f32,
    pub nose_slim: f32,
    pub face_slim: f32,
    pub chin_vshape: f32,
}

/// One-tap beauty look preset.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum BeautyLookPreset {
    Natural,
    Soft,
    Glow,
    Glam,
    Clear,
    Peach,
    Bold,
}

/// Filter presets applied globally to color grade the image.
#[derive(Debug, Clone, Copy)]
pub enum FilterPreset {
    Neue,
    Lix,
    Ryo,
    Lofi,
    PastelPink,
    Golden,
    Cali,
    Dramatic,
    Firenze,
    Obsidian,
    DuotoneViolette,
    DuotoneHorizon,
    DuotoneLilac,
    DuotoneOchre,
}

/// Instagram-style mood filters (requires image_forge for implementation).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum MoodFilterPreset {
    Rose,
    Clarendon,
    Juno,
    Valencia,
    Lark,
    Reyes,
    Gingham,
    LoFi,
    Moon,
    Aden,
    Perpetua,
    Mayfair,
    Hudson,
    Sierra,
    Willow,
    Inkwell,
}

/// TikTok / Instagram combo swipe looks (requires image_forge for implementation).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum SwipeLookPreset {
    CleanGirlGlow,
    CloudSkin,
    GoldenAura,
    SoftFocus,
    FauxFilm,
    BoldGlamourLite,
    NeonNight,
    AnimeAirbrush,
}

/// Post-grade extras applied during combo looks (such as overlay glow or grain).
#[derive(Debug, Clone, Copy)]
pub struct SwipeLookExtrasDto {
    pub glow: f32,
    pub grain: f32,
    pub sharpen: f32,
    pub skin_preserve_detail: f32,
    pub halation: f32,
    pub rgb_split: f32,
}

/// Composite blend modes.
#[derive(Debug, Clone, Copy)]
pub enum BlendMode {
    Normal,
    Multiply,
    Screen,
    Overlay,
    Add,
}

/// Processing backend: CPU (SIMD) or GPU (Metal/Vulkan via wgpu).
#[derive(Debug, Clone, Copy)]
pub enum ProcessingBackend {
    Cpu,
    Gpu,
    Auto,
}

/// Quality vs Speed choice for interactive previews.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PreviewQuality {
    Fast,
    Quality,
}

/// Diagnostics metadata about the active GPU device.
#[derive(Debug, Clone)]
pub struct GpuComputeInfo {
    pub available: bool,
    pub api: String,
    pub device: String,
}

/// High-level format and EXIF info for a queried image.
#[derive(Debug, Clone)]
pub struct ImageInfo {
    pub width: u32,
    pub height: u32,
    pub format: Option<String>,
    pub exif_orientation: Option<u16>,
}

/// Raw RGBA buffer for chained edits without re-decoding.
#[derive(Debug, Clone)]
pub struct RgbaImageBuffer {
    pub width: u32,
    pub height: u32,
    pub pixels: Vec<u8>,
}

/// Progressive decoding results containing a fast preview and the full image buffer.
#[derive(Debug, Clone)]
pub struct ProgressiveDecodeResult {
    pub info: ImageInfo,
    pub preview_rgba: RgbaImageBuffer,
    pub buffer: RgbaImageBuffer,
}

/// Text overlay drawing settings.
#[derive(Debug, Clone)]
pub struct TextOverlay {
    pub text: String,
    pub x: u32,
    pub y: u32,
    pub font_size: f32,
    pub color_r: u8,
    pub color_g: u8,
    pub color_b: u8,
    pub color_a: u8,
}

/// Vector line coordinates and styles.
#[derive(Debug, Clone, Copy)]
pub struct DrawLine {
    pub x0: u32,
    pub y0: u32,
    pub x1: u32,
    pub y1: u32,
    pub color_r: u8,
    pub color_g: u8,
    pub color_b: u8,
    pub color_a: u8,
}

/// Vector circle coordinates and styles.
#[derive(Debug, Clone, Copy)]
pub struct DrawCircle {
    pub center_x: u32,
    pub center_y: u32,
    pub radius: u32,
    pub color_r: u8,
    pub color_g: u8,
    pub color_b: u8,
    pub color_a: u8,
}

/// Batch resize input payload.
#[derive(Debug, Clone)]
pub struct BatchResizeItem {
    pub bytes: Vec<u8>,
    pub width: u32,
    pub height: u32,
}

fn process(bytes: &[u8], fix_exif: bool) -> Result<image::DynamicImage, String> {
    let img = utils::decode(bytes)?;
    if fix_exif {
        exif::apply_orientation(img, bytes)
    } else {
        Ok(img)
    }
}

/// Resizes an image file and encodes the result in the specified format and quality.
#[flutter_rust_bridge::frb(sync)]
pub fn resize_image(
    bytes: Vec<u8>,
    width: u32,
    height: u32,
    algorithm: ResizeAlgorithm,
    format: OutputFormat,
    quality: u8,
    fix_exif: bool,
    backend: ProcessingBackend,
) -> Result<Vec<u8>, String> {
    let img = process(&bytes, fix_exif)?;
    let resized = resize::resize(img, width, height, algorithm, backend)?;
    utils::encode(&resized, format, quality)
}

/// Creates a fast thumbnail for an image. Fits the image within `max_edge` bounding box.
#[flutter_rust_bridge::frb(sync)]
pub fn create_thumbnail(
    bytes: Vec<u8>,
    max_edge: u32,
    format: OutputFormat,
    quality: u8,
    algorithm: ResizeAlgorithm,
    fix_exif: bool,
    backend: ProcessingBackend,
) -> Result<Vec<u8>, String> {
    let bytes = if fix_exif {
        let img = process(&bytes, true)?;
        utils::encode(&img, format, quality)?
    } else {
        bytes
    };
    thumbnail::thumbnail(&bytes, max_edge, format, quality, algorithm, backend)
}

/// Crops a rectangular area of an image file.
#[flutter_rust_bridge::frb(sync)]
pub fn crop_image(
    bytes: Vec<u8>,
    x: u32,
    y: u32,
    width: u32,
    height: u32,
    format: OutputFormat,
    quality: u8,
    fix_exif: bool,
) -> Result<Vec<u8>, String> {
    let img = process(&bytes, fix_exif)?;
    let cropped = crop::crop(img, x, y, width, height)?;
    utils::encode(&cropped, format, quality)
}

/// Rotates or flips an image file.
#[flutter_rust_bridge::frb(sync)]
pub fn rotate_image(
    bytes: Vec<u8>,
    rotation: Rotation,
    format: OutputFormat,
    quality: u8,
    fix_exif: bool,
) -> Result<Vec<u8>, String> {
    let img = process(&bytes, fix_exif)?;
    let rotated = rotate::rotate(img, rotation);
    utils::encode(&rotated, format, quality)
}

/// Rewrites the image file so that pixels match the physical EXIF orientation, clearing the EXIF tag.
#[flutter_rust_bridge::frb(sync)]
pub fn fix_exif_orientation(bytes: Vec<u8>, format: OutputFormat, quality: u8) -> Result<Vec<u8>, String> {
    let img = process(&bytes, true)?;
    utils::encode(&img, format, quality)
}

/// Reads the raw EXIF orientation value from the image metadata.
#[flutter_rust_bridge::frb(sync)]
pub fn read_exif_orientation(bytes: Vec<u8>) -> Option<u16> {
    exif::orientation_value(&bytes)
}

/// Re-compresses an image file with a specified quality and output format.
#[flutter_rust_bridge::frb(sync)]
pub fn compress_image(bytes: Vec<u8>, format: OutputFormat, quality: u8) -> Result<Vec<u8>, String> {
    let img = utils::decode(&bytes)?;
    utils::encode(&img, format, quality)
}

/// Applies a basic filter or adjustment (brightness, blur, etc.) to an image file.
/// Studio filters (Mood, SwipeLook, LutPng, SkinSmooth, Beauty) return an error when
/// called without the `image_forge` package.
#[flutter_rust_bridge::frb(sync)]
pub fn apply_filter(
    bytes: Vec<u8>,
    filter: ImageFilter,
    format: OutputFormat,
    quality: u8,
    fix_exif: bool,
) -> Result<Vec<u8>, String> {
    let img = process(&bytes, fix_exif)?;
    let buffer = RgbaImageBuffer::from_dynamic(img);
    let filtered = filters::apply_rgba(buffer, filter)?;
    buffer::encode_from_rgba(filtered, format, quality)
}

/// Overlays a watermark image onto a base image at the specified pixel coordinates.
#[flutter_rust_bridge::frb(sync)]
pub fn add_watermark(
    base_bytes: Vec<u8>,
    overlay_bytes: Vec<u8>,
    x: i32,
    y: i32,
    format: OutputFormat,
    quality: u8,
) -> Result<Vec<u8>, String> {
    let img = filters::watermark(&base_bytes, &overlay_bytes, x, y)?;
    utils::encode(&img, format, quality)
}

/// Renders a single line of text directly onto the image.
#[flutter_rust_bridge::frb(sync)]
pub fn draw_text_on_image(
    bytes: Vec<u8>,
    overlay: TextOverlay,
    format: OutputFormat,
    quality: u8,
    fix_exif: bool,
) -> Result<Vec<u8>, String> {
    let img = process(&bytes, fix_exif)?;
    let rgba = img.into_rgba8();
    let drawn = draw::draw_text(rgba, overlay)?;
    let drawn_dyn = image::DynamicImage::ImageRgba8(drawn);
    encode_after_edit(&drawn_dyn, format, quality)
}

/// Draws a vector line directly onto the image.
#[flutter_rust_bridge::frb(sync)]
pub fn draw_line_on_image(
    bytes: Vec<u8>,
    line: DrawLine,
    format: OutputFormat,
    quality: u8,
    fix_exif: bool,
) -> Result<Vec<u8>, String> {
    let img = process(&bytes, fix_exif)?;
    let rgba = img.into_rgba8();
    let drawn = draw::draw_line(rgba, line)?;
    let drawn_dyn = image::DynamicImage::ImageRgba8(drawn);
    encode_after_edit(&drawn_dyn, format, quality)
}

/// Draws a vector circle directly onto the image.
#[flutter_rust_bridge::frb(sync)]
pub fn draw_circle_on_image(
    bytes: Vec<u8>,
    circle: DrawCircle,
    format: OutputFormat,
    quality: u8,
    fix_exif: bool,
) -> Result<Vec<u8>, String> {
    let img = process(&bytes, fix_exif)?;
    let rgba = img.into_rgba8();
    let drawn = draw::draw_circle(rgba, circle)?;
    let drawn_dyn = image::DynamicImage::ImageRgba8(drawn);
    encode_after_edit(&drawn_dyn, format, quality)
}

fn encode_after_edit(
    img: &image::DynamicImage,
    format: OutputFormat,
    quality: u8,
) -> Result<Vec<u8>, String> {
    match format {
        OutputFormat::Png => crate::compress::encode_png(img, false),
        _ => utils::encode(img, format, quality),
    }
}

/// Resizes multiple images concurrently in parallel (using rayon).
#[flutter_rust_bridge::frb(sync)]
pub fn batch_resize_images(
    items: Vec<BatchResizeItem>,
    algorithm: ResizeAlgorithm,
    format: OutputFormat,
    quality: u8,
    backend: ProcessingBackend,
) -> Result<Vec<Vec<u8>>, String> {
    items
        .par_iter()
        .map(|item| {
            let img = utils::decode(&item.bytes)?;
            let resized = resize::resize(img, item.width, item.height, algorithm, backend)?;
            utils::encode(&resized, format, quality)
        })
        .collect()
}

/// Composites an overlay image onto a base image using standard blend modes.
#[flutter_rust_bridge::frb(sync)]
pub fn overlay_image(
    base_bytes: Vec<u8>,
    overlay_bytes: Vec<u8>,
    x: i32,
    y: i32,
    blend_mode: BlendMode,
    format: OutputFormat,
    quality: u8,
) -> Result<Vec<u8>, String> {
    let base = buffer::decode_to_rgba(&base_bytes, false, None)?;
    let composed = overlay::composite(base, &overlay_bytes, x, y, blend_mode, 0, 0)?;
    encode_after_edit_rgba(composed, format, quality)
}

fn encode_after_edit_rgba(
    buffer: RgbaImageBuffer,
    format: OutputFormat,
    quality: u8,
) -> Result<Vec<u8>, String> {
    let img = buffer.to_dynamic()?;
    encode_after_edit(&img, format, quality)
}

/// Computes a BlurHash string from raw image bytes.
#[cfg(feature = "blurhash")]
#[flutter_rust_bridge::frb(sync)]
pub fn encode_blurhash(bytes: Vec<u8>, components_x: u32, components_y: u32) -> Result<String, String> {
    let img = utils::decode(&bytes)?;
    crate::blurhash::encode(&img, components_x, components_y)
}

/// Decodes a BlurHash string back into compressed image bytes.
#[cfg(feature = "blurhash")]
#[flutter_rust_bridge::frb(sync)]
pub fn decode_blurhash(
    hash: String,
    width: u32,
    height: u32,
    format: OutputFormat,
    quality: u8,
) -> Result<Vec<u8>, String> {
    let img = crate::blurhash::decode(&hash, width, height)?;
    utils::encode(&img, format, quality)
}

/// Placeholder if BlurHash is disabled.
#[cfg(not(feature = "blurhash"))]
#[flutter_rust_bridge::frb(sync)]
pub fn encode_blurhash(
    _bytes: Vec<u8>,
    _components_x: u32,
    _components_y: u32,
) -> Result<String, String> {
    Err("BlurHash disabled. Build with default features or `blurhash`.".into())
}

/// Placeholder if BlurHash is disabled.
#[cfg(not(feature = "blurhash"))]
#[flutter_rust_bridge::frb(sync)]
pub fn decode_blurhash(
    _hash: String,
    _width: u32,
    _height: u32,
    _format: OutputFormat,
    _quality: u8,
) -> Result<Vec<u8>, String> {
    Err("BlurHash disabled. Build with default features or `blurhash`.".into())
}

/// Representation of a non-destructive edit operation.
#[derive(Debug, Clone)]
pub enum EditOp {
    Filter {
        filter: ImageFilter,
    },
    Resize {
        width: u32,
        height: u32,
        algorithm: ResizeAlgorithm,
    },
    Crop {
        x: u32,
        y: u32,
        width: u32,
        height: u32,
    },
    Rotate {
        rotation: Rotation,
    },
}

#[flutter_rust_bridge::frb(sync)]
pub fn apply_edit_pipeline(
    buffer: RgbaImageBuffer,
    ops: Vec<EditOp>,
    backend: ProcessingBackend,
) -> Result<RgbaImageBuffer, String> {
    let mut buf = buffer;
    let is_gpu = matches!(crate::backend::resolve(backend), Ok(crate::backend::EffectiveBackend::Gpu));

    if is_gpu {
        #[cfg(feature = "gpu")]
        {
            if let Ok(gpu) = crate::gpu::engine() {
                let mut i = 0;
                while i < ops.len() {
                    let mut gpu_ops = Vec::new();
                    while i < ops.len() && is_gpu_capable(&ops[i]) {
                        gpu_ops.push(ops[i].clone());
                        i += 1;
                    }
                    if !gpu_ops.is_empty() {
                        buf = gpu.process_gpu_pipeline(buf, &gpu_ops)?;
                    }
                    if i < ops.len() {
                        buf = apply_single_op_cpu(buf, &ops[i])?;
                        i += 1;
                    }
                }
                return Ok(buf);
            }
        }
    }

    for op in ops {
        buf = apply_single_op_cpu(buf, &op)?;
    }
    Ok(buf)
}

fn is_gpu_capable(op: &EditOp) -> bool {
    match op {
        EditOp::Filter { filter } => {
            matches!(
                filter,
                ImageFilter::Brightness { .. }
                    | ImageFilter::Contrast { .. }
                    | ImageFilter::Saturation { .. }
                    | ImageFilter::HueRotate { .. }
                    | ImageFilter::Blur { .. }
                    | ImageFilter::Sharpen
                    | ImageFilter::Vignette { .. }
            )
        }
        EditOp::Resize { .. } => true,
        _ => false,
    }
}

fn apply_single_op_cpu(buf: RgbaImageBuffer, op: &EditOp) -> Result<RgbaImageBuffer, String> {
    match op {
        EditOp::Filter { filter } => {
            buffer::filter_rgba_with_backend(buf, filter.clone(), ProcessingBackend::Cpu)
        }
        EditOp::Resize { width, height, algorithm } => {
            buffer::resize_rgba(buf, *width, *height, *algorithm, ProcessingBackend::Cpu)
        }
        EditOp::Crop { x, y, width, height } => {
            buffer::crop_rgba(buf, *x, *y, *width, *height)
        }
        EditOp::Rotate { rotation } => {
            let img = buf.into_dynamic()?;
            let rotated = rotate::rotate(img, *rotation);
            Ok(RgbaImageBuffer::from_dynamic(rotated))
        }
    }
}

/// Dummy function to force the code generator to expose BeautyLookPreset and SwipeLookExtrasDto
#[flutter_rust_bridge::frb(sync)]
pub fn dummy_for_codegen_extras(_a: SwipeLookExtrasDto, _b: BeautyLookPreset) {}

