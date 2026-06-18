import 'package:video_forge/video_forge.dart' as vf;
import 'package:video_forge_kit/src/compositor/video_text_overlay_style.dart';
import 'package:video_forge_kit/src/compositor/video_text_presets.dart';

/// Maps preview styles to v3 [vf.OverlayEffects] for export burn-in.
class OverlayEffectsExport {
  OverlayEffectsExport._();

  static vf.OverlayEffects forStyle(VideoTextOverlayStyle style) {
    final effects = <vf.OverlayEffect>[];

    if (style.animation == VideoTextAnimation.glitch) {
      final dur = _ms(520, style.animationDurationScale);
      effects.add(
        vf.OverlayEffect(
          kind: vf.OverlayEffectKind.glitch,
          intensity: 0.85,
          startMs: BigInt.zero,
          durationMs: BigInt.from(dur),
        ),
      );
    }

    if (style.lookPreset == VideoTextLookPreset.neon && style.glowIntensity > 0.2) {
      effects.add(
        vf.OverlayEffect(
          kind: vf.OverlayEffectKind.glow,
          intensity: style.glowIntensity.clamp(0.0, 1.0),
          startMs: BigInt.zero,
          durationMs: BigInt.zero,
        ),
      );
    }

    if (style.useThreeD) {
      effects.add(
        vf.OverlayEffect(
          kind: vf.OverlayEffectKind.rgbSplit,
          intensity: 0.35,
          startMs: BigInt.zero,
          durationMs: BigInt.zero,
        ),
      );
    }

    return vf.OverlayEffects(effects: effects);
  }

  static int _ms(int base, double scale) =>
      (base / scale.clamp(0.35, 2.5)).round().clamp(80, 4000);
}
