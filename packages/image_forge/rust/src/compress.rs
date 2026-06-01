use image::{DynamicImage, GenericImageView, ImageEncoder};
use mozjpeg::ColorSpace;
use oxipng::{Options, StripChunks};

pub fn encode_jpeg(img: &DynamicImage, quality: u8) -> Result<Vec<u8>, String> {
    std::panic::catch_unwind(|| encode_jpeg_inner(img, quality))
        .map_err(|_| "mozjpeg panicked while encoding".to_string())?
}

pub fn encode_jpeg_optimized(
    img: &DynamicImage,
    quality: u8,
    preview_quality: crate::api::image::PreviewQuality,
) -> Result<Vec<u8>, String> {
    std::panic::catch_unwind(|| encode_jpeg_inner_optimized(img, quality, preview_quality))
        .map_err(|_| "mozjpeg panicked while encoding".to_string())?
}

fn encode_jpeg_inner(img: &DynamicImage, quality: u8) -> Result<Vec<u8>, String> {
    encode_jpeg_inner_optimized(img, quality, crate::api::image::PreviewQuality::Quality)
}

fn encode_jpeg_inner_optimized(
    img: &DynamicImage,
    quality: u8,
    preview_quality: crate::api::image::PreviewQuality,
) -> Result<Vec<u8>, String> {
    let (width, height) = img.dimensions();
    let mut rgb_storage: Option<image::RgbImage> = None;
    let mut rgb_storage_vec: Option<Vec<u8>> = None;

    let pixels: &[u8] = match img {
        DynamicImage::ImageRgb8(rgb) => rgb.as_raw(),
        DynamicImage::ImageRgba8(rgba) => {
            let raw = rgba.as_raw();
            let rgb_len = raw.len() / 4 * 3;
            let mut rgb = crate::pool::acquire_buffer(rgb_len);
            rgb.resize(rgb_len, 0);
            for (i, chunk) in raw.chunks_exact(4).enumerate() {
                let o = i * 3;
                rgb[o..o + 3].copy_from_slice(&chunk[..3]);
            }
            rgb_storage_vec = Some(rgb);
            rgb_storage_vec.as_ref().unwrap().as_slice()
        }
        _ => {
            rgb_storage = Some(img.to_rgb8());
            rgb_storage.as_ref().unwrap().as_raw()
        }
    };

    let mut comp = mozjpeg::Compress::new(ColorSpace::JCS_RGB);
    comp.set_size(width as usize, height as usize);
    comp.set_quality(f32::from(quality.clamp(1, 100)));

    if preview_quality == crate::api::image::PreviewQuality::Quality {
        comp.set_progressive_mode();
        comp.set_optimize_coding(true);
    } else {
        comp.set_optimize_coding(false);
    }

    let mut comp = comp.start_compress(Vec::new()).map_err(|e| e.to_string())?;
    comp.write_scanlines(pixels).map_err(|e| e.to_string())?;
    let out = comp.finish().map_err(|e| e.to_string())?;

    if let Some(buf) = rgb_storage_vec {
        crate::pool::release_buffer(buf);
    }
    let _ = rgb_storage;

    Ok(out)
}

pub fn encode_png(img: &DynamicImage, optimize: bool) -> Result<Vec<u8>, String> {
    let (w, h) = img.dimensions();
    let mut raw = Vec::new();
    let rgba_storage: Option<image::RgbaImage>;
    let pixels: &[u8] = match img {
        DynamicImage::ImageRgba8(rgba) => rgba.as_raw(),
        _ => {
            rgba_storage = Some(img.to_rgba8());
            rgba_storage.as_ref().unwrap().as_raw()
        }
    };

    image::codecs::png::PngEncoder::new(&mut raw)
        .write_image(pixels, w, h, image::ExtendedColorType::Rgba8)
        .map_err(|e| e.to_string())?;

    if !optimize {
        return Ok(raw);
    }

    let mut options = Options::max_compression();
    options.strip = StripChunks::Safe;
    oxipng::optimize_from_memory(&raw, &options).map_err(|e| e.to_string())
}

#[cfg(feature = "avif")]
pub fn encode_avif(img: &DynamicImage, quality: u8) -> Result<Vec<u8>, String> {
    use rgb::RGBA8;

    let rgba_storage: Option<image::RgbaImage>;
    let pixels_u8: &[u8] = match img {
        DynamicImage::ImageRgba8(rgba) => rgba.as_raw(),
        _ => {
            rgba_storage = Some(img.to_rgba8());
            rgba_storage.as_ref().unwrap().as_raw()
        }
    };
    let (w, h) = img.dimensions();

    let pixels: &[RGBA8] = unsafe {
        std::slice::from_raw_parts(pixels_u8.as_ptr() as *const RGBA8, pixels_u8.len() / 4)
    };

    ravif::Encoder::new()
        .with_quality(f32::from(quality.clamp(1, 100)))
        .with_speed(6)
        .encode_rgba(ravif::Img::new(pixels, w as usize, h as usize))
        .map_err(|e| e.to_string())
        .map(|r| r.avif_file)
}

#[allow(dead_code)]
pub fn optimize_bytes(
    bytes: &[u8],
    format: crate::api::image::OutputFormat,
) -> Result<Vec<u8>, String> {
    match format {
        crate::api::image::OutputFormat::Jpeg => {
            let img = crate::utils::decode(bytes)?;
            encode_jpeg(&img, 85)
        }
        crate::api::image::OutputFormat::Png => {
            let mut options = Options::max_compression();
            options.strip = StripChunks::Safe;
            oxipng::optimize_from_memory(bytes, &options).map_err(|e| e.to_string())
        }
        other => {
            let img = crate::utils::decode(bytes)?;
            crate::utils::encode(&img, other, 85)
        }
    }
}
