use crate::api::image::RgbaImageBuffer;

/// Soft bloom on bright pixels (0 = off, 1 = strong).
pub fn apply_glow_rgba(buffer: &mut RgbaImageBuffer, strength: f32) {
    let strength = strength.clamp(0.0, 1.0);
    if strength <= 0.001 {
        return;
    }
    let w = buffer.width as usize;
    let h = buffer.height as usize;
    let src = buffer.pixels.clone();

    // Luma-gated glow source: only highlights above 0.55 luma contribute to bloom
    let mut glow_src = src.clone();
    for chunk in glow_src.chunks_exact_mut(4) {
        let luma =
            (chunk[0] as f32 * 0.299 + chunk[1] as f32 * 0.587 + chunk[2] as f32 * 0.114) / 255.0;
        if luma < 0.55 {
            chunk[0] = 0;
            chunk[1] = 0;
            chunk[2] = 0;
        } else {
            let factor = ((luma - 0.55) / 0.45).clamp(0.0, 1.0);
            chunk[0] = (chunk[0] as f32 * factor) as u8;
            chunk[1] = (chunk[1] as f32 * factor) as u8;
            chunk[2] = (chunk[2] as f32 * factor) as u8;
        }
    }

    // dream-like Gaussian bloom with radius 10
    let blurred = separable_blur(&glow_src, w, h, 10);

    // Screen blend the bloom back onto the original image
    for y in 0..h {
        for x in 0..w {
            let i = (y * w + x) * 4;
            let bloom_factor = strength * 0.8;

            for c in 0..3 {
                let base = src[i + c] as f32 / 255.0;
                let bloom = (blurred[i + c] as f32 / 255.0) * bloom_factor;
                // Screen blend formula: 1 - (1 - base) * (1 - bloom)
                let blended = 1.0 - (1.0 - base) * (1.0 - bloom);
                buffer.pixels[i + c] = (blended * 255.0).clamp(0.0, 255.0) as u8;
            }
        }
    }
}

/// Film grain noise modulated by luma.
pub fn apply_grain_rgba(buffer: &mut RgbaImageBuffer, strength: f32) {
    let strength = strength.clamp(0.0, 1.0);
    if strength <= 0.001 {
        return;
    }
    let w = buffer.width as usize;
    let h = buffer.height as usize;
    let mut seed = (w as u32).wrapping_mul(2654435761) ^ (h as u32).wrapping_mul(1597334677);
    for y in 0..h {
        for x in 0..w {
            seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
            let noise = ((seed >> 16) & 0xff) as f32 / 255.0 - 0.5;
            let i = (y * w + x) * 4;
            let amp = strength * 28.0;
            for c in 0..3 {
                buffer.pixels[i + c] =
                    (buffer.pixels[i + c] as f32 + noise * amp).clamp(0.0, 255.0) as u8;
            }
        }
    }
}

/// Red halation on highlights (vintage).
pub fn apply_halation_rgba(buffer: &mut RgbaImageBuffer, strength: f32) {
    let strength = strength.clamp(0.0, 1.0);
    if strength <= 0.001 {
        return;
    }
    let w = buffer.width as usize;
    let h = buffer.height as usize;
    let src = buffer.pixels.clone();

    // Halation is red bleeding on sharp highlight transitions
    let mut halation_src = src.clone();
    for chunk in halation_src.chunks_exact_mut(4) {
        let luma =
            (chunk[0] as f32 * 0.299 + chunk[1] as f32 * 0.587 + chunk[2] as f32 * 0.114) / 255.0;
        if luma < 0.7 {
            chunk[0] = 0;
            chunk[1] = 0;
            chunk[2] = 0;
        }
    }

    let blurred = separable_blur(&halation_src, w, h, 6);

    for y in 0..h {
        for x in 0..w {
            let i = (y * w + x) * 4;
            let luma =
                (src[i] as f32 * 0.299 + src[i + 1] as f32 * 0.587 + src[i + 2] as f32 * 0.114)
                    / 255.0;

            if luma > 0.6 {
                let t = ((luma - 0.6) / 0.4).clamp(0.0, 1.0) * strength;
                let r_bleed = blurred[i] as f32 * t * 0.5;

                buffer.pixels[i] = (src[i] as f32 + r_bleed).clamp(0.0, 255.0) as u8;
                buffer.pixels[i + 1] =
                    (src[i + 1] as f32 * (1.0 - t * 0.1)).clamp(0.0, 255.0) as u8;
                buffer.pixels[i + 2] =
                    (src[i + 2] as f32 * (1.0 - t * 0.1)).clamp(0.0, 255.0) as u8;
            }
        }
    }
}

/// Specular dewy lift on mid/high tones (K-beauty glass skin shine).
pub fn apply_dewy_highlight_rgba(buffer: &mut RgbaImageBuffer, strength: f32) {
    let strength = strength.clamp(0.0, 1.0);
    if strength <= 0.001 {
        return;
    }
    let w = buffer.width as usize;
    let h = buffer.height as usize;
    let src = buffer.pixels.clone();

    // Create a specular map of highlights
    let mut spec_map = vec![0u8; src.len()];
    for y in 0..h {
        for x in 0..w {
            let i = (y * w + x) * 4;
            let luma =
                (src[i] as f32 * 0.299 + src[i + 1] as f32 * 0.587 + src[i + 2] as f32 * 0.114)
                    / 255.0;
            if luma > 0.4 {
                let spec = ((luma - 0.4) / 0.6).clamp(0.0, 1.0).powf(2.0) * 255.0;
                spec_map[i] = spec as u8;
                spec_map[i + 1] = spec as u8;
                spec_map[i + 2] = spec as u8;
            }
        }
    }

    // Blur the specular map for a soft dewy glow
    let blurred_spec = separable_blur(&spec_map, w, h, 4);

    for y in 0..h {
        for x in 0..w {
            let i = (y * w + x) * 4;
            let lift = (blurred_spec[i] as f32 / 255.0) * strength * 25.0;
            if lift > 0.001 {
                for c in 0..3 {
                    buffer.pixels[i + c] =
                        (buffer.pixels[i + c] as f32 + lift).clamp(0.0, 255.0) as u8;
                }
            }
        }
    }
}

/// Subtle RGB channel offset (cyber / lo-fi).
pub fn apply_rgb_split_rgba(buffer: &mut RgbaImageBuffer, strength: f32) {
    let strength = strength.clamp(0.0, 1.0);
    if strength <= 0.001 {
        return;
    }
    let w = buffer.width as usize;
    let h = buffer.height as usize;
    let src = buffer.pixels.clone();
    let shift = (strength * 4.0).round() as i32;
    for y in 0..h {
        for x in 0..w {
            let i = (y * w + x) * 4;
            let xr = x.saturating_sub(shift as usize).min(w - 1);
            let xb = (x + shift as usize).min(w - 1);
            let ri = (y * w + xr) * 4;
            let bi = (y * w + xb) * 4 + 2;
            buffer.pixels[i] = src[ri];
            buffer.pixels[i + 2] = src[bi];
        }
    }
}

/// High-performance two-pass separable Gaussian blur (runs in O(N * radius) time)
fn separable_blur(pixels: &[u8], w: usize, h: usize, radius: i32) -> Vec<u8> {
    if w == 0 || h == 0 || pixels.is_empty() {
        return pixels.to_vec();
    }
    let r = radius.max(1);
    let sigma = r as f32 / 2.0;

    // Precompute Gaussian weights
    let mut weights = Vec::with_capacity((r * 2 + 1) as usize);
    let mut sum = 0.0;
    for i in -r..=r {
        let weight = (-(i as f32 * i as f32) / (2.0 * sigma * sigma)).exp();
        weights.push(weight);
        sum += weight;
    }
    for w_val in &mut weights {
        *w_val /= sum;
    }

    // Horizontal Pass
    let mut temp = vec![0u8; pixels.len()];
    for y in 0..h {
        for x in 0..w {
            let mut val = [0.0; 3];
            for (step, &weight) in (-r..=r).zip(weights.iter()) {
                let cx = (x as i32 + step).clamp(0, w as i32 - 1) as usize;
                let i = (y * w + cx) * 4;
                val[0] += pixels[i] as f32 * weight;
                val[1] += pixels[i + 1] as f32 * weight;
                val[2] += pixels[i + 2] as f32 * weight;
            }
            let idx = (y * w + x) * 4;
            temp[idx] = val[0].clamp(0.0, 255.0) as u8;
            temp[idx + 1] = val[1].clamp(0.0, 255.0) as u8;
            temp[idx + 2] = val[2].clamp(0.0, 255.0) as u8;
            temp[idx + 3] = pixels[idx + 3];
        }
    }

    // Vertical Pass
    let mut out = vec![0u8; pixels.len()];
    for y in 0..h {
        for x in 0..w {
            let mut val = [0.0; 3];
            for (step, &weight) in (-r..=r).zip(weights.iter()) {
                let cy = (y as i32 + step).clamp(0, h as i32 - 1) as usize;
                let i = (cy * w + x) * 4;
                val[0] += temp[i] as f32 * weight;
                val[1] += temp[i + 1] as f32 * weight;
                val[2] += temp[i + 2] as f32 * weight;
            }
            let idx = (y * w + x) * 4;
            out[idx] = val[0].clamp(0.0, 255.0) as u8;
            out[idx + 1] = val[1].clamp(0.0, 255.0) as u8;
            out[idx + 2] = val[2].clamp(0.0, 255.0) as u8;
            out[idx + 3] = temp[idx + 3];
        }
    }
    out
}
