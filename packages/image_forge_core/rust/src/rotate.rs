use image::{DynamicImage, Rgba, RgbaImage};
use imageproc::geometric_transformations::{rotate_about_center, Interpolation};

use crate::api::image::{Rotation, RgbaImageBuffer};

pub fn rotate_rgba_arbitrary(buffer: RgbaImageBuffer, degrees: f32) -> Result<RgbaImageBuffer, String> {
    if degrees.abs() < 0.001 {
        return Ok(buffer);
    }
    let img = RgbaImage::from_raw(buffer.width, buffer.height, buffer.pixels)
        .ok_or_else(|| "invalid RGBA buffer".to_string())?;
    let radians = degrees.to_radians();
    let rotated = rotate_about_center(
        &img,
        radians,
        Interpolation::Bilinear,
        Rgba([0, 0, 0, 0]),
    );
    Ok(RgbaImageBuffer {
        width: rotated.width(),
        height: rotated.height(),
        pixels: rotated.into_raw(),
    })
}

pub fn rotate(img: DynamicImage, rotation: Rotation) -> DynamicImage {
    match rotation {
        Rotation::Rotate90 => img.rotate90(),
        Rotation::Rotate180 => img.rotate180(),
        Rotation::Rotate270 => img.rotate270(),
        Rotation::FlipHorizontal => DynamicImage::ImageRgba8(image::imageops::flip_horizontal(&img.to_rgba8())),
        Rotation::FlipVertical => DynamicImage::ImageRgba8(image::imageops::flip_vertical(&img.to_rgba8())),
    }
}
