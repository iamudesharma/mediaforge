use std::sync::OnceLock;

use crate::api::image::MoodFilterPreset;

use super::lut_bake::{bake_mood_lut, lut_byte_len, pack_lut_pixels, LUT_SIZE};

static MOOD_LUT_CACHE: OnceLock<Vec<Vec<u32>>> = OnceLock::new();

pub fn lut_size() -> u32 {
    LUT_SIZE
}

/// Lazily baked 3D LUT cubes for all mood presets (once per process).
pub fn mood_lut_packed(preset: MoodFilterPreset) -> &'static [u32] {
    let all = MOOD_LUT_CACHE.get_or_init(|| {
        all_mood_presets()
            .into_iter()
            .map(|p| pack_lut_pixels(&bake_mood_lut(p)))
            .collect()
    });
    &all[preset_index(preset)]
}

fn all_mood_presets() -> [MoodFilterPreset; 16] {
    [
        MoodFilterPreset::Rose,
        MoodFilterPreset::Clarendon,
        MoodFilterPreset::Juno,
        MoodFilterPreset::Valencia,
        MoodFilterPreset::Lark,
        MoodFilterPreset::Reyes,
        MoodFilterPreset::Gingham,
        MoodFilterPreset::LoFi,
        MoodFilterPreset::Moon,
        MoodFilterPreset::Aden,
        MoodFilterPreset::Perpetua,
        MoodFilterPreset::Mayfair,
        MoodFilterPreset::Hudson,
        MoodFilterPreset::Sierra,
        MoodFilterPreset::Willow,
        MoodFilterPreset::Inkwell,
    ]
}

fn preset_index(preset: MoodFilterPreset) -> usize {
    match preset {
        MoodFilterPreset::Rose => 0,
        MoodFilterPreset::Clarendon => 1,
        MoodFilterPreset::Juno => 2,
        MoodFilterPreset::Valencia => 3,
        MoodFilterPreset::Lark => 4,
        MoodFilterPreset::Reyes => 5,
        MoodFilterPreset::Gingham => 6,
        MoodFilterPreset::LoFi => 7,
        MoodFilterPreset::Moon => 8,
        MoodFilterPreset::Aden => 9,
        MoodFilterPreset::Perpetua => 10,
        MoodFilterPreset::Mayfair => 11,
        MoodFilterPreset::Hudson => 12,
        MoodFilterPreset::Sierra => 13,
        MoodFilterPreset::Willow => 14,
        MoodFilterPreset::Inkwell => 15,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn mood_lut_cache_len() {
        let lut = mood_lut_packed(MoodFilterPreset::Juno);
        assert_eq!(lut.len(), lut_byte_len() / 4);
    }
}
