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

#[derive(Debug, Clone, Copy)]
pub enum OutputFormat {
    Jpeg,
    Png,
    WebP,
    Avif,
}

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

#[derive(Debug, Clone, Copy)]
pub enum Rotation {
    Rotate90,
    Rotate180,
    Rotate270,
    FlipHorizontal,
    FlipVertical,
}

#[derive(Debug, Clone)]
pub enum ImageFilter {
    Blur { radius: u32 },
    Sharpen,
    Brightness { amount: i16 },
    Contrast { amount: f32 },
    Saturation { amount: f32 },
    HueRotate { degrees: f32 },
    Oil { radius: u32, intensity: f64 },
    FrostedGlass,
    Pixelize { size: u32 },
    Solarize,
    Preset {
        preset: FilterPreset,
        /// 0.0 = identity, 1.0 = full preset (Instagram-style filter strength).
        strength: f32,
    },
    /// Color temperature shift (−100 cool … +100 warm).
    Warmth { amount: f32 },
    /// Blend toward neutral gray (0 = none, 1 = max fade).
    Fade { amount: f32 },
    /// Radial edge darkening (0 = none, 1 = strong).
    Vignette { amount: f32 },
    /// Recover/compress bright tones (−100 … +100).
    Highlights { amount: f32 },
    /// Lift/crush dark tones (−100 … +100).
    Shadows { amount: f32 },
    /// Local clarity / micro-contrast (−100 … +100).
    Structure { amount: f32 },
    /// Swipe mood filter (Instagram-style global grade).
    Mood {
        preset: MoodFilterPreset,
        /// 0.0 = identity, 1.0 = full mood grade.
        strength: f32,
    },
    /// Combo swipe look (global grade from [SwipeLookPreset] — beauty in separate slot).
    SwipeLook {
        preset: SwipeLookPreset,
        /// 0.0 = identity, 1.0 = full look grade.
        strength: f32,
    },
    /// Authentic 3D LUT PNG filter (Hald CLUT representation).
    LutPng {
        png_bytes: Vec<u8>,
        /// 0.0 = identity, 1.0 = full grade.
        strength: f32,
    },
    /// Regional skin smooth (mask applied separately in session / GPU pass).
    SkinSmooth {
        /// 0.0 = none, 1.0 = full smooth.
        strength: f32,
    },
    /// Regional beauty (skin, eyes, lips, blush) — mask + landmarks in session.
    Beauty {
        params: crate::api::face::BeautyParams,
    },
}

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

/// Instagram-style mood filters (swipe on preview — not Filters-tab presets).
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

/// TikTok / Instagram combo swipe looks (global grade + beauty slot).
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

#[derive(Debug, Clone, Copy)]
pub struct SwipeLookExtrasDto {
    pub glow: f32,
    pub grain: f32,
    pub sharpen: f32,
    pub skin_preserve_detail: f32,
    pub halation: f32,
    pub rgb_split: f32,
}

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

#[derive(Debug, Clone)]
pub struct GpuComputeInfo {
    pub available: bool,
    pub api: String,
    pub device: String,
}

#[derive(Debug, Clone)]
pub struct ImageInfo {
    pub width: u32,
    pub height: u32,
    pub format: Option<String>,
    pub exif_orientation: Option<u16>,
}

/// Raw RGBA buffer for chained edits without re-decoding (Phase 3).
#[derive(Debug, Clone)]
pub struct RgbaImageBuffer {
    pub width: u32,
    pub height: u32,
    pub pixels: Vec<u8>,
}

#[derive(Debug, Clone)]
pub struct ProgressiveDecodeResult {
    pub info: ImageInfo,
    pub preview_rgba: RgbaImageBuffer,
    pub buffer: RgbaImageBuffer,
}

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

#[flutter_rust_bridge::frb(sync)]
pub fn fix_exif_orientation(bytes: Vec<u8>, format: OutputFormat, quality: u8) -> Result<Vec<u8>, String> {
    let img = process(&bytes, true)?;
    utils::encode(&img, format, quality)
}

#[flutter_rust_bridge::frb(sync)]
pub fn read_exif_orientation(bytes: Vec<u8>) -> Option<u16> {
    exif::orientation_value(&bytes)
}

#[flutter_rust_bridge::frb(sync)]
pub fn compress_image(bytes: Vec<u8>, format: OutputFormat, quality: u8) -> Result<Vec<u8>, String> {
    let img = utils::decode(&bytes)?;
    utils::encode(&img, format, quality)
}

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
        // Interactive draw/export: skip oxipng max_compression (very slow on large images).
        OutputFormat::Png => crate::compress::encode_png(img, false),
        _ => utils::encode(img, format, quality),
    }
}

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

#[cfg(feature = "blurhash")]
#[flutter_rust_bridge::frb(sync)]
pub fn encode_blurhash(bytes: Vec<u8>, components_x: u32, components_y: u32) -> Result<String, String> {
    let img = utils::decode(&bytes)?;
    crate::blurhash::encode(&img, components_x, components_y)
}

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

#[cfg(not(feature = "blurhash"))]
#[flutter_rust_bridge::frb(sync)]
pub fn encode_blurhash(
    _bytes: Vec<u8>,
    _components_x: u32,
    _components_y: u32,
) -> Result<String, String> {
    Err("BlurHash disabled. Build with default features or `blurhash`.".into())
}

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

/// Regional beauty params for a combo swipe look.
#[flutter_rust_bridge::frb(sync)]
pub fn swipe_look_beauty_params(preset: SwipeLookPreset) -> crate::api::face::BeautyParams {
    crate::filters::swipe_look_recipe_for(preset).beauty
}

/// Post-grade extras (glow, grain, skin preserve) for a swipe look.
#[flutter_rust_bridge::frb(sync)]
pub fn swipe_look_extras(preset: SwipeLookPreset) -> SwipeLookExtrasDto {
    let e = crate::filters::swipe_look_recipe_for(preset).extras;
    SwipeLookExtrasDto {
        glow: e.glow,
        grain: e.grain,
        sharpen: e.sharpen,
        skin_preserve_detail: e.skin_preserve_detail,
        halation: e.halation,
        rgb_split: e.rgb_split,
    }
}

/// User-facing label for swipe combo filter chip.
#[flutter_rust_bridge::frb(sync)]
pub fn swipe_look_display_name(preset: SwipeLookPreset) -> String {
    crate::filters::swipe_look_display_name(preset).to_string()
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
                    |                 ImageFilter::Blur { .. }
                    | ImageFilter::Sharpen
                    | ImageFilter::Vignette { .. }
                    | ImageFilter::Mood { .. }
                    | ImageFilter::SwipeLook { .. }
                    | ImageFilter::LutPng { .. }
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
