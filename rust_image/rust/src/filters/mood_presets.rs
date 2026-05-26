use crate::api::image::{MoodFilterPreset, RgbaImageBuffer};

use super::{
    apply_fade_rgba, apply_highlights_rgba, apply_shadows_rgba, apply_structure_rgba,
    apply_vignette_rgba, apply_warmth_rgba,
};

/// Parametric Instagram-style mood grade (global — whole image).
#[derive(Debug, Clone, Copy)]
pub struct MoodRecipe {
    pub warmth: f32,
    pub fade: f32,
    pub vignette: f32,
    pub contrast: f32,
    pub saturation: f32,
    pub brightness: i16,
    pub highlights: f32,
    pub shadows: f32,
    pub hue_degrees: f32,
    pub structure: f32,
}

pub fn recipe_for(preset: MoodFilterPreset) -> MoodRecipe {
    match preset {
        MoodFilterPreset::Rose => MoodRecipe {
            warmth: 35.0,
            fade: 0.12,
            vignette: 0.08,
            contrast: 1.05,
            saturation: 1.08,
            brightness: 6,
            highlights: -8.0,
            shadows: 12.0,
            hue_degrees: 4.0,
            structure: 0.0,
        },
        MoodFilterPreset::Clarendon => MoodRecipe {
            warmth: -12.0,
            fade: 0.0,
            vignette: 0.18,
            contrast: 1.22,
            saturation: 1.15,
            brightness: 4,
            highlights: 10.0,
            shadows: -15.0,
            hue_degrees: -6.0,
            structure: 18.0,
        },
        MoodFilterPreset::Juno => MoodRecipe {
            warmth: 42.0,
            fade: 0.06,
            vignette: 0.1,
            contrast: 1.1,
            saturation: 1.25,
            brightness: 8,
            highlights: 5.0,
            shadows: 8.0,
            hue_degrees: 8.0,
            structure: 8.0,
        },
        MoodFilterPreset::Valencia => MoodRecipe {
            warmth: 38.0,
            fade: 0.22,
            vignette: 0.05,
            contrast: 0.95,
            saturation: 0.92,
            brightness: 10,
            highlights: -5.0,
            shadows: 18.0,
            hue_degrees: 6.0,
            structure: 0.0,
        },
        MoodFilterPreset::Lark => MoodRecipe {
            warmth: 8.0,
            fade: 0.08,
            vignette: 0.0,
            contrast: 1.05,
            saturation: 0.82,
            brightness: 18,
            highlights: 12.0,
            shadows: 10.0,
            hue_degrees: 0.0,
            structure: 5.0,
        },
        MoodFilterPreset::Reyes => MoodRecipe {
            warmth: 28.0,
            fade: 0.35,
            vignette: 0.12,
            contrast: 0.88,
            saturation: 0.78,
            brightness: 6,
            highlights: -10.0,
            shadows: 20.0,
            hue_degrees: 5.0,
            structure: -8.0,
        },
        MoodFilterPreset::Gingham => MoodRecipe {
            warmth: 5.0,
            fade: 0.18,
            vignette: 0.0,
            contrast: 0.92,
            saturation: 0.88,
            brightness: 14,
            highlights: 8.0,
            shadows: 5.0,
            hue_degrees: -3.0,
            structure: 0.0,
        },
        MoodFilterPreset::LoFi => MoodRecipe {
            warmth: 15.0,
            fade: 0.08,
            vignette: 0.25,
            contrast: 1.28,
            saturation: 0.72,
            brightness: -4,
            highlights: -18.0,
            shadows: -12.0,
            hue_degrees: 0.0,
            structure: 22.0,
        },
        MoodFilterPreset::Moon => MoodRecipe {
            warmth: -25.0,
            fade: 0.1,
            vignette: 0.08,
            contrast: 1.08,
            saturation: 0.55,
            brightness: 22,
            highlights: 15.0,
            shadows: 8.0,
            hue_degrees: -8.0,
            structure: 0.0,
        },
        MoodFilterPreset::Aden => MoodRecipe {
            warmth: 22.0,
            fade: 0.28,
            vignette: 0.06,
            contrast: 0.9,
            saturation: 0.85,
            brightness: 8,
            highlights: 5.0,
            shadows: 12.0,
            hue_degrees: 3.0,
            structure: 0.0,
        },
        MoodFilterPreset::Perpetua => MoodRecipe {
            warmth: 30.0,
            fade: 0.15,
            vignette: 0.1,
            contrast: 1.0,
            saturation: 0.95,
            brightness: 6,
            highlights: 0.0,
            shadows: 10.0,
            hue_degrees: 10.0,
            structure: 5.0,
        },
        MoodFilterPreset::Mayfair => MoodRecipe {
            warmth: 18.0,
            fade: 0.1,
            vignette: 0.22,
            contrast: 1.08,
            saturation: 1.05,
            brightness: 4,
            highlights: -5.0,
            shadows: 8.0,
            hue_degrees: 12.0,
            structure: 10.0,
        },
        MoodFilterPreset::Hudson => MoodRecipe {
            warmth: -18.0,
            fade: 0.12,
            vignette: 0.2,
            contrast: 1.15,
            saturation: 1.1,
            brightness: -2,
            highlights: 8.0,
            shadows: -8.0,
            hue_degrees: -12.0,
            structure: 15.0,
        },
        MoodFilterPreset::Sierra => MoodRecipe {
            warmth: 32.0,
            fade: 0.32,
            vignette: 0.15,
            contrast: 0.9,
            saturation: 0.8,
            brightness: 4,
            highlights: -8.0,
            shadows: 15.0,
            hue_degrees: 4.0,
            structure: -5.0,
        },
        MoodFilterPreset::Willow => MoodRecipe {
            warmth: 12.0,
            fade: 0.05,
            vignette: 0.08,
            contrast: 0.95,
            saturation: 0.0,
            brightness: 6,
            highlights: 5.0,
            shadows: 8.0,
            hue_degrees: 0.0,
            structure: 0.0,
        },
        MoodFilterPreset::Inkwell => MoodRecipe {
            warmth: 0.0,
            fade: 0.0,
            vignette: 0.12,
            contrast: 1.35,
            saturation: 0.0,
            brightness: -6,
            highlights: -12.0,
            shadows: -10.0,
            hue_degrees: 0.0,
            structure: 12.0,
        },
    }
}

pub fn apply_mood_filter_rgba(
    mut buffer: RgbaImageBuffer,
    preset: MoodFilterPreset,
    strength: f32,
) -> RgbaImageBuffer {
    let t = strength.clamp(0.0, 1.0);
    if t < 0.001 {
        return buffer;
    }
    if t >= 0.999 {
        apply_mood_recipe_rgba(&mut buffer, recipe_for(preset));
        return buffer;
    }
    let before = buffer.pixels.clone();
    apply_mood_recipe_rgba(&mut buffer, recipe_for(preset));
    for (b, a) in before.iter().zip(buffer.pixels.iter_mut()) {
        *a = (*b as f32 * (1.0 - t) + *a as f32 * t).round() as u8;
    }
    buffer
}

fn apply_mood_recipe_rgba(buffer: &mut RgbaImageBuffer, recipe: MoodRecipe) {
    apply_mood_color_rgba(buffer, recipe);
    if recipe.structure.abs() > 0.001 {
        apply_structure_rgba(buffer, recipe.structure);
    }
    if recipe.vignette.abs() > 0.001 {
        apply_vignette_rgba(buffer, recipe.vignette);
    }
}

/// Color-only mood grade (no spatial structure / vignette) — used for 3D LUT baking.
pub fn apply_mood_color_rgba(buffer: &mut RgbaImageBuffer, recipe: MoodRecipe) {
    if recipe.brightness != 0 {
        crate::parallel_ops::par_brightness(&mut buffer.pixels, recipe.brightness);
    }
    if (recipe.contrast - 1.0).abs() > 0.001 {
        crate::parallel_ops::par_contrast(&mut buffer.pixels, recipe.contrast);
    }
    if (recipe.saturation - 1.0).abs() > 0.001 {
        crate::parallel_ops::par_saturation(&mut buffer.pixels, recipe.saturation);
    }
    if recipe.hue_degrees.abs() > 0.001 {
        crate::parallel_ops::par_hue_rotate(&mut buffer.pixels, recipe.hue_degrees);
    }
    apply_warmth_rgba(&mut buffer.pixels, recipe.warmth);
    apply_highlights_rgba(&mut buffer.pixels, recipe.highlights);
    apply_shadows_rgba(&mut buffer.pixels, recipe.shadows);
    apply_fade_rgba(&mut buffer.pixels, recipe.fade);
}
