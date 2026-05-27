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
    pub tone_curve: f32,
    pub saturation: f32,
    pub brightness: i16,
    pub highlights: f32,
    pub shadows: f32,
    pub hue_degrees: f32,
    pub structure: f32,
    
    // Cinematic extensions
    pub highlight_rolloff: f32,
    pub shadow_tint: [f32; 3],
    pub highlight_tint: [f32; 3],
    pub midtone_tint: [f32; 3],
    pub skin_protection: f32,
    pub contrast: f32,
}

pub fn recipe_for(preset: MoodFilterPreset) -> MoodRecipe {
    match preset {
        MoodFilterPreset::Rose => MoodRecipe {
            warmth: 10.0,
            fade: 0.08,
            vignette: 0.08,
            tone_curve: 0.55,
            saturation: 1.06,
            brightness: 4,
            highlights: -6.0,
            shadows: 10.0,
            hue_degrees: 3.0,
            structure: 0.0,
            highlight_rolloff: 0.35,
            shadow_tint: [0.06, 0.0, 0.08],
            highlight_tint: [0.10, 0.06, 0.02],
            midtone_tint: [0.04, 0.01, 0.0],
            skin_protection: 0.15,
            contrast: 0.0,
        },
        MoodFilterPreset::Clarendon => MoodRecipe {
            warmth: -5.0,
            fade: 0.0,
            vignette: 0.18,
            tone_curve: 0.75,
            saturation: 1.12,
            brightness: 4,
            highlights: 8.0,
            shadows: -12.0,
            hue_degrees: -4.0,
            structure: 18.0,
            highlight_rolloff: 0.4,
            shadow_tint: [0.0, 0.04, 0.10],
            highlight_tint: [0.08, 0.08, 0.02],
            midtone_tint: [0.0, 0.02, 0.04],
            skin_protection: 0.05,
            contrast: 0.0,
        },
        MoodFilterPreset::Juno => MoodRecipe {
            warmth: 15.0,
            fade: 0.06,
            vignette: 0.1,
            tone_curve: 0.65,
            saturation: 1.18,
            brightness: 6,
            highlights: 4.0,
            shadows: 6.0,
            hue_degrees: 6.0,
            structure: 8.0,
            highlight_rolloff: 0.3,
            shadow_tint: [0.02, 0.0, 0.08],
            highlight_tint: [0.12, 0.06, 0.0],
            midtone_tint: [0.05, 0.02, 0.0],
            skin_protection: 0.2,
            contrast: 0.0,
        },
        MoodFilterPreset::Valencia => MoodRecipe {
            warmth: 12.0,
            fade: 0.2,
            vignette: 0.05,
            tone_curve: 0.35,
            saturation: 0.95,
            brightness: 8,
            highlights: -4.0,
            shadows: 15.0,
            hue_degrees: 4.0,
            structure: 0.0,
            highlight_rolloff: 0.5,
            shadow_tint: [0.08, 0.06, 0.02],
            highlight_tint: [0.10, 0.08, 0.04],
            midtone_tint: [0.06, 0.04, 0.01],
            skin_protection: 0.25,
            contrast: 0.0,
        },
        MoodFilterPreset::Lark => MoodRecipe {
            warmth: 2.0,
            fade: 0.08,
            vignette: 0.0,
            tone_curve: 0.45,
            saturation: 0.85,
            brightness: 15,
            highlights: 10.0,
            shadows: 8.0,
            hue_degrees: 0.0,
            structure: 5.0,
            highlight_rolloff: 0.25,
            shadow_tint: [0.0, 0.06, 0.05],
            highlight_tint: [0.04, 0.04, 0.02],
            midtone_tint: [0.0, 0.02, 0.02],
            skin_protection: 0.1,
            contrast: 0.0,
        },
        MoodFilterPreset::Reyes => MoodRecipe {
            warmth: 10.0,
            fade: 0.3,
            vignette: 0.12,
            tone_curve: 0.25,
            saturation: 0.8,
            brightness: 6,
            highlights: -8.0,
            shadows: 16.0,
            hue_degrees: 4.0,
            structure: -8.0,
            highlight_rolloff: 0.6,
            shadow_tint: [0.07, 0.06, 0.04],
            highlight_tint: [0.06, 0.05, 0.03],
            midtone_tint: [0.04, 0.03, 0.02],
            skin_protection: 0.3,
            contrast: 0.0,
        },
        MoodFilterPreset::Gingham => MoodRecipe {
            warmth: 2.0,
            fade: 0.15,
            vignette: 0.0,
            tone_curve: 0.35,
            saturation: 0.9,
            brightness: 12,
            highlights: 6.0,
            shadows: 4.0,
            hue_degrees: -2.0,
            structure: 0.0,
            highlight_rolloff: 0.4,
            shadow_tint: [0.02, 0.04, 0.02],
            highlight_tint: [0.05, 0.05, 0.04],
            midtone_tint: [0.03, 0.03, 0.02],
            skin_protection: 0.15,
            contrast: 0.0,
        },
        MoodFilterPreset::LoFi => MoodRecipe {
            warmth: 5.0,
            fade: 0.08,
            vignette: 0.25,
            tone_curve: 0.85,
            saturation: 0.85,
            brightness: -4,
            highlights: -14.0,
            shadows: -10.0,
            hue_degrees: 0.0,
            structure: 22.0,
            highlight_rolloff: 0.3,
            shadow_tint: [0.02, 0.01, 0.05],
            highlight_tint: [0.08, 0.06, 0.02],
            midtone_tint: [0.04, 0.02, 0.0],
            skin_protection: 0.1,
            contrast: 0.0,
        },
        MoodFilterPreset::Moon => MoodRecipe {
            warmth: -10.0,
            fade: 0.1,
            vignette: 0.08,
            tone_curve: 0.55,
            saturation: 0.0,
            brightness: 18,
            highlights: 12.0,
            shadows: 6.0,
            hue_degrees: -6.0,
            structure: 0.0,
            highlight_rolloff: 0.35,
            shadow_tint: [0.0, 0.0, 0.0],
            highlight_tint: [0.0, 0.0, 0.0],
            midtone_tint: [0.0, 0.0, 0.0],
            skin_protection: 0.0,
            contrast: 0.0,
        },
        MoodFilterPreset::Aden => MoodRecipe {
            warmth: 10.0,
            fade: 0.25,
            vignette: 0.06,
            tone_curve: 0.3,
            saturation: 0.88,
            brightness: 8,
            highlights: 4.0,
            shadows: 10.0,
            hue_degrees: 2.0,
            structure: 0.0,
            highlight_rolloff: 0.5,
            shadow_tint: [0.05, 0.02, 0.04],
            highlight_tint: [0.06, 0.04, 0.03],
            midtone_tint: [0.04, 0.02, 0.02],
            skin_protection: 0.25,
            contrast: 0.0,
        },
        MoodFilterPreset::Perpetua => MoodRecipe {
            warmth: 10.0,
            fade: 0.12,
            vignette: 0.1,
            tone_curve: 0.45,
            saturation: 0.95,
            brightness: 6,
            highlights: 0.0,
            shadows: 8.0,
            hue_degrees: 8.0,
            structure: 5.0,
            highlight_rolloff: 0.3,
            shadow_tint: [0.01, 0.05, 0.02],
            highlight_tint: [0.06, 0.04, 0.02],
            midtone_tint: [0.03, 0.03, 0.01],
            skin_protection: 0.1,
            contrast: 0.0,
        },
        MoodFilterPreset::Mayfair => MoodRecipe {
            warmth: 6.0,
            fade: 0.08,
            vignette: 0.22,
            tone_curve: 0.5,
            saturation: 1.05,
            brightness: 4,
            highlights: -4.0,
            shadows: 6.0,
            hue_degrees: 10.0,
            structure: 10.0,
            highlight_rolloff: 0.35,
            shadow_tint: [0.04, 0.0, 0.02],
            highlight_tint: [0.08, 0.05, 0.04],
            midtone_tint: [0.04, 0.02, 0.02],
            skin_protection: 0.2,
            contrast: 0.0,
        },
        MoodFilterPreset::Hudson => MoodRecipe {
            warmth: -8.0,
            fade: 0.1,
            vignette: 0.2,
            tone_curve: 0.65,
            saturation: 1.1,
            brightness: -2,
            highlights: 6.0,
            shadows: -6.0,
            hue_degrees: -10.0,
            structure: 15.0,
            highlight_rolloff: 0.35,
            shadow_tint: [0.0, 0.03, 0.08],
            highlight_tint: [0.02, 0.02, 0.04],
            midtone_tint: [0.0, 0.01, 0.03],
            skin_protection: 0.05,
            contrast: 0.0,
        },
        MoodFilterPreset::Sierra => MoodRecipe {
            warmth: 12.0,
            fade: 0.28,
            vignette: 0.15,
            tone_curve: 0.3,
            saturation: 0.85,
            brightness: 4,
            highlights: -6.0,
            shadows: 12.0,
            hue_degrees: 3.0,
            structure: -5.0,
            highlight_rolloff: 0.55,
            shadow_tint: [0.06, 0.04, 0.02],
            highlight_tint: [0.08, 0.06, 0.04],
            midtone_tint: [0.05, 0.04, 0.02],
            skin_protection: 0.28,
            contrast: 0.0,
        },
        MoodFilterPreset::Willow => MoodRecipe {
            warmth: 5.0,
            fade: 0.05,
            vignette: 0.08,
            tone_curve: 0.4,
            saturation: 0.0,
            brightness: 6,
            highlights: 4.0,
            shadows: 6.0,
            hue_degrees: 0.0,
            structure: 0.0,
            highlight_rolloff: 0.4,
            shadow_tint: [0.04, 0.03, 0.02],
            highlight_tint: [0.05, 0.04, 0.03],
            midtone_tint: [0.03, 0.02, 0.01],
            skin_protection: 0.1,
            contrast: 0.0,
        },
        MoodFilterPreset::Inkwell => MoodRecipe {
            warmth: 0.0,
            fade: 0.0,
            vignette: 0.12,
            tone_curve: 0.9,
            saturation: 0.0,
            brightness: -6,
            highlights: -10.0,
            shadows: -8.0,
            hue_degrees: 0.0,
            structure: 12.0,
            highlight_rolloff: 0.3,
            shadow_tint: [0.0, 0.0, 0.0],
            highlight_tint: [0.0, 0.0, 0.0],
            midtone_tint: [0.0, 0.0, 0.0],
            skin_protection: 0.0,
            contrast: 0.0,
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
    let original = if recipe.skin_protection > 0.001 {
        Some(buffer.pixels.clone())
    } else {
        None
    };

    if recipe.tone_curve.abs() > 0.001 {
        super::filmic::apply_filmic_tone_curve(&mut buffer.pixels, recipe.tone_curve);
    }
    if recipe.contrast.abs() > 0.001 {
        crate::parallel_ops::par_contrast(&mut buffer.pixels, recipe.contrast * 100.0);
    }
    if recipe.brightness != 0 {
        crate::parallel_ops::par_brightness(&mut buffer.pixels, recipe.brightness);
    }
    if (recipe.saturation - 1.0).abs() > 0.001 {
        crate::parallel_ops::par_saturation(&mut buffer.pixels, recipe.saturation);
    }
    if recipe.hue_degrees.abs() > 0.001 {
        crate::parallel_ops::par_hue_rotate(&mut buffer.pixels, recipe.hue_degrees);
    }
    
    super::filmic::apply_split_toning(
        &mut buffer.pixels,
        recipe.shadow_tint,
        recipe.midtone_tint,
        recipe.highlight_tint,
    );
    
    if recipe.warmth.abs() > 0.001 {
        apply_warmth_rgba(&mut buffer.pixels, recipe.warmth);
    }
    if recipe.highlight_rolloff.abs() > 0.001 {
        super::filmic::apply_highlight_rolloff(&mut buffer.pixels, recipe.highlight_rolloff);
    }
    if recipe.highlights.abs() > 0.001 {
        apply_highlights_rgba(&mut buffer.pixels, recipe.highlights);
    }
    if recipe.shadows.abs() > 0.001 {
        apply_shadows_rgba(&mut buffer.pixels, recipe.shadows);
    }
    if recipe.fade.abs() > 0.001 {
        apply_fade_rgba(&mut buffer.pixels, recipe.fade);
    }

    if let Some(orig) = original {
        super::filmic::apply_skin_luma_protection(&orig, &mut buffer.pixels, recipe.skin_protection);
    }
}
