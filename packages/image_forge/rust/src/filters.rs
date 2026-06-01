use image::DynamicImage;
use photon_rs::PhotonImage;
use photon_rs::{
    colour_spaces, conv, effects, filters as photon_filters, native::open_image_from_bytes,
};

pub(crate) mod filmic;
pub(crate) mod lut_hald;
mod mood_presets;
mod swipe_extras;
mod swipe_looks;

use crate::api::image::{FilterPreset, ImageFilter, RgbaImageBuffer};

#[allow(unused_imports)]
pub use mood_presets::{apply_mood_color_rgba, apply_mood_filter_rgba, recipe_for, MoodRecipe};
pub use swipe_extras::{
    apply_dewy_highlight_rgba, apply_glow_rgba, apply_grain_rgba, apply_halation_rgba,
    apply_rgb_split_rgba,
};
#[allow(unused_imports)]
pub use swipe_looks::{
    apply_swipe_look_extras_rgba, apply_swipe_look_grade_rgba,
    display_name as swipe_look_display_name, recipe_for as swipe_look_recipe_for,
};

#[allow(dead_code)]
pub fn apply(bytes: &[u8], filter: ImageFilter) -> Result<DynamicImage, String> {
    let mut photon = open_image_from_bytes(bytes).map_err(|e| e.to_string())?;
    apply_to_photon(&mut photon, filter);
    Ok(photon_to_dynamic(photon))
}

/// Apply a filter directly on an RGBA buffer (no PNG encode/decode).
pub fn apply_rgba(
    mut buffer: RgbaImageBuffer,
    filter: ImageFilter,
) -> Result<RgbaImageBuffer, String> {
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
        ImageFilter::Warmth { amount } => {
            apply_warmth_rgba(&mut buffer.pixels, amount);
            Ok(buffer)
        }
        ImageFilter::Fade { amount } => {
            apply_fade_rgba(&mut buffer.pixels, amount);
            Ok(buffer)
        }
        ImageFilter::Vignette { amount } => {
            apply_vignette_rgba(&mut buffer, amount);
            Ok(buffer)
        }
        ImageFilter::Highlights { amount } => {
            apply_highlights_rgba(&mut buffer.pixels, amount);
            Ok(buffer)
        }
        ImageFilter::Shadows { amount } => {
            apply_shadows_rgba(&mut buffer.pixels, amount);
            Ok(buffer)
        }
        ImageFilter::Structure { amount } => {
            apply_structure_rgba(&mut buffer, amount);
            Ok(buffer)
        }
        ImageFilter::Mood { preset, strength } => Ok(mood_presets::apply_mood_filter_rgba(
            buffer, preset, strength,
        )),
        ImageFilter::SwipeLook { preset, strength } => Ok(
            swipe_looks::apply_swipe_look_grade_rgba(buffer, preset, strength),
        ),
        ImageFilter::LutPng {
            png_bytes,
            strength,
        } => {
            if let Ok((lut_data, lut_size)) = lut_hald::parse_hald_clut(&png_bytes) {
                lut_hald::apply_lut_3d_with_strength_rgba(
                    &mut buffer,
                    &lut_data,
                    lut_size,
                    strength,
                );
            }
            Ok(buffer)
        }
        ImageFilter::SkinSmooth { strength: _ } => Ok(buffer),
        ImageFilter::Beauty { .. } => Ok(buffer),
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
        ImageFilter::Preset { preset, strength } => {
            apply_preset_with_strength(photon, preset, strength);
        }
        ImageFilter::Mood { preset, strength } => {
            let w = photon.get_width();
            let h = photon.get_height();
            let mut buf = RgbaImageBuffer {
                width: w,
                height: h,
                pixels: photon.get_raw_pixels().to_vec(),
            };
            buf = mood_presets::apply_mood_filter_rgba(buf, preset, strength);
            *photon = PhotonImage::new(buf.pixels, w, h);
        }
        ImageFilter::SwipeLook { preset, strength } => {
            let w = photon.get_width();
            let h = photon.get_height();
            let mut buf = RgbaImageBuffer {
                width: w,
                height: h,
                pixels: photon.get_raw_pixels().to_vec(),
            };
            buf = swipe_looks::apply_swipe_look_grade_rgba(buf, preset, strength);
            *photon = PhotonImage::new(buf.pixels, w, h);
        }
        ImageFilter::LutPng {
            png_bytes,
            strength,
        } => {
            let w = photon.get_width();
            let h = photon.get_height();
            let mut buf = RgbaImageBuffer {
                width: w,
                height: h,
                pixels: photon.get_raw_pixels().to_vec(),
            };
            if let Ok((lut_data, lut_size)) = lut_hald::parse_hald_clut(&png_bytes) {
                lut_hald::apply_lut_3d_with_strength_rgba(&mut buf, &lut_data, lut_size, strength);
            }
            *photon = PhotonImage::new(buf.pixels, w, h);
        }
        ImageFilter::Warmth { amount } => {
            let w = photon.get_width();
            let h = photon.get_height();
            let mut px = photon.get_raw_pixels().to_vec();
            apply_warmth_rgba(&mut px, amount);
            *photon = PhotonImage::new(px, w, h);
        }
        ImageFilter::Fade { amount } => {
            let w = photon.get_width();
            let h = photon.get_height();
            let mut px = photon.get_raw_pixels().to_vec();
            apply_fade_rgba(&mut px, amount);
            *photon = PhotonImage::new(px, w, h);
        }
        ImageFilter::Vignette { amount } => {
            let w = photon.get_width();
            let h = photon.get_height();
            let px = photon.get_raw_pixels().to_vec();
            let mut buf = RgbaImageBuffer {
                width: w,
                height: h,
                pixels: px,
            };
            apply_vignette_rgba(&mut buf, amount);
            *photon = PhotonImage::new(buf.pixels, w, h);
        }
        ImageFilter::Highlights { amount } => {
            let w = photon.get_width();
            let h = photon.get_height();
            let mut px = photon.get_raw_pixels().to_vec();
            apply_highlights_rgba(&mut px, amount);
            *photon = PhotonImage::new(px, w, h);
        }
        ImageFilter::Shadows { amount } => {
            let w = photon.get_width();
            let h = photon.get_height();
            let mut px = photon.get_raw_pixels().to_vec();
            apply_shadows_rgba(&mut px, amount);
            *photon = PhotonImage::new(px, w, h);
        }
        ImageFilter::Structure { amount } => {
            let w = photon.get_width();
            let h = photon.get_height();
            let px = photon.get_raw_pixels().to_vec();
            let mut buf = RgbaImageBuffer {
                width: w,
                height: h,
                pixels: px,
            };
            apply_structure_rgba(&mut buf, amount);
            *photon = PhotonImage::new(buf.pixels, w, h);
        }
        ImageFilter::SkinSmooth { .. } => {}
        ImageFilter::Beauty { .. } => {}
    }
}

fn pixel_luminance(chunk: &[u8]) -> f32 {
    (0.299 * chunk[0] as f32 + 0.587 * chunk[1] as f32 + 0.114 * chunk[2] as f32) / 255.0
}

fn scale_rgb(chunk: &mut [u8], factor: f32) {
    let f = factor.clamp(0.0, 2.0);
    for c in 0..3 {
        chunk[c] = (chunk[c] as f32 * f).round().clamp(0.0, 255.0) as u8;
    }
}

pub(crate) fn apply_highlights_rgba(pixels: &mut [u8], amount: f32) {
    let t = (amount / 100.0).clamp(-1.0, 1.0);
    if t.abs() < 0.001 {
        return;
    }
    for chunk in pixels.chunks_exact_mut(4) {
        let l = pixel_luminance(chunk);
        if l > 0.55 {
            let influence = ((l - 0.55) / 0.45).clamp(0.0, 1.0);
            let factor = 1.0 - t * influence * 0.45;
            scale_rgb(chunk, factor);
        }
    }
}

pub(crate) fn apply_shadows_rgba(pixels: &mut [u8], amount: f32) {
    let t = (amount / 100.0).clamp(-1.0, 1.0);
    if t.abs() < 0.001 {
        return;
    }
    for chunk in pixels.chunks_exact_mut(4) {
        let l = pixel_luminance(chunk);
        if l < 0.45 {
            let influence = ((0.45 - l) / 0.45).clamp(0.0, 1.0);
            let lift = t * influence * 0.5;
            for c in 0..3 {
                let v = chunk[c] as f32 / 255.0;
                let out = if t > 0.0 {
                    v + (1.0 - v) * lift
                } else {
                    v * (1.0 + lift)
                };
                chunk[c] = (out * 255.0).round().clamp(0.0, 255.0) as u8;
            }
        }
    }
}

pub(crate) fn apply_structure_rgba(buffer: &mut RgbaImageBuffer, amount: f32) {
    let t = (amount / 100.0).clamp(-1.0, 1.0);
    if t.abs() < 0.001 || buffer.width < 3 || buffer.height < 3 {
        return;
    }
    let w = buffer.width as usize;
    let h = buffer.height as usize;
    let src = buffer.pixels.clone();
    let strength = t * 0.35;
    for y in 1..h - 1 {
        for x in 1..w - 1 {
            let i = (y * w + x) * 4;
            let mut blur = [0f32; 3];
            for dy in -1i32..=1 {
                for dx in -1i32..=1 {
                    let j = ((y as i32 + dy) as usize * w + (x as i32 + dx) as usize) * 4;
                    for c in 0..3 {
                        blur[c] += src[j + c] as f32;
                    }
                }
            }
            for c in 0..3 {
                blur[c] /= 9.0;
                let orig = src[i + c] as f32;
                let detail = orig - blur[c];
                let out = (orig + detail * strength).round().clamp(0.0, 255.0) as u8;
                buffer.pixels[i + c] = out;
            }
        }
    }
}

pub(crate) fn apply_warmth_rgba(pixels: &mut [u8], amount: f32) {
    let t = (amount / 100.0).clamp(-1.0, 1.0);
    if t.abs() < 0.001 {
        return;
    }
    let dr = (t * 28.0).round() as i16;
    let db = (-t * 28.0).round() as i16;
    for chunk in pixels.chunks_exact_mut(4) {
        chunk[0] = (chunk[0] as i16 + dr).clamp(0, 255) as u8;
        chunk[2] = (chunk[2] as i16 + db).clamp(0, 255) as u8;
    }
}

pub(crate) fn apply_fade_rgba(pixels: &mut [u8], amount: f32) {
    let a = amount.clamp(0.0, 1.0);
    if a < 0.001 {
        return;
    }
    for chunk in pixels.chunks_exact_mut(4) {
        for c in 0..3 {
            let v = chunk[c] as f32;
            chunk[c] = (v + (128.0 - v) * a).round().clamp(0.0, 255.0) as u8;
        }
    }
}

pub(crate) fn apply_vignette_rgba(buffer: &mut RgbaImageBuffer, amount: f32) {
    let a = amount.clamp(0.0, 1.0);
    if a < 0.001 || buffer.width == 0 || buffer.height == 0 {
        return;
    }
    let w = buffer.width as f32;
    let h = buffer.height as f32;
    let cx = w * 0.5;
    let cy = h * 0.5;
    let max_r = (cx * cx + cy * cy).sqrt();
    for y in 0..buffer.height {
        for x in 0..buffer.width {
            let dx = x as f32 - cx;
            let dy = y as f32 - cy;
            let dist = (dx * dx + dy * dy).sqrt() / max_r;
            let darken = (dist * dist * a * 0.85).clamp(0.0, 0.95);
            let i = ((y * buffer.width + x) * 4) as usize;
            for c in 0..3 {
                let v = buffer.pixels[i + c] as f32;
                buffer.pixels[i + c] = (v * (1.0 - darken)).round().clamp(0.0, 255.0) as u8;
            }
        }
    }
}

fn apply_preset_with_strength(img: &mut PhotonImage, preset: FilterPreset, strength: f32) {
    let t = strength.clamp(0.0, 1.0);
    if t < 0.001 {
        return;
    }
    if t >= 0.999 {
        apply_preset(img, preset);
        return;
    }
    let before = img.get_raw_pixels().to_vec();
    apply_preset(img, preset);
    let after = img.get_raw_pixels();
    let mut blended = Vec::with_capacity(before.len());
    for (b, a) in before.iter().zip(after.iter()) {
        blended.push((*b as f32 * (1.0 - t) + *a as f32 * t).round() as u8);
    }
    let w = img.get_width();
    let h = img.get_height();
    *img = PhotonImage::new(blended, w, h);
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
    photon_to_rgba_buffer(img)
        .to_dynamic()
        .expect("valid photon buffer")
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
