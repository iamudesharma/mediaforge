import 'package:flutter_test/flutter_test.dart';
import 'package:image_forge_core/image_forge_core.dart';

void main() {
  group('BlendMode', () {
    test('all values accessible', () {
      expect(BlendMode.values, hasLength(5));
      expect(BlendMode.normal, isA<BlendMode>());
      expect(BlendMode.multiply, isA<BlendMode>());
      expect(BlendMode.screen, isA<BlendMode>());
      expect(BlendMode.overlay, isA<BlendMode>());
      expect(BlendMode.add, isA<BlendMode>());
    });
  });

  group('FilterPreset', () {
    test('has 14 presets', () {
      expect(FilterPreset.values, hasLength(14));
    });

    test('named presets accessible', () {
      expect(FilterPreset.neue, isA<FilterPreset>());
      expect(FilterPreset.lix, isA<FilterPreset>());
      expect(FilterPreset.ryo, isA<FilterPreset>());
      expect(FilterPreset.lofi, isA<FilterPreset>());
      expect(FilterPreset.golden, isA<FilterPreset>());
      expect(FilterPreset.obsidian, isA<FilterPreset>());
      expect(FilterPreset.dramatic, isA<FilterPreset>());
    });
  });

  group('MoodFilterPreset', () {
    test('has 16 presets', () {
      expect(MoodFilterPreset.values, hasLength(16));
    });

    test('instagram mood filters accessible', () {
      expect(MoodFilterPreset.rose, isA<MoodFilterPreset>());
      expect(MoodFilterPreset.clarendon, isA<MoodFilterPreset>());
      expect(MoodFilterPreset.juno, isA<MoodFilterPreset>());
      expect(MoodFilterPreset.lark, isA<MoodFilterPreset>());
      expect(MoodFilterPreset.reyes, isA<MoodFilterPreset>());
      expect(MoodFilterPreset.gingham, isA<MoodFilterPreset>());
      expect(MoodFilterPreset.loFi, isA<MoodFilterPreset>());
      expect(MoodFilterPreset.moon, isA<MoodFilterPreset>());
      expect(MoodFilterPreset.aden, isA<MoodFilterPreset>());
      expect(MoodFilterPreset.willow, isA<MoodFilterPreset>());
      expect(MoodFilterPreset.inkwell, isA<MoodFilterPreset>());
    });
  });

  group('OutputFormat', () {
    test('has 4 formats', () {
      expect(OutputFormat.values, hasLength(4));
    });

    test('all formats accessible', () {
      expect(OutputFormat.jpeg, isA<OutputFormat>());
      expect(OutputFormat.png, isA<OutputFormat>());
      expect(OutputFormat.webP, isA<OutputFormat>());
      expect(OutputFormat.avif, isA<OutputFormat>());
    });
  });

  group('PreviewQuality', () {
    test('has 2 values', () {
      expect(PreviewQuality.values, hasLength(2));
      expect(PreviewQuality.fast, isA<PreviewQuality>());
      expect(PreviewQuality.quality, isA<PreviewQuality>());
    });
  });

  group('ProcessingBackend', () {
    test('has 3 backends', () {
      expect(ProcessingBackend.values, hasLength(3));
      expect(ProcessingBackend.cpu, isA<ProcessingBackend>());
      expect(ProcessingBackend.gpu, isA<ProcessingBackend>());
      expect(ProcessingBackend.auto, isA<ProcessingBackend>());
    });
  });

  group('ResizeAlgorithm', () {
    test('has 6 algorithms', () {
      expect(ResizeAlgorithm.values, hasLength(6));
    });

    test('algorithms ordered from fast to quality', () {
      expect(ResizeAlgorithm.nearest, isA<ResizeAlgorithm>());
      expect(ResizeAlgorithm.box, isA<ResizeAlgorithm>());
      expect(ResizeAlgorithm.hamming, isA<ResizeAlgorithm>());
      expect(ResizeAlgorithm.catmullRom, isA<ResizeAlgorithm>());
      expect(ResizeAlgorithm.mitchell, isA<ResizeAlgorithm>());
      expect(ResizeAlgorithm.lanczos3, isA<ResizeAlgorithm>());
    });
  });

  group('Rotation', () {
    test('has 5 rotations', () {
      expect(Rotation.values, hasLength(5));
    });

    test('all rotation values accessible', () {
      expect(Rotation.rotate90, isA<Rotation>());
      expect(Rotation.rotate180, isA<Rotation>());
      expect(Rotation.rotate270, isA<Rotation>());
      expect(Rotation.flipHorizontal, isA<Rotation>());
      expect(Rotation.flipVertical, isA<Rotation>());
    });
  });

  group('SwipeLookPreset', () {
    test('has 8 presets', () {
      expect(SwipeLookPreset.values, hasLength(8));
    });

    test('combo look presets accessible', () {
      expect(SwipeLookPreset.cleanGirlGlow, isA<SwipeLookPreset>());
      expect(SwipeLookPreset.cloudSkin, isA<SwipeLookPreset>());
      expect(SwipeLookPreset.goldenAura, isA<SwipeLookPreset>());
      expect(SwipeLookPreset.softFocus, isA<SwipeLookPreset>());
      expect(SwipeLookPreset.fauxFilm, isA<SwipeLookPreset>());
      expect(SwipeLookPreset.boldGlamourLite, isA<SwipeLookPreset>());
      expect(SwipeLookPreset.neonNight, isA<SwipeLookPreset>());
      expect(SwipeLookPreset.animeAirbrush, isA<SwipeLookPreset>());
    });
  });

  group('BeautyLookPreset', () {
    test('has 7 presets', () {
      expect(BeautyLookPreset.values, hasLength(7));
    });

    test('all presets accessible', () {
      expect(BeautyLookPreset.natural, isA<BeautyLookPreset>());
      expect(BeautyLookPreset.soft, isA<BeautyLookPreset>());
      expect(BeautyLookPreset.glow, isA<BeautyLookPreset>());
      expect(BeautyLookPreset.glam, isA<BeautyLookPreset>());
      expect(BeautyLookPreset.clear, isA<BeautyLookPreset>());
      expect(BeautyLookPreset.peach, isA<BeautyLookPreset>());
      expect(BeautyLookPreset.bold, isA<BeautyLookPreset>());
    });
  });

  group('LipTintPreset', () {
    test('has 6 presets', () {
      expect(LipTintPreset.values, hasLength(6));
    });

    test('all tints accessible', () {
      expect(LipTintPreset.none, isA<LipTintPreset>());
      expect(LipTintPreset.nude, isA<LipTintPreset>());
      expect(LipTintPreset.rose, isA<LipTintPreset>());
      expect(LipTintPreset.berry, isA<LipTintPreset>());
      expect(LipTintPreset.coral, isA<LipTintPreset>());
      expect(LipTintPreset.red, isA<LipTintPreset>());
    });
  });
}
