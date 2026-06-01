import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_forge_core/image_forge_core.dart';

void main() {
  group('ImageFilter', () {
    group('blur', () {
      test('construction', () {
        final f = ImageFilter.blur(radius: 5);
        expect(f, isA<ImageFilter_Blur>());
        expect((f as ImageFilter_Blur).radius, 5);
      });

      test('equality', () {
        final a = ImageFilter.blur(radius: 3);
        final b = ImageFilter.blur(radius: 3);
        final c = ImageFilter.blur(radius: 5);
        expect(a, equals(b));
        expect(a, isNot(equals(c)));
      });
    });

    group('sharpen', () {
      test('construction', () {
        final f = ImageFilter.sharpen();
        expect(f, isA<ImageFilter_Sharpen>());
      });

      test('equality', () {
        final a = ImageFilter.sharpen();
        final b = ImageFilter.sharpen();
        expect(a, equals(b));
      });
    });

    group('brightness', () {
      test('construction', () {
        final f = ImageFilter.brightness(amount: 50);
        expect(f, isA<ImageFilter_Brightness>());
        expect((f as ImageFilter_Brightness).amount, 50);
      });

      test('equality', () {
        final a = ImageFilter.brightness(amount: 10);
        final b = ImageFilter.brightness(amount: 10);
        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });
    });

    group('contrast', () {
      test('construction', () {
        final f = ImageFilter.contrast(amount: 1.5);
        expect(f, isA<ImageFilter_Contrast>());
        expect((f as ImageFilter_Contrast).amount, 1.5);
      });
    });

    group('saturation', () {
      test('construction', () {
        final f = ImageFilter.saturation(amount: 2.0);
        expect(f, isA<ImageFilter_Saturation>());
        expect((f as ImageFilter_Saturation).amount, 2.0);
      });
    });

    group('hueRotate', () {
      test('construction', () {
        final f = ImageFilter.hueRotate(degrees: 90.0);
        expect(f, isA<ImageFilter_HueRotate>());
        expect((f as ImageFilter_HueRotate).degrees, 90.0);
      });
    });

    group('oil', () {
      test('construction', () {
        final f = ImageFilter.oil(radius: 4, intensity: 0.7);
        expect(f, isA<ImageFilter_Oil>());
        final o = f as ImageFilter_Oil;
        expect(o.radius, 4);
        expect(o.intensity, 0.7);
      });
    });

    group('frostedGlass', () {
      test('construction and equality', () {
        final a = ImageFilter.frostedGlass();
        final b = ImageFilter.frostedGlass();
        expect(a, equals(b));
        expect(a, isA<ImageFilter_FrostedGlass>());
      });
    });

    group('pixelize', () {
      test('construction', () {
        final f = ImageFilter.pixelize(size: 8);
        expect(f, isA<ImageFilter_Pixelize>());
        expect((f as ImageFilter_Pixelize).size, 8);
      });
    });

    group('solarize', () {
      test('construction and equality', () {
        final a = ImageFilter.solarize();
        final b = ImageFilter.solarize();
        expect(a, equals(b));
      });
    });

    group('preset', () {
      test('construction', () {
        final f = ImageFilter.preset(preset: FilterPreset.lofi, strength: 0.5);
        expect(f, isA<ImageFilter_Preset>());
        final p = f as ImageFilter_Preset;
        expect(p.preset, FilterPreset.lofi);
        expect(p.strength, 0.5);
      });
    });

    group('warmth', () {
      test('construction', () {
        final f = ImageFilter.warmth(amount: 25.0);
        expect(f, isA<ImageFilter_Warmth>());
        expect((f as ImageFilter_Warmth).amount, 25.0);
      });
    });

    group('fade', () {
      test('construction', () {
        final f = ImageFilter.fade(amount: 0.3);
        expect(f, isA<ImageFilter_Fade>());
        expect((f as ImageFilter_Fade).amount, 0.3);
      });
    });

    group('vignette', () {
      test('construction', () {
        final f = ImageFilter.vignette(amount: 0.8);
        expect(f, isA<ImageFilter_Vignette>());
        expect((f as ImageFilter_Vignette).amount, 0.8);
      });
    });

    group('highlights', () {
      test('construction', () {
        final f = ImageFilter.highlights(amount: -50.0);
        expect(f, isA<ImageFilter_Highlights>());
        expect((f as ImageFilter_Highlights).amount, -50.0);
      });
    });

    group('shadows', () {
      test('construction', () {
        final f = ImageFilter.shadows(amount: 30.0);
        expect(f, isA<ImageFilter_Shadows>());
        expect((f as ImageFilter_Shadows).amount, 30.0);
      });
    });

    group('structure', () {
      test('construction', () {
        final f = ImageFilter.structure(amount: 50.0);
        expect(f, isA<ImageFilter_Structure>());
        expect((f as ImageFilter_Structure).amount, 50.0);
      });
    });

    group('mood', () {
      test('construction', () {
        final f = ImageFilter.mood(preset: MoodFilterPreset.juno, strength: 0.7);
        expect(f, isA<ImageFilter_Mood>());
        final m = f as ImageFilter_Mood;
        expect(m.preset, MoodFilterPreset.juno);
        expect(m.strength, 0.7);
      });
    });

    group('swipeLook', () {
      test('construction', () {
        final f = ImageFilter.swipeLook(
          preset: SwipeLookPreset.softFocus,
          strength: 0.8,
        );
        expect(f, isA<ImageFilter_SwipeLook>());
        final s = f as ImageFilter_SwipeLook;
        expect(s.preset, SwipeLookPreset.softFocus);
        expect(s.strength, 0.8);
      });
    });

    group('lutPng', () {
      test('construction', () {
        final png = Uint8List.fromList([1, 2, 3]);
        final f = ImageFilter.lutPng(pngBytes: png, strength: 0.6);
        expect(f, isA<ImageFilter_LutPng>());
        final l = f as ImageFilter_LutPng;
        expect(l.pngBytes, png);
        expect(l.strength, 0.6);
      });
    });

    group('skinSmooth', () {
      test('construction', () {
        final f = ImageFilter.skinSmooth(strength: 0.5);
        expect(f, isA<ImageFilter_SkinSmooth>());
        expect((f as ImageFilter_SkinSmooth).strength, 0.5);
      });
    });

    group('beauty', () {
      test('construction', () {
        const params = BeautyParams(
          skinSmooth: 0.5, eyeBrighten: 0.3, lipTint: LipTintPreset.none,
          lipTintStrength: 0.0, lipPlump: 0.0, blush: 0.0,
          underEye: 0.0, teethWhiten: 0.0, skinPreserveDetail: 0.0,
          eyeEnlarge: 0.0, jawSlim: 0.0, noseSlim: 0.0,
          faceSlim: 0.0, chinVshape: 0.0,
        );
        final f = ImageFilter.beauty(params: params);
        expect(f, isA<ImageFilter_Beauty>());
        expect((f as ImageFilter_Beauty).params, params);
      });
    });

    group('cross-variant', () {
      test('different variants not equal', () {
        final a = ImageFilter.blur(radius: 5);
        final b = ImageFilter.sharpen();
        expect(a, isNot(equals(b)));
      });

      test('22 unique variants exist', () {
        expect(ImageFilter_Blur, isA<Type>());
        expect(ImageFilter_Sharpen, isA<Type>());
        expect(ImageFilter_Brightness, isA<Type>());
        expect(ImageFilter_Contrast, isA<Type>());
        expect(ImageFilter_Saturation, isA<Type>());
        expect(ImageFilter_HueRotate, isA<Type>());
        expect(ImageFilter_Oil, isA<Type>());
        expect(ImageFilter_FrostedGlass, isA<Type>());
        expect(ImageFilter_Pixelize, isA<Type>());
        expect(ImageFilter_Solarize, isA<Type>());
        expect(ImageFilter_Preset, isA<Type>());
        expect(ImageFilter_Warmth, isA<Type>());
        expect(ImageFilter_Fade, isA<Type>());
        expect(ImageFilter_Vignette, isA<Type>());
        expect(ImageFilter_Highlights, isA<Type>());
        expect(ImageFilter_Shadows, isA<Type>());
        expect(ImageFilter_Structure, isA<Type>());
        expect(ImageFilter_Mood, isA<Type>());
        expect(ImageFilter_SwipeLook, isA<Type>());
        expect(ImageFilter_LutPng, isA<Type>());
        expect(ImageFilter_SkinSmooth, isA<Type>());
        expect(ImageFilter_Beauty, isA<Type>());
      });
    });

    group('freezed pattern matching', () {
      test('when', () {
        final f = ImageFilter.blur(radius: 7);
        final result = f.when(
          blur: (radius) => 'blur-$radius',
          sharpen: () => 'sharpen',
          brightness: (amount) => 'brightness-$amount',
          contrast: (amount) => 'contrast-$amount',
          saturation: (amount) => 'saturation-$amount',
          hueRotate: (degrees) => 'hue-$degrees',
          oil: (radius, intensity) => 'oil-$radius-$intensity',
          frostedGlass: () => 'frostedGlass',
          pixelize: (size) => 'pixelize-$size',
          solarize: () => 'solarize',
          preset: (preset, strength) => 'preset-$preset-$strength',
          warmth: (amount) => 'warmth-$amount',
          fade: (amount) => 'fade-$amount',
          vignette: (amount) => 'vignette-$amount',
          highlights: (amount) => 'highlights-$amount',
          shadows: (amount) => 'shadows-$amount',
          structure: (amount) => 'structure-$amount',
          mood: (preset, strength) => 'mood-$preset-$strength',
          swipeLook: (preset, strength) => 'swipeLook-$preset-$strength',
          lutPng: (pngBytes, strength) => 'lutPng',
          skinSmooth: (strength) => 'skinSmooth-$strength',
          beauty: (params) => 'beauty',
        );
        expect(result, 'blur-7');
      });

      test('maybeWhen with orElse', () {
        final f = ImageFilter.solarize();
        final result = f.maybeWhen(
          blur: (radius) => 'blur-$radius',
          orElse: () => 'not-blur',
        );
        expect(result, 'not-blur');
      });

      test('maybeMap with orElse', () {
        final f = ImageFilter.sharpen();
        final result = f.maybeMap(
          sharpen: (_) => 'yes',
          orElse: () => 'no',
        );
        expect(result, 'yes');
      });
    });
  });
}
