import 'package:flutter_test/flutter_test.dart';
import 'package:video_forge/video_forge.dart' as vf;
import 'package:video_forge_kit/src/compositor/video_text_overlay_style.dart';
import 'package:video_forge_kit/src/compositor/video_text_presets.dart';
import 'package:video_forge_kit/src/export/overlay_effects_export.dart';

void main() {
  test('glitch animation adds glitch effect', () {
    final effects = OverlayEffectsExport.forStyle(
      VideoTextOverlayStyle.defaults.copyWith(
        animation: VideoTextAnimation.glitch,
      ),
    );
    expect(
      effects.effects.any((e) => e.kind == vf.OverlayEffectKind.glitch),
      isTrue,
    );
  });

  test('neon preset adds glow effect', () {
    final effects = OverlayEffectsExport.forStyle(
      VideoTextOverlayStyle.defaults.copyWith(
        lookPreset: VideoTextLookPreset.neon,
        glowIntensity: 0.8,
      ),
    );
    expect(
      effects.effects.any((e) => e.kind == vf.OverlayEffectKind.glow),
      isTrue,
    );
  });

  test('threeD flag adds rgb split', () {
    final effects = OverlayEffectsExport.forStyle(
      VideoTextOverlayStyle.defaults.copyWith(useThreeD: true),
    );
    expect(
      effects.effects.any((e) => e.kind == vf.OverlayEffectKind.rgbSplit),
      isTrue,
    );
  });
}
