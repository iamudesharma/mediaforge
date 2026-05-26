use crate::api::face::{BeautyLookPreset, BeautyParams, LipTintPreset};

/// Recipe for a beauty look (mirrors mood parametric style).
#[derive(Debug, Clone, Copy)]
pub struct BeautyRecipe {
    pub skin_smooth: f32,
    pub eye_brighten: f32,
    pub lip_tint: LipTintPreset,
    pub lip_tint_strength: f32,
    pub lip_plump: f32,
    pub blush: f32,
}

pub fn recipe_for(preset: BeautyLookPreset) -> BeautyRecipe {
    match preset {
        BeautyLookPreset::Natural => BeautyRecipe {
            skin_smooth: 0.35,
            eye_brighten: 0.10,
            lip_tint: LipTintPreset::Nude,
            lip_tint_strength: 0.20,
            lip_plump: 0.0,
            blush: 0.0,
        },
        BeautyLookPreset::Soft => BeautyRecipe {
            skin_smooth: 0.55,
            eye_brighten: 0.20,
            lip_tint: LipTintPreset::Rose,
            lip_tint_strength: 0.30,
            lip_plump: 0.15,
            blush: 0.15,
        },
        BeautyLookPreset::Glow => BeautyRecipe {
            skin_smooth: 0.45,
            eye_brighten: 0.35,
            lip_tint: LipTintPreset::Coral,
            lip_tint_strength: 0.25,
            lip_plump: 0.10,
            blush: 0.20,
        },
        BeautyLookPreset::Glam => BeautyRecipe {
            skin_smooth: 0.50,
            eye_brighten: 0.40,
            lip_tint: LipTintPreset::Berry,
            lip_tint_strength: 0.50,
            lip_plump: 0.25,
            blush: 0.10,
        },
        BeautyLookPreset::Clear => BeautyRecipe {
            skin_smooth: 0.70,
            eye_brighten: 0.15,
            lip_tint: LipTintPreset::None,
            lip_tint_strength: 0.0,
            lip_plump: 0.0,
            blush: 0.0,
        },
        BeautyLookPreset::Peach => BeautyRecipe {
            skin_smooth: 0.40,
            eye_brighten: 0.15,
            lip_tint: LipTintPreset::Coral,
            lip_tint_strength: 0.35,
            lip_plump: 0.10,
            blush: 0.25,
        },
        BeautyLookPreset::Bold => BeautyRecipe {
            skin_smooth: 0.45,
            eye_brighten: 0.30,
            lip_tint: LipTintPreset::Red,
            lip_tint_strength: 0.55,
            lip_plump: 0.20,
            blush: 0.05,
        },
    }
}

pub fn params_for_look(preset: BeautyLookPreset) -> BeautyParams {
    let r = recipe_for(preset);
    BeautyParams {
        skin_smooth: r.skin_smooth,
        eye_brighten: r.eye_brighten,
        lip_tint: r.lip_tint,
        lip_tint_strength: r.lip_tint_strength,
        lip_plump: r.lip_plump,
        blush: r.blush,
        under_eye: 0.0,
        teeth_whiten: if matches!(preset, BeautyLookPreset::Glam) {
            0.25
        } else {
            0.0
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn all_looks_produce_active_params_except_clear_has_skin() {
        for preset in [
            BeautyLookPreset::Natural,
            BeautyLookPreset::Soft,
            BeautyLookPreset::Glow,
            BeautyLookPreset::Glam,
            BeautyLookPreset::Clear,
            BeautyLookPreset::Peach,
            BeautyLookPreset::Bold,
        ] {
            let p = params_for_look(preset);
            assert!(p.is_active(), "{preset:?} should be active");
        }
    }
}
