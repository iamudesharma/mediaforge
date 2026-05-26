use crate::api::image::{MoodFilterPreset, RgbaImageBuffer};
use crate::filters::{apply_mood_color_rgba, recipe_for};

/// Edge length of baked 3D LUT cubes (33³ ≈ 36k entries).
pub const LUT_SIZE: u32 = 33;

pub fn lut_entry_count() -> usize {
    (LUT_SIZE as usize).pow(3)
}

pub fn lut_byte_len() -> usize {
    lut_entry_count() * 4
}

/// Bake a 33³ RGBA LUT for [preset] using the color-only mood recipe.
pub fn bake_mood_lut(preset: MoodFilterPreset) -> Vec<u8> {
    let recipe = recipe_for(preset);
    let size = LUT_SIZE as usize;
    let mut data = vec![0u8; lut_byte_len()];

    for b in 0..size {
        for g in 0..size {
            for r in 0..size {
                let rf = channel_from_index(r, size);
                let gf = channel_from_index(g, size);
                let bf = channel_from_index(b, size);
                let mut buf = RgbaImageBuffer {
                    width: 1,
                    height: 1,
                    pixels: vec![rf, gf, bf, 255],
                };
                apply_mood_color_rgba(&mut buf, recipe);
                let idx = (r + g * size + b * size * size) * 4;
                data[idx..idx + 4].copy_from_slice(&buf.pixels);
            }
        }
    }
    data
}

fn channel_from_index(i: usize, size: usize) -> u8 {
    if size <= 1 {
        return 0;
    }
    ((i as f32 / (size - 1) as f32) * 255.0).round().clamp(0.0, 255.0) as u8
}

/// Pack LUT RGBA bytes into wgpu-friendly u32 RGBA pixels.
pub fn pack_lut_pixels(lut: &[u8]) -> Vec<u32> {
    debug_assert_eq!(lut.len(), lut_byte_len());
    lut.chunks_exact(4)
        .map(|c| u32::from_le_bytes([c[0], c[1], c[2], c[3]]))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn baked_lut_identity_corners() {
        let lut = bake_mood_lut(MoodFilterPreset::Rose);
        assert_eq!(lut.len(), lut_byte_len());
        // Black corner should remain near black after Rose (warm but dark input).
        let black_idx = 0;
        assert!(lut[black_idx] <= 40);
    }
}
