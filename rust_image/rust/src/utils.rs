use image::{DynamicImage, GenericImageView, ImageEncoder, ImageFormat};

use crate::api::image::OutputFormat;

pub fn decode(bytes: &[u8]) -> Result<DynamicImage, String> {
    image::load_from_memory(bytes).map_err(|e| e.to_string())
}

pub fn encode(img: &DynamicImage, format: OutputFormat, quality: u8) -> Result<Vec<u8>, String> {
    match format {
        OutputFormat::Jpeg => crate::compress::encode_jpeg(img, quality),
        OutputFormat::Png => crate::compress::encode_png(img, true),
        OutputFormat::WebP => encode_webp(img),
        OutputFormat::Avif => encode_avif(img, quality),
    }
}

fn encode_webp(img: &DynamicImage) -> Result<Vec<u8>, String> {
    let rgba = img.to_rgba8();
    let mut buf = Vec::new();
    image::codecs::webp::WebPEncoder::new_lossless(&mut buf)
        .encode(
            rgba.as_raw(),
            rgba.width(),
            rgba.height(),
            image::ExtendedColorType::Rgba8,
        )
        .map_err(|e| e.to_string())?;
    Ok(buf)
}

fn encode_avif(img: &DynamicImage, quality: u8) -> Result<Vec<u8>, String> {
    #[cfg(feature = "avif")]
    {
        crate::compress::encode_avif(img, quality)
    }
    #[cfg(not(feature = "avif"))]
    {
        let _ = (img, quality);
        Err("AVIF support is disabled. Rebuild with the `avif` feature.".into())
    }
}

pub fn detect_format(bytes: &[u8]) -> Option<ImageFormat> {
    image::guess_format(bytes).ok()
}
