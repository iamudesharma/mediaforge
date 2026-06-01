//! Synthetic fixtures for integration tests (no disk I/O).

use image::codecs::jpeg::JpegEncoder;
use image::codecs::png::PngEncoder;
use image::{ExtendedColorType, GenericImageView, ImageEncoder, RgbaImage};

use crate::api::image::RgbaImageBuffer;

/// Deterministic RGBA buffer: channel values vary with `(x, y)`.
pub fn tiny_rgba(w: u32, h: u32) -> RgbaImageBuffer {
    synthetic_rgba(w, h)
}

/// Alias for integration tests (`api_advanced.rs`).
pub fn synthetic_rgba(w: u32, h: u32) -> RgbaImageBuffer {
    let mut pixels = Vec::with_capacity((w * h * 4) as usize);
    for y in 0..h {
        for x in 0..w {
            let r = ((x.wrapping_mul(17).wrapping_add(y.wrapping_mul(31))) % 256) as u8;
            let g = ((x.wrapping_mul(23).wrapping_add(y.wrapping_mul(13))) % 256) as u8;
            let b = ((x.wrapping_mul(7).wrapping_add(y.wrapping_mul(41))) % 256) as u8;
            pixels.extend_from_slice(&[r, g, b, 255]);
        }
    }
    RgbaImageBuffer {
        width: w,
        height: h,
        pixels,
    }
}

fn rgba_to_image(buf: &RgbaImageBuffer) -> RgbaImage {
    RgbaImage::from_raw(buf.width, buf.height, buf.pixels.clone()).expect("tiny_rgba dimensions")
}

/// JPEG bytes via `image` 0.25 encoder (quality 1–100).
pub fn synthetic_jpeg(w: u32, h: u32, quality: u8) -> Vec<u8> {
    let rgba = rgba_to_image(&tiny_rgba(w, h));
    let rgb = image::DynamicImage::ImageRgba8(rgba).into_rgb8();
    let mut out = Vec::new();
    let mut enc = JpegEncoder::new_with_quality(&mut out, quality);
    enc.encode(
        rgb.as_raw(),
        rgb.width(),
        rgb.height(),
        ExtendedColorType::Rgb8,
    )
    .expect("jpeg encode");
    out
}

pub fn synthetic_webp(w: u32, h: u32) -> Vec<u8> {
    let rgba = rgba_to_image(&tiny_rgba(w, h));
    let mut out = Vec::new();
    let enc = image::codecs::webp::WebPEncoder::new_lossless(&mut out);
    enc.write_image(
        rgba.as_raw(),
        rgba.width(),
        rgba.height(),
        ExtendedColorType::Rgba8,
    )
    .expect("webp encode");
    out
}

pub fn synthetic_png(w: u32, h: u32) -> Vec<u8> {
    let rgba = rgba_to_image(&tiny_rgba(w, h));
    let mut out = Vec::new();
    let enc = PngEncoder::new(&mut out);
    enc.write_image(
        rgba.as_raw(),
        rgba.width(),
        rgba.height(),
        ExtendedColorType::Rgba8,
    )
    .expect("png encode");
    out
}

pub fn decode_dims(bytes: &[u8]) -> (u32, u32) {
    let img = image::load_from_memory(bytes).expect("decode_dims");
    img.dimensions()
}

/// Alias used by integration tests.
pub fn rgb_mean(buf: &RgbaImageBuffer) -> f64 {
    mean_r_channel(buf)
}

/// Mean red channel (0–255) for brightness assertions.
pub fn mean_r_channel(buf: &RgbaImageBuffer) -> f64 {
    let n = buf.pixels.len() / 4;
    if n == 0 {
        return 0.0;
    }
    let sum: u64 = buf.pixels.chunks(4).map(|c| c[0] as u64).sum();
    sum as f64 / n as f64
}

/// Solid-color JPEG (no EXIF orientation tag).
pub fn plain_jpeg(w: u32, h: u32) -> Vec<u8> {
    synthetic_jpeg(w, h, 85)
}

// Complex EXIF JPEG synthesis (kamadak round-trip) is intentionally skipped;
// `read_exif_orientation(plain_jpeg)` is covered in api_image tests.
