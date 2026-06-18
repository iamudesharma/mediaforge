//! CPU overlay post-effects (v3) applied to RGBA buffers before compositing.

use crate::types::{OverlayEffect, OverlayEffectKind};

/// Apply active effects to RGBA [pixels] (width × height × 4).
pub fn apply_overlay_effects(
    pixels: &mut [u8],
    width: u32,
    height: u32,
    effects: &[OverlayEffect],
    local_ms: u64,
) {
    for effect in effects {
        if effect.kind == OverlayEffectKind::None {
            continue;
        }
        if !effect_active(effect, local_ms) {
            continue;
        }
        let t = effect_intensity(effect, local_ms);
        let strength = effect.intensity.clamp(0.0, 1.0) * t;
        if strength <= 0.001 {
            continue;
        }
        match effect.kind {
            OverlayEffectKind::Glitch => apply_glitch(pixels, width, height, strength, local_ms),
            OverlayEffectKind::Glow => apply_glow(pixels, width, height, strength),
            OverlayEffectKind::ChromaticAberration | OverlayEffectKind::RgbSplit => {
                apply_rgb_split(pixels, width, height, strength)
            }
            OverlayEffectKind::MotionBlur => apply_motion_blur(pixels, width, height, strength),
            OverlayEffectKind::Shake => apply_shake(pixels, width, height, strength, local_ms),
            OverlayEffectKind::None => {}
        }
    }
}

fn effect_active(effect: &OverlayEffect, local_ms: u64) -> bool {
    if local_ms < effect.start_ms {
        return false;
    }
    if effect.duration_ms == 0 {
        return true;
    }
    local_ms < effect.start_ms + effect.duration_ms
}

fn effect_intensity(effect: &OverlayEffect, local_ms: u64) -> f32 {
    if effect.duration_ms == 0 {
        return 1.0;
    }
    let elapsed = local_ms.saturating_sub(effect.start_ms) as f32;
    let dur = effect.duration_ms as f32;
    if elapsed >= dur {
        return 0.0;
    }
    // Fade effect strength in/out within window.
    let mid = (elapsed / dur).clamp(0.0, 1.0);
    if mid < 0.15 {
        mid / 0.15
    } else if mid > 0.85 {
        (1.0 - mid) / 0.15
    } else {
        1.0
    }
}

fn apply_glitch(pixels: &mut [u8], width: u32, height: u32, strength: f32, seed: u64) {
    let offset = (4.0 + 12.0 * strength) as i32;
    let slice_h = (height as f32 * 0.08).max(2.0) as u32;
    let mut copy = pixels.to_vec();
    for y in 0..height {
        if (y + seed as u32) % 7 != 0 {
            continue;
        }
        let jitter = (((seed.wrapping_mul(y as u64 + 1)) % 5) as i32 - 2) * (strength * 3.0) as i32;
        for x in 0..width {
            let sx = (x as i32 + jitter).clamp(0, width as i32 - 1) as u32;
            let di = ((y * width + x) * 4) as usize;
            let si_r = ((y * width + sx.saturating_sub(offset as u32 / 2).min(width - 1)) * 4) as usize;
            let si_b = ((y * width + (sx + offset as u32 / 2).min(width - 1)) * 4) as usize;
            if di + 3 < pixels.len() && si_r + 2 < copy.len() && si_b + 2 < copy.len() {
                pixels[di] = copy[si_r];
                pixels[di + 2] = copy[si_b + 2];
            }
        }
        let _ = slice_h;
    }
}

fn apply_rgb_split(pixels: &mut [u8], width: u32, height: u32, strength: f32) {
    let offset = (2.0 + 6.0 * strength) as i32;
    let copy = pixels.to_vec();
    for y in 0..height {
        for x in 0..width {
            let di = ((y * width + x) * 4) as usize;
            let xr = (x as i32 - offset).clamp(0, width as i32 - 1) as u32;
            let xb = (x as i32 + offset).clamp(0, width as i32 - 1) as u32;
            let si_r = ((y * width + xr) * 4) as usize;
            let si_b = ((y * width + xb) * 4) as usize;
            if di + 3 < pixels.len() && si_r + 2 < copy.len() && si_b + 2 < copy.len() {
                pixels[di] = copy[si_r];
                pixels[di + 2] = copy[si_b + 2];
            }
        }
    }
}

fn apply_glow(pixels: &mut [u8], width: u32, height: u32, strength: f32) {
    let copy = pixels.to_vec();
    let radius = (2.0 + 4.0 * strength) as i32;
    for y in 0..height as i32 {
        for x in 0..width as i32 {
            let mut acc = [0f32; 3];
            let mut count = 0f32;
            for dy in -radius..=radius {
                for dx in -radius..=radius {
                    let ny = y + dy;
                    let nx = x + dx;
                    if ny < 0 || nx < 0 || ny >= height as i32 || nx >= width as i32 {
                        continue;
                    }
                    let si = ((ny as u32 * width + nx as u32) * 4) as usize;
                    let a = copy[si + 3] as f32 / 255.0;
                    if a < 0.05 {
                        continue;
                    }
                    for c in 0..3 {
                        acc[c] += copy[si + c] as f32 * a;
                    }
                    count += a;
                }
            }
            if count < 0.01 {
                continue;
            }
            let di = ((y as u32 * width + x as u32) * 4) as usize;
            if di + 3 >= pixels.len() {
                continue;
            }
            let glow = 0.35 * strength;
            for c in 0..3 {
                let base = pixels[di + c] as f32;
                let g = acc[c] / count;
                pixels[di + c] = (base + g * glow).clamp(0.0, 255.0) as u8;
            }
        }
    }
}

fn apply_motion_blur(pixels: &mut [u8], width: u32, height: u32, strength: f32) {
    let copy = pixels.to_vec();
    let steps = (2.0 + 4.0 * strength) as i32;
    for y in 0..height {
        for x in 0..width {
            let di = ((y * width + x) * 4) as usize;
            let mut acc = [0f32; 4];
            for s in 0..steps {
                let nx = (x as i32 - s).clamp(0, width as i32 - 1) as u32;
                let si = ((y * width + nx) * 4) as usize;
                if si + 3 >= copy.len() {
                    continue;
                }
                for c in 0..4 {
                    acc[c] += copy[si + c] as f32;
                }
            }
            if di + 3 < pixels.len() {
                for c in 0..4 {
                    pixels[di + c] = (acc[c] / steps as f32) as u8;
                }
            }
        }
    }
}

fn apply_shake(pixels: &mut [u8], width: u32, height: u32, strength: f32, seed: u64) {
    let shift = (((seed % 7) as i32) - 3) as f32 * strength * 2.0;
    let copy = pixels.to_vec();
    let row_bytes = (width * 4) as usize;
    for y in 0..height {
        let offset = shift.round() as i32;
        for x in 0..width as i32 {
            let sx = (x - offset).clamp(0, width as i32 - 1) as u32;
            let di = ((y * width + x as u32) * 4) as usize;
            let si = ((y * width + sx) * 4) as usize;
            if di + 3 < pixels.len() && si + 3 < copy.len() {
                pixels[di..di + 4].copy_from_slice(&copy[si..si + 4]);
            }
        }
        let _ = row_bytes;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn glow_does_not_panic_on_small_buffer() {
        let mut px = vec![0u8, 0, 0, 255, 255, 255, 255, 255];
        apply_glow(&mut px, 2, 1, 0.5);
    }
}
