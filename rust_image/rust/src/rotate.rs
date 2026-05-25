use image::DynamicImage;

use crate::api::image::Rotation;

pub fn rotate(img: DynamicImage, rotation: Rotation) -> DynamicImage {
    match rotation {
        Rotation::Rotate90 => img.rotate90(),
        Rotation::Rotate180 => img.rotate180(),
        Rotation::Rotate270 => img.rotate270(),
        Rotation::FlipHorizontal => DynamicImage::ImageRgba8(image::imageops::flip_horizontal(&img.to_rgba8())),
        Rotation::FlipVertical => DynamicImage::ImageRgba8(image::imageops::flip_vertical(&img.to_rgba8())),
    }
}
