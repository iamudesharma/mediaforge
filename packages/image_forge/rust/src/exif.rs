use exif::{In, Reader, Tag};
use image::DynamicImage;

pub fn apply_orientation(mut img: DynamicImage, bytes: &[u8]) -> Result<DynamicImage, String> {
    let Some(orientation) = read_orientation(bytes) else {
        return Ok(img);
    };

    img = match orientation {
        2 => DynamicImage::ImageRgba8(image::imageops::flip_horizontal(&img.to_rgba8())),
        3 => img.rotate180(),
        4 => DynamicImage::ImageRgba8(image::imageops::flip_vertical(&img.to_rgba8())),
        5 => {
            let flipped = image::imageops::flip_horizontal(&img.to_rgba8());
            DynamicImage::ImageRgba8(flipped).rotate90()
        }
        6 => img.rotate90(),
        7 => {
            let flipped = image::imageops::flip_horizontal(&img.to_rgba8());
            DynamicImage::ImageRgba8(flipped).rotate270()
        }
        8 => img.rotate270(),
        _ => img,
    };

    Ok(img)
}

pub fn orientation_value(bytes: &[u8]) -> Option<u16> {
    read_orientation(bytes)
}

fn read_orientation(bytes: &[u8]) -> Option<u16> {
    let mut cursor = std::io::Cursor::new(bytes);
    let exif = Reader::new().read_from_container(&mut cursor).ok()?;
    let field = exif.get_field(Tag::Orientation, In::PRIMARY)?;
    field.value.get_uint(0).map(|v| v as u16)
}
