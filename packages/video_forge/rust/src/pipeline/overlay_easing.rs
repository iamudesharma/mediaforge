//! Easing curves for overlay transform tracks (matches Flutter Curves where noted).

use crate::types::Easing;

/// Map linear progress `t` in [0, 1] through the easing curve.
pub fn apply_easing(easing: Easing, t: f32) -> f32 {
    let t = t.clamp(0.0, 1.0);
    match easing {
        Easing::Linear => t,
        Easing::EaseIn => t * t * t,
        Easing::EaseOut => {
            let u = 1.0 - t;
            1.0 - u * u * u
        }
        Easing::EaseInOut => {
            if t < 0.5 {
                4.0 * t * t * t
            } else {
                let u = -2.0 * t + 2.0;
                1.0 - u * u * u / 2.0
            }
        }
        Easing::Overshoot => {
            const C1: f32 = 1.70158;
            const C3: f32 = C1 + 1.0;
            let u = t - 1.0;
            1.0 + C3 * u * u * u + C1 * u * u
        }
        Easing::Bounce => ease_out_bounce(t),
    }
}

/// CSS / Material-style ease-out bounce.
fn ease_out_bounce(t: f32) -> f32 {
    const N1: f32 = 7.5625;
    const D1: f32 = 2.75;

    if t < 1.0 / D1 {
        N1 * t * t
    } else if t < 2.0 / D1 {
        let t = t - 1.5 / D1;
        N1 * t * t + 0.75
    } else if t < 2.5 / D1 {
        let t = t - 2.25 / D1;
        N1 * t * t + 0.9375
    } else {
        let t = t - 2.625 / D1;
        N1 * t * t + 0.984375
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn linear_endpoints() {
        assert!((apply_easing(Easing::Linear, 0.0) - 0.0).abs() < 1e-6);
        assert!((apply_easing(Easing::Linear, 1.0) - 1.0).abs() < 1e-6);
    }

    #[test]
    fn ease_out_ends_at_one() {
        assert!((apply_easing(Easing::EaseOut, 1.0) - 1.0).abs() < 1e-4);
    }

    #[test]
    fn bounce_ends_at_one() {
        assert!((apply_easing(Easing::Bounce, 1.0) - 1.0).abs() < 1e-4);
    }
}
