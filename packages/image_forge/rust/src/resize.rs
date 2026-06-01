use fast_image_resize::{images::Image, PixelType, ResizeOptions, Resizer};
use image::{DynamicImage, RgbaImage};

use crate::api::image::{ProcessingBackend, ResizeAlgorithm, RgbaImageBuffer};
use crate::backend::EffectiveBackend;

pub fn resize(
    img: DynamicImage,
    width: u32,
    height: u32,
    algorithm: ResizeAlgorithm,
    backend: ProcessingBackend,
) -> Result<DynamicImage, String> {
    match crate::backend::resolve(backend)? {
        EffectiveBackend::Gpu => {
            #[cfg(feature = "gpu")]
            {
                let buffer = crate::api::image::RgbaImageBuffer::from_dynamic(img);
                let out = crate::gpu::resize_rgba(buffer, width, height, algorithm)?;
                out.to_dynamic()
            }
            #[cfg(not(feature = "gpu"))]
            {
                let _ = (img, width, height, algorithm);
                Err("GPU feature not enabled".into())
            }
        }
        EffectiveBackend::Cpu => resize_cpu(img, width, height, algorithm),
    }
}

/// Resize RGBA pixels in place via `fast_image_resize` (no `DynamicImage` round-trip).
pub fn resize_rgba_buffer(
    mut buffer: RgbaImageBuffer,
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

    let src = Image::from_vec_u8(buffer.width, buffer.height, buffer.pixels, PixelType::U8x4)
        .map_err(|e| e.to_string())?;

    let mut dst = Image::new(width, height, PixelType::U8x4);
    let options = ResizeOptions::new().resize_alg(algorithm.into());
    Resizer::new()
        .resize(&src, &mut dst, &options)
        .map_err(|e| e.to_string())?;

    buffer.width = width;
    buffer.height = height;
    buffer.pixels = dst.into_vec();
    Ok(buffer)
}

fn resize_cpu(
    img: DynamicImage,
    width: u32,
    height: u32,
    algorithm: ResizeAlgorithm,
) -> Result<DynamicImage, String> {
    if width == 0 || height == 0 {
        return Err("width and height must be greater than zero".into());
    }

    let rgba = img.to_rgba8();
    let (src_w, src_h) = rgba.dimensions();
    if src_w == width && src_h == height {
        return Ok(DynamicImage::ImageRgba8(rgba));
    }

    let src = Image::from_vec_u8(src_w, src_h, rgba.into_raw(), PixelType::U8x4)
        .map_err(|e| e.to_string())?;

    let mut dst = Image::new(width, height, PixelType::U8x4);
    let options = ResizeOptions::new().resize_alg(algorithm.into());
    Resizer::new()
        .resize(&src, &mut dst, &options)
        .map_err(|e| e.to_string())?;

    let out = RgbaImage::from_raw(width, height, dst.into_vec())
        .ok_or_else(|| "failed to build resized image buffer".to_string())?;
    Ok(DynamicImage::ImageRgba8(out))
}
