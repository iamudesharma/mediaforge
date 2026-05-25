use image::DynamicImage;
use photon_rs::PhotonImage;
use photon_rs::{
    colour_spaces, conv, effects, filters as photon_filters,
    native::open_image_from_bytes,
};

use crate::api::image::{FilterPreset, ImageFilter, RgbaImageBuffer};

pub fn apply(bytes: &[u8], filter: ImageFilter) -> Result<DynamicImage, String> {
    let mut photon = open_image_from_bytes(bytes).map_err(|e| e.to_string())?;
    apply_to_photon(&mut photon, filter);
    Ok(photon_to_dynamic(photon))
}

/// Apply a filter directly on an RGBA buffer (no PNG encode/decode).
pub fn apply_rgba(mut buffer: RgbaImageBuffer, filter: ImageFilter) -> Result<RgbaImageBuffer, String> {
    match filter {
        ImageFilter::Brightness { amount } => {
            crate::parallel_ops::par_brightness(&mut buffer.pixels, amount);
            Ok(buffer)
        }
        ImageFilter::Contrast { amount } => {
            crate::parallel_ops::par_contrast(&mut buffer.pixels, amount);
            Ok(buffer)
        }
        ImageFilter::Saturation { amount } => {
            crate::parallel_ops::par_saturation(&mut buffer.pixels, amount);
            Ok(buffer)
        }
        ImageFilter::HueRotate { degrees } => {
            crate::parallel_ops::par_hue_rotate(&mut buffer.pixels, degrees);
            Ok(buffer)
        }
        other_filter => {
            let RgbaImageBuffer {
                width,
                height,
                pixels,
            } = buffer;
            let mut photon = PhotonImage::new(pixels, width, height);
            apply_to_photon(&mut photon, other_filter);
            Ok(photon_to_rgba_buffer(photon))
        }
    }
}

pub fn watermark(
    base_bytes: &[u8],
    overlay_bytes: &[u8],
    x: i32,
    y: i32,
) -> Result<DynamicImage, String> {
    let mut base = open_image_from_bytes(base_bytes).map_err(|e| e.to_string())?;
    let overlay = open_image_from_bytes(overlay_bytes).map_err(|e| e.to_string())?;
    photon_rs::multiple::watermark(&mut base, &overlay, x as i64, y as i64);
    Ok(photon_to_dynamic(base))
}

fn apply_to_photon(photon: &mut PhotonImage, filter: ImageFilter) {
    match filter {
        ImageFilter::Blur { radius } => conv::gaussian_blur(photon, radius as i32),
        ImageFilter::Sharpen => conv::sharpen(photon),
        ImageFilter::Brightness { amount } => effects::adjust_brightness(photon, amount),
        ImageFilter::Contrast { amount } => effects::adjust_contrast(photon, amount),
        ImageFilter::Saturation { amount } => colour_spaces::saturate_hsv(photon, amount),
        ImageFilter::HueRotate { degrees } => colour_spaces::hue_rotate_hsv(photon, degrees),
        ImageFilter::Oil { radius, intensity } => effects::oil(photon, radius as i32, intensity),
        ImageFilter::FrostedGlass => effects::frosted_glass(photon),
        ImageFilter::Pixelize { size } => effects::pixelize(photon, size as i32),
        ImageFilter::Solarize => effects::solarize(photon),
        ImageFilter::Preset(preset) => apply_preset(photon, preset),
    }
}

fn apply_preset(img: &mut PhotonImage, preset: FilterPreset) {
    match preset {
        FilterPreset::Neue => photon_filters::neue(img),
        FilterPreset::Lix => photon_filters::lix(img),
        FilterPreset::Ryo => photon_filters::ryo(img),
        FilterPreset::Lofi => photon_filters::lofi(img),
        FilterPreset::PastelPink => photon_filters::pastel_pink(img),
        FilterPreset::Golden => photon_filters::golden(img),
        FilterPreset::Cali => photon_filters::cali(img),
        FilterPreset::Dramatic => photon_filters::dramatic(img),
        FilterPreset::Firenze => photon_filters::firenze(img),
        FilterPreset::Obsidian => photon_filters::obsidian(img),
        FilterPreset::DuotoneViolette => photon_filters::duotone_violette(img),
        FilterPreset::DuotoneHorizon => photon_filters::duotone_horizon(img),
        FilterPreset::DuotoneLilac => photon_filters::duotone_lilac(img),
        FilterPreset::DuotoneOchre => photon_filters::duotone_ochre(img),
    }
}

fn photon_to_dynamic(img: PhotonImage) -> DynamicImage {
    photon_to_rgba_buffer(img).to_dynamic().expect("valid photon buffer")
}

fn photon_to_rgba_buffer(img: PhotonImage) -> RgbaImageBuffer {
    let width = img.get_width();
    let height = img.get_height();
    let raw_pixels = img.get_raw_pixels().to_vec();
    RgbaImageBuffer {
        width,
        height,
        pixels: raw_pixels,
    }
}
