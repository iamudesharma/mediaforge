use fast_image_resize::{images::Image, PixelType, ResizeOptions, Resizer};
use image::{DynamicImage, GenericImageView, RgbaImage};

use crate::api::image::{ImageInfo, ProgressiveDecodeResult, RgbaImageBuffer};
use crate::utils;

pub fn probe(bytes: &[u8]) -> Result<ImageInfo, String> {
    let format = image::guess_format(bytes).ok();
    let img = image::load_from_memory(bytes).map_err(|e| e.to_string())?;
    let (width, height) = img.dimensions();
    Ok(ImageInfo {
        width,
        height,
        format: format.map(|f| format!("{f:?}")),
        exif_orientation: crate::exif::orientation_value(bytes),
    })
}

fn resize_ref(
    img: &DynamicImage,
    width: u32,
    height: u32,
    algorithm: crate::api::image::ResizeAlgorithm,
) -> Result<DynamicImage, String> {
    if width == 0 || height == 0 {
        return Err("width and height must be greater than zero".into());
    }

    let (src_w, src_h) = img.dimensions();
    let pixel_type = match img {
        DynamicImage::ImageRgba8(_) => PixelType::U8x4,
        DynamicImage::ImageRgb8(_) => PixelType::U8x3,
        _ => {
            // Fallback for other formats
            let rgba = img.to_rgba8();
            let src = Image::from_vec_u8(src_w, src_h, rgba.into_raw(), PixelType::U8x4)
                .map_err(|e| e.to_string())?;
            let mut dst = Image::new(width, height, PixelType::U8x4);
            let options = ResizeOptions::new().resize_alg(algorithm.into());
            Resizer::new()
                .resize(&src, &mut dst, &options)
                .map_err(|e| e.to_string())?;
            let out = RgbaImage::from_raw(width, height, dst.into_vec())
                .ok_or_else(|| "failed to build resized image buffer".to_string())?;
            return Ok(DynamicImage::ImageRgba8(out));
        }
    };

    let bytes = img.as_bytes();
    let src = fast_image_resize::images::ImageRef::new(src_w, src_h, bytes, pixel_type)
        .map_err(|e| e.to_string())?;

    let mut dst = Image::new(width, height, pixel_type);
    let options = ResizeOptions::new().resize_alg(algorithm.into());
    Resizer::new()
        .resize(&src, &mut dst, &options)
        .map_err(|e| e.to_string())?;

    let out_img = match pixel_type {
        PixelType::U8x4 => {
            let out = RgbaImage::from_raw(width, height, dst.into_vec())
                .ok_or_else(|| "failed to build resized image buffer".to_string())?;
            DynamicImage::ImageRgba8(out)
        }
        PixelType::U8x3 => {
            let out = image::RgbImage::from_raw(width, height, dst.into_vec())
                .ok_or_else(|| "failed to build resized image buffer".to_string())?;
            DynamicImage::ImageRgb8(out)
        }
        _ => unreachable!(),
    };
    Ok(out_img)
}

pub fn fit_max_edge(img: &DynamicImage, max_edge: u32) -> Result<DynamicImage, String> {
    if max_edge == 0 {
        return Err("max_edge must be greater than zero".into());
    }
    let (w, h) = img.dimensions();
    let longest = w.max(h);
    if longest <= max_edge {
        return Ok(img.clone());
    }
    let scale = max_edge as f32 / longest as f32;
    let tw = (w as f32 * scale).round().max(1.0) as u32;
    let th = (h as f32 * scale).round().max(1.0) as u32;
    resize_ref(
        img,
        tw,
        th,
        crate::api::image::ResizeAlgorithm::Lanczos3,
    )
}

pub fn decode_progressive(
    bytes: &[u8],
    preview_max_edge: u32,
    fix_exif: bool,
) -> Result<ProgressiveDecodeResult, String> {
    let info = probe(bytes)?;
    let full = utils::decode(bytes)?;
    let full = if fix_exif {
        crate::exif::apply_orientation(full, bytes)?
    } else {
        full
    };
    let preview_img = fit_max_edge(&full, preview_max_edge)?;
    let preview_rgba = RgbaImageBuffer::from_dynamic(preview_img);
    let buffer = RgbaImageBuffer::from_dynamic(full);
    Ok(ProgressiveDecodeResult {
        info,
        preview_rgba,
        buffer,
    })
}
