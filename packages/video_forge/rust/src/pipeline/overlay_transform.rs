//! Evaluate [TransformTracks] at a local timeline offset (ms from overlay start).

use crate::types::{AnimationTrack, Easing, TransformProperty, TransformTracks};

/// Resolved transform at `local_ms` (milliseconds since overlay start).
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct ResolvedTransform {
    pub translate_x: f32,
    pub translate_y: f32,
    pub scale: f32,
    pub rotation: f32,
    pub opacity: f32,
}

impl Default for ResolvedTransform {
    fn default() -> Self {
        Self {
            translate_x: 0.0,
            translate_y: 0.0,
            scale: 1.0,
            rotation: 0.0,
            opacity: 1.0,
        }
    }
}

impl ResolvedTransform {
    pub fn evaluate(tracks: &TransformTracks, local_ms: u64) -> Self {
        let mut out = Self::default();
        for track in &tracks.tracks {
            if local_ms < track.start_ms {
                continue;
            }
            let value = evaluate_track(track, local_ms);
            match track.property {
                TransformProperty::TranslateX => out.translate_x = value,
                TransformProperty::TranslateY => out.translate_y = value,
                TransformProperty::Scale => out.scale = value,
                TransformProperty::Rotation => out.rotation = value,
                TransformProperty::Opacity => out.opacity = value,
            }
        }
        out.opacity = out.opacity.clamp(0.0, 1.0);
        if out.scale < 0.001 {
            out.scale = 0.001;
        }
        out
    }
}

fn evaluate_track(track: &AnimationTrack, local_ms: u64) -> f32 {
    if track.duration_ms == 0 {
        return track.to;
    }
    let end = track.start_ms.saturating_add(track.duration_ms);
    if local_ms >= end {
        return track.to;
    }
    let elapsed = (local_ms - track.start_ms) as f32;
    let t = elapsed / track.duration_ms as f32;
    let eased = crate::pipeline::overlay_easing::apply_easing(track.easing, t);
    track.from + (track.to - track.from) * eased
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::types::{AnimationTrack, TransformProperty, TransformTracks};

    #[test]
    fn opacity_fade_in() {
        let tracks = TransformTracks {
            tracks: vec![AnimationTrack {
                property: TransformProperty::Opacity,
                from: 0.0,
                to: 1.0,
                start_ms: 0,
                duration_ms: 200,
                easing: Easing::Linear,
            }],
        };
        let at_100 = ResolvedTransform::evaluate(&tracks, 100);
        assert!((at_100.opacity - 0.5).abs() < 0.06);
        let at_200 = ResolvedTransform::evaluate(&tracks, 200);
        assert!((at_200.opacity - 1.0).abs() < 0.02);
    }

    #[test]
    fn scale_bounce_track() {
        let tracks = TransformTracks {
            tracks: vec![AnimationTrack {
                property: TransformProperty::Scale,
                from: 0.0,
                to: 1.0,
                start_ms: 0,
                duration_ms: 450,
                easing: Easing::Bounce,
            }],
        };
        let at_end = ResolvedTransform::evaluate(&tracks, 450);
        assert!((at_end.scale - 1.0).abs() < 0.05);
    }
}
