use crate::api::face::{BeautyParams, LipTintPreset};
use crate::api::image::{RgbaImageBuffer, SwipeLookPreset};

use super::mood_presets::MoodRecipe;
use super::swipe_extras::{
    apply_dewy_highlight_rgba, apply_glow_rgba, apply_grain_rgba, apply_halation_rgba,
    apply_rgb_split_rgba,
};

/// Optional post-grade effects (Phase 1+).
#[derive(Debug, Clone, Copy, Default)]
#[allow(dead_code)]
pub struct SwipeLookExtras {
    pub glow: f32,
    pub grain: f32,
    pub sharpen: f32,
    pub skin_preserve_detail: f32,
    pub halation: f32,
    pub rgb_split: f32,
}

/// Combo swipe look: global mood grade + regional beauty params.
#[derive(Debug, Clone, Copy)]
#[allow(dead_code)]
pub struct SwipeLookRecipe {
    pub mood: MoodRecipe,
    pub beauty: BeautyParams,
    pub extras: SwipeLookExtras,
}

pub fn recipe_for(preset: SwipeLookPreset) -> SwipeLookRecipe {
    match preset {
        SwipeLookPreset::CleanGirlGlow => SwipeLookRecipe {
            mood: MoodRecipe {
                warmth: 0.0,
                fade: 0.0,
                vignette: 0.0,
                tone_curve: 0.28,
                saturation: 1.03,
                brightness: 0,
                highlights: 0.0,
                shadows: 0.0,
                hue_degrees: 0.0,
                structure: 0.0,
                highlight_rolloff: 0.42,
                shadow_tint: [0.00, 0.01, 0.03],
                highlight_tint: [0.05, 0.03, 0.01],
                midtone_tint: [0.02, 0.01, 0.00],
                skin_protection: 0.35,
                contrast: 0.0,
            },
            beauty: BeautyParams {
                skin_smooth: 0.34,
                eye_brighten: 0.0,
                lip_tint: LipTintPreset::None,
                lip_tint_strength: 0.0,
                lip_plump: 0.0,
                blush: 0.0,
                under_eye: 0.0,
                teeth_whiten: 0.0,
                skin_preserve_detail: 0.25,
                eye_enlarge: 0.0,
                jaw_slim: 0.0,
                nose_slim: 0.0,
                face_slim: 0.0,
                chin_vshape: 0.0,
            },
            extras: SwipeLookExtras {
                glow: 0.20,
                grain: 0.0,
                sharpen: 0.0,
                skin_preserve_detail: 0.25,
                halation: 0.0,
                rgb_split: 0.0,
            },
        },
        SwipeLookPreset::CloudSkin => SwipeLookRecipe {
            mood: MoodRecipe {
                warmth: 0.0,
                fade: 0.08,
                vignette: 0.0,
                tone_curve: 0.35,
                saturation: 1.0,
                brightness: 0,
                highlights: 0.0,
                shadows: 0.0,
                hue_degrees: 0.0,
                structure: -12.0,
                highlight_rolloff: 0.30,
                shadow_tint: [0.0, 0.0, 0.0],
                highlight_tint: [0.0, 0.0, 0.0],
                midtone_tint: [0.0, 0.0, 0.0],
                skin_protection: 0.30,
                contrast: -0.04,
            },
            beauty: BeautyParams {
                skin_smooth: 0.25,
                eye_brighten: 0.0,
                lip_tint: LipTintPreset::None,
                lip_tint_strength: 0.0,
                lip_plump: 0.0,
                blush: 0.0,
                under_eye: 0.0,
                teeth_whiten: 0.0,
                skin_preserve_detail: 0.92,
                eye_enlarge: 0.0,
                jaw_slim: 0.0,
                nose_slim: 0.0,
                face_slim: 0.0,
                chin_vshape: 0.0,
            },
            extras: SwipeLookExtras {
                glow: 0.06,
                grain: 0.02,
                sharpen: 0.0,
                skin_preserve_detail: 0.92,
                halation: 0.0,
                rgb_split: 0.0,
            },
        },
        SwipeLookPreset::GoldenAura => SwipeLookRecipe {
            mood: MoodRecipe {
                warmth: 12.0,
                fade: 0.0,
                vignette: 0.08,
                tone_curve: 0.42,
                saturation: 1.08,
                brightness: 4,
                highlights: 0.0,
                shadows: 0.0,
                hue_degrees: 2.0,
                structure: 0.0,
                highlight_rolloff: 0.48,
                shadow_tint: [0.00, 0.01, 0.04],
                highlight_tint: [0.10, 0.07, 0.02],
                midtone_tint: [0.04, 0.02, 0.0],
                skin_protection: 0.25,
                contrast: 0.0,
            },
            beauty: BeautyParams {
                skin_smooth: 0.22,
                eye_brighten: 0.10,
                lip_tint: LipTintPreset::Coral,
                lip_tint_strength: 0.15,
                lip_plump: 0.0,
                blush: 0.10,
                under_eye: 0.0,
                teeth_whiten: 0.0,
                skin_preserve_detail: 0.10,
                eye_enlarge: 0.0,
                jaw_slim: 0.0,
                nose_slim: 0.0,
                face_slim: 0.0,
                chin_vshape: 0.0,
            },
            extras: SwipeLookExtras {
                glow: 0.24,
                grain: 0.03,
                sharpen: 0.0,
                skin_preserve_detail: 0.10,
                halation: 0.0,
                rgb_split: 0.0,
            },
        },
        SwipeLookPreset::SoftFocus => SwipeLookRecipe {
            mood: MoodRecipe {
                warmth: 2.0,
                fade: 0.04,
                vignette: 0.0,
                tone_curve: 0.24,
                saturation: 1.02,
                brightness: 4,
                highlights: 0.0,
                shadows: 0.0,
                hue_degrees: 0.0,
                structure: -8.0,
                highlight_rolloff: 0.36,
                shadow_tint: [0.0, 0.0, 0.01],
                highlight_tint: [0.02, 0.01, 0.0],
                midtone_tint: [0.01, 0.0, 0.0],
                skin_protection: 0.30,
                contrast: -0.03,
            },
            beauty: BeautyParams {
                skin_smooth: 0.44,
                eye_brighten: 0.12,
                lip_tint: LipTintPreset::Rose,
                lip_tint_strength: 0.10,
                lip_plump: 0.0,
                blush: 0.08,
                under_eye: 0.0,
                teeth_whiten: 0.0,
                skin_preserve_detail: 0.30,
                eye_enlarge: 0.0,
                jaw_slim: 0.0,
                nose_slim: 0.0,
                face_slim: 0.0,
                chin_vshape: 0.0,
            },
            extras: SwipeLookExtras {
                glow: 0.28,
                grain: 0.01,
                sharpen: 0.0,
                skin_preserve_detail: 0.30,
                halation: 0.0,
                rgb_split: 0.0,
            },
        },
        SwipeLookPreset::FauxFilm => SwipeLookRecipe {
            mood: MoodRecipe {
                warmth: 6.0,
                fade: 0.16,
                vignette: 0.10,
                tone_curve: 0.52,
                saturation: 0.88,
                brightness: -2,
                highlights: -8.0,
                shadows: 6.0,
                hue_degrees: -2.0,
                structure: 0.0,
                highlight_rolloff: 0.32,
                shadow_tint: [0.02, 0.01, 0.00],
                highlight_tint: [0.08, 0.05, 0.02],
                midtone_tint: [0.04, 0.03, 0.01],
                skin_protection: 0.15,
                contrast: 0.0,
            },
            beauty: BeautyParams::default(),
            extras: SwipeLookExtras {
                glow: 0.0,
                grain: 0.12,
                sharpen: 0.0,
                skin_preserve_detail: 0.0,
                halation: 0.08,
                rgb_split: 0.0,
            },
        },
        SwipeLookPreset::BoldGlamourLite => SwipeLookRecipe {
            mood: MoodRecipe {
                warmth: 4.0,
                fade: 0.02,
                vignette: 0.04,
                tone_curve: 0.38,
                saturation: 1.10,
                brightness: 4,
                highlights: 4.0,
                shadows: -4.0,
                hue_degrees: 1.0,
                structure: 6.0,
                highlight_rolloff: 0.35,
                shadow_tint: [0.01, 0.0, 0.03],
                highlight_tint: [0.06, 0.04, 0.01],
                midtone_tint: [0.03, 0.01, 0.01],
                skin_protection: 0.20,
                contrast: 0.0,
            },
            beauty: BeautyParams {
                skin_smooth: 0.48,
                eye_brighten: 0.10,
                lip_tint: LipTintPreset::Berry,
                lip_tint_strength: 0.25,
                lip_plump: 0.08,
                blush: 0.15,
                under_eye: 0.05,
                teeth_whiten: 0.06,
                skin_preserve_detail: 0.10,
                eye_enlarge: 0.05,
                jaw_slim: 0.02,
                nose_slim: 0.01,
                face_slim: 0.02,
                chin_vshape: 0.02,
            },
            extras: SwipeLookExtras {
                glow: 0.16,
                grain: 0.0,
                sharpen: 0.05,
                skin_preserve_detail: 0.10,
                halation: 0.0,
                rgb_split: 0.0,
            },
        },
        SwipeLookPreset::NeonNight => SwipeLookRecipe {
            mood: MoodRecipe {
                warmth: -6.0,
                fade: 0.0,
                vignette: 0.12,
                tone_curve: 0.65,
                saturation: 1.30,
                brightness: -4,
                highlights: 8.0,
                shadows: -12.0,
                hue_degrees: 180.0,
                structure: 12.0,
                highlight_rolloff: 0.30,
                shadow_tint: [0.00, 0.03, 0.08],
                highlight_tint: [0.08, 0.02, 0.10],
                midtone_tint: [0.03, 0.0, 0.05],
                skin_protection: 0.05,
                contrast: 0.12,
            },
            beauty: BeautyParams::default(),
            extras: SwipeLookExtras {
                glow: 0.30,
                grain: 0.04,
                sharpen: 0.0,
                skin_preserve_detail: 0.0,
                halation: 0.0,
                rgb_split: 0.02,
            },
        },
        SwipeLookPreset::AnimeAirbrush => SwipeLookRecipe {
            mood: MoodRecipe {
                warmth: -2.0,
                fade: 0.05,
                vignette: 0.0,
                tone_curve: 0.45,
                saturation: 1.05,
                brightness: 12,
                highlights: 10.0,
                shadows: 6.0,
                hue_degrees: -2.0,
                structure: -2.0,
                highlight_rolloff: 0.52,
                shadow_tint: [0.0, 0.02, 0.05],
                highlight_tint: [0.05, 0.02, 0.04],
                midtone_tint: [0.02, 0.01, 0.03],
                skin_protection: 0.15,
                contrast: 0.0,
            },
            beauty: BeautyParams {
                skin_smooth: 0.62,
                eye_brighten: 0.14,
                lip_tint: LipTintPreset::Rose,
                lip_tint_strength: 0.16,
                lip_plump: 0.05,
                blush: 0.10,
                under_eye: 0.08,
                teeth_whiten: 0.05,
                skin_preserve_detail: 0.75,
                eye_enlarge: 0.12,
                jaw_slim: 0.05,
                nose_slim: 0.05,
                face_slim: 0.05,
                chin_vshape: 0.05,
            },
            extras: SwipeLookExtras {
                glow: 0.22,
                grain: 0.0,
                sharpen: 0.0,
                skin_preserve_detail: 0.75,
                halation: 0.0,
                rgb_split: 0.0,
            },
        },
    }
}

#[allow(dead_code)]
pub fn display_name(preset: SwipeLookPreset) -> &'static str {
    match preset {
        SwipeLookPreset::CleanGirlGlow => "Clean Girl Glow",
        SwipeLookPreset::CloudSkin => "Cloud Skin",
        SwipeLookPreset::GoldenAura => "Golden Aura",
        SwipeLookPreset::SoftFocus => "Soft Focus",
        SwipeLookPreset::FauxFilm => "Faux Film",
        SwipeLookPreset::BoldGlamourLite => "Bold Glamour Lite",
        SwipeLookPreset::NeonNight => "Neon Night",
        SwipeLookPreset::AnimeAirbrush => "Anime Airbrush",
    }
}

pub fn apply_swipe_look_grade_rgba(
    buffer: RgbaImageBuffer,
    preset: SwipeLookPreset,
    strength: f32,
) -> RgbaImageBuffer {
    let recipe = recipe_for(preset);
    let mut out = apply_mood_recipe_with_strength(buffer, recipe.mood, strength);
    apply_swipe_look_extras_rgba(&mut out, preset, strength);
    out
}

/// Post-LUT extras (glow, grain, halation, rgb split) — also applied after GPU LUT batch.
pub fn apply_swipe_look_extras_rgba(
    buffer: &mut RgbaImageBuffer,
    preset: SwipeLookPreset,
    strength: f32,
) {
    let recipe = recipe_for(preset);
    let e = recipe.extras;
    let t = strength.clamp(0.0, 1.0);
    if e.glow > 0.001 {
        apply_glow_rgba(buffer, e.glow * t);
    }
    if preset == SwipeLookPreset::CleanGirlGlow && e.glow > 0.001 {
        apply_dewy_highlight_rgba(buffer, e.glow * t * 0.85);
    }
    if e.grain > 0.001 {
        apply_grain_rgba(buffer, e.grain * t);
    }
    if e.halation > 0.001 {
        apply_halation_rgba(buffer, e.halation * t);
    }
    if e.rgb_split > 0.001 {
        apply_rgb_split_rgba(buffer, e.rgb_split * t);
    }
    if e.sharpen > 0.001 {
        super::apply_structure_rgba(buffer, e.sharpen * 100.0 * t);
    }
}

fn apply_mood_recipe_with_strength(
    mut buffer: RgbaImageBuffer,
    recipe: MoodRecipe,
    strength: f32,
) -> RgbaImageBuffer {
    let t = strength.clamp(0.0, 1.0);
    if t < 0.001 {
        return buffer;
    }
    if t >= 0.999 {
        apply_mood_recipe_full(&mut buffer, recipe);
        return buffer;
    }
    let orig = buffer.pixels.clone();
    apply_mood_recipe_full(&mut buffer, recipe);
    blend_pixels(&mut buffer.pixels, &orig, t);
    buffer
}

fn apply_mood_recipe_full(buffer: &mut RgbaImageBuffer, recipe: MoodRecipe) {
    use super::mood_presets::apply_mood_color_rgba;
    use super::{apply_structure_rgba, apply_vignette_rgba};
    apply_mood_color_rgba(buffer, recipe);
    if recipe.structure.abs() > 0.001 {
        apply_structure_rgba(buffer, recipe.structure);
    }
    if recipe.vignette.abs() > 0.001 {
        apply_vignette_rgba(buffer, recipe.vignette);
    }
}

fn blend_pixels(out: &mut [u8], orig: &[u8], t: f32) {
    for (o, s) in out.iter_mut().zip(orig.iter()) {
        *o = (*o as f32 * t + *s as f32 * (1.0 - t))
            .round()
            .clamp(0.0, 255.0) as u8;
    }
}

#[cfg(test)]
use crate::api::image::RgbaImageBuffer as RgbaBuf;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn all_swipe_looks_have_names() {
        use SwipeLookPreset::*;
        for preset in [
            CleanGirlGlow,
            CloudSkin,
            GoldenAura,
            SoftFocus,
            FauxFilm,
            BoldGlamourLite,
            NeonNight,
            AnimeAirbrush,
        ] {
            assert!(!display_name(preset).is_empty());
            let r = recipe_for(preset);
            assert!(r.mood.tone_curve >= 0.0);
        }
    }

    #[test]
    fn clean_girl_glow_changes_pixels() {
        use SwipeLookPreset::*;
        let mut buf = RgbaBuf {
            width: 64,
            height: 64,
            pixels: (0..64 * 64).flat_map(|_| [180u8, 140, 120, 255]).collect(),
        };
        let before = buf.pixels.clone();
        buf = apply_swipe_look_grade_rgba(buf, CleanGirlGlow, 1.0);
        let changed = before
            .iter()
            .zip(buf.pixels.iter())
            .filter(|(a, b)| a != b)
            .count();
        assert!(
            changed > before.len() / 20,
            "expected visible grade change, only {changed} bytes differ"
        );
    }
}
