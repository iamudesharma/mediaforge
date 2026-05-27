#[inline]
pub fn luminance_f32(chunk: &[u8]) -> f32 {
    (0.299 * chunk[0] as f32 + 0.587 * chunk[1] as f32 + 0.114 * chunk[2] as f32) / 255.0
}

/// Apply an ACES-inspired filmic S-curve.
/// strength: 0.0 = linear, 0.5 = natural film, 1.0 = cinema, 1.5 = dramatic
pub fn apply_filmic_tone_curve(pixels: &mut [u8], strength: f32) {
    if strength < 0.001 {
        return;
    }
    // Build a 256-entry lookup table from the curve
    let lut = build_tone_curve_lut(strength);
    for chunk in pixels.chunks_exact_mut(4) {
        // Apply per-channel through the curve, preserving hue
        let luma_before = luminance_f32(chunk);
        for c in 0..3 {
            chunk[c] = lut[chunk[c] as usize];
        }
        // Restore original saturation ratio to prevent hue shifts
        let luma_after = luminance_f32(chunk);
        if luma_after > 0.001 {
            let ratio = luma_before / luma_after;
            // Partial restore: keep some of the curve's saturation effect
            let restore = 0.3; // 30% saturation restore
            let factor = 1.0 + (ratio - 1.0) * restore;
            for c in 0..3 {
                chunk[c] = ((chunk[c] as f32) * factor).clamp(0.0, 255.0) as u8;
            }
        }
    }
}

fn build_tone_curve_lut(strength: f32) -> [u8; 256] {
    let mut lut = [0u8; 256];
    for i in 0..256 {
        let x = i as f32 / 255.0;
        let curved = filmic_curve(x, strength);
        lut[i] = (curved * 255.0).clamp(0.0, 255.0) as u8;
    }
    lut
}

/// ACES-inspired filmic curve with controllable strength
fn filmic_curve(x: f32, strength: f32) -> f32 {
    if strength < 0.001 {
        return x;
    }
    
    // Pegtop soft-light inspired S-curve with configurable toe/shoulder
    let toe = 0.04 + strength * 0.08;   // shadow lift
    let shoulder = 0.92 - strength * 0.12; // highlight compression
    
    // Cubic hermite S-curve between toe and shoulder
    let t = ((x - toe) / (shoulder - toe)).clamp(0.0, 1.0);
    let s = t * t * (3.0 - 2.0 * t); // smoothstep
    
    // Mix between linear and S-curve based on strength
    let linear = x;
    let curved = toe + s * (shoulder - toe);
    let mix_factor = strength.clamp(0.0, 1.0);
    linear * (1.0 - mix_factor) + curved * mix_factor
}

/// Filmic highlight compression — prevents hard clipping on bright areas
/// Makes skin highlights look expensive and smooth
pub fn apply_highlight_rolloff(pixels: &mut [u8], strength: f32) {
    if strength < 0.001 {
        return;
    }
    for chunk in pixels.chunks_exact_mut(4) {
        let luma = luminance_f32(chunk);
        if luma > 0.5 {
            let influence = ((luma - 0.5) / 0.5).clamp(0.0, 1.0);
            let factor = influence * strength;
            for c in 0..3 {
                let v = chunk[c] as f32 / 255.0;
                // Soft compress: shoulder curve that rolls off smoothly
                let compressed = 1.0 - (1.0 - v).powf(1.0 + factor * 1.5);
                chunk[c] = (compressed * 255.0).clamp(0.0, 255.0) as u8;
            }
        }
    }
}

/// Luma-aware split toning: different tints for shadows, midtones, highlights
/// This is the single most important feature for "Instagram look"
pub fn apply_split_toning(
    pixels: &mut [u8],
    shadow_tint: [f32; 3],    // RGB offset for dark areas (normalized 0..1)
    midtone_tint: [f32; 3],   // RGB offset for mid areas
    highlight_tint: [f32; 3], // RGB offset for bright areas
) {
    // Check if tints are zero
    let has_shadow = shadow_tint[0].abs() > 0.001 || shadow_tint[1].abs() > 0.001 || shadow_tint[2].abs() > 0.001;
    let has_midtone = midtone_tint[0].abs() > 0.001 || midtone_tint[1].abs() > 0.001 || midtone_tint[2].abs() > 0.001;
    let has_highlight = highlight_tint[0].abs() > 0.001 || highlight_tint[1].abs() > 0.001 || highlight_tint[2].abs() > 0.001;
    
    if !has_shadow && !has_midtone && !has_highlight {
        return;
    }

    for chunk in pixels.chunks_exact_mut(4) {
        let luma = luminance_f32(chunk);
        
        // Shadow zone: strong in darks, fades out in mids
        let shadow_weight = (1.0 - luma * 2.5).clamp(0.0, 1.0).powf(1.5);
        // Highlight zone: strong in brights, fades out in mids
        let highlight_weight = ((luma - 0.4) * 2.5).clamp(0.0, 1.0).powf(1.5);
        // Midtone zone: bell curve peaking at ~0.45
        let midtone_weight = (1.0 - ((luma - 0.45) / 0.35).powi(2)).clamp(0.0, 1.0);
        
        for c in 0..3 {
            let shift = shadow_tint[c] * shadow_weight * 40.0
                      + midtone_tint[c] * midtone_weight * 30.0
                      + highlight_tint[c] * highlight_weight * 35.0;
            chunk[c] = (chunk[c] as f32 + shift).clamp(0.0, 255.0) as u8;
        }
    }
}

/// Protect skin tones from extreme color shifts during grading.
/// Detects skin-range hues and reduces color transform intensity.
pub fn apply_skin_luma_protection(
    original: &[u8],  // pre-grade pixels
    graded: &mut [u8], // post-grade pixels to modify
    strength: f32,     // 0 = no protection, 1 = full protection
) {
    if strength < 0.001 {
        return;
    }
    for (orig, graded_chunk) in original.chunks_exact(4).zip(graded.chunks_exact_mut(4)) {
        // Detect skin hue range (peach/beige in HSV)
        let (h, s, _) = rgb_to_hsv_inline(orig[0], orig[1], orig[2]);
        let is_skin_hue = h >= 5.0 && h <= 50.0 && s >= 0.1 && s <= 0.75;
        
        if is_skin_hue {
            let skin_factor = strength * 0.4; // partial protection
            for c in 0..3 {
                // Blend back toward original to protect skin
                graded_chunk[c] = (graded_chunk[c] as f32 * (1.0 - skin_factor)
                                 + orig[c] as f32 * skin_factor)
                    .clamp(0.0, 255.0) as u8;
            }
        }
    }
}

#[inline]
pub fn rgb_to_hsv_inline(r: u8, g: u8, b: u8) -> (f32, f32, f32) {
    let r = r as f32 / 255.0;
    let g = g as f32 / 255.0;
    let b = b as f32 / 255.0;

    let max = r.max(g).max(b);
    let min = r.min(g).min(b);
    let delta = max - min;

    let h = if delta == 0.0 {
        0.0
    } else if max == r {
        let mut val = 60.0 * (((g - b) / delta) % 6.0);
        if val < 0.0 {
            val += 360.0;
        }
        val
    } else if max == g {
        60.0 * (((b - r) / delta) + 2.0)
    } else {
        60.0 * (((r - g) / delta) + 4.0)
    };

    let h = if h < 0.0 { h + 360.0 } else { h };
    let s = if max == 0.0 { 0.0 } else { delta / max };
    let v = max;

    (h, s, v)
}
