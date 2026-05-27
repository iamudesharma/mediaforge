use image::{DynamicImage, GenericImageView};

pub fn crop(img: DynamicImage, x: u32, y: u32, width: u32, height: u32) -> Result<DynamicImage, String> {
    let (img_w, img_h) = img.dimensions();
    if width == 0 || height == 0 {
        return Err("crop width and height must be greater than zero".into());
    }
    if x.saturating_add(width) > img_w || y.saturating_add(height) > img_h {
        return Err(format!(
            "crop rect ({x},{y},{width}x{height}) exceeds image bounds ({img_w}x{img_h})"
        ));
    }
    Ok(img.crop_imm(x, y, width, height))
}
