use image::DynamicImage;

pub fn encode(img: &DynamicImage, components_x: u32, components_y: u32) -> Result<String, String> {
    let rgba = img.to_rgba8();
    let (w, h) = rgba.dimensions();
    blurhash_crate::encode(components_x, components_y, w, h, &rgba.into_raw())
        .map_err(|e| e.to_string())
}

pub fn decode(hash: &str, width: u32, height: u32) -> Result<DynamicImage, String> {
    let pixels = blurhash_crate::decode(hash, width, height, 1.0).map_err(|e| e.to_string())?;
    let buffer = image::RgbaImage::from_raw(width, height, pixels)
        .ok_or_else(|| "failed to build image from blurhash".to_string())?;
    Ok(DynamicImage::ImageRgba8(buffer))
}
