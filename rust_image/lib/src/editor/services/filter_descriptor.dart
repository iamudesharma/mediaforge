import 'package:rust_image/src/rust/api/face.dart';
import 'package:rust_image/src/rust_image_editor.dart';

/// Serializable filter spec for isolate messages.
class FilterDescriptor {
  const FilterDescriptor(this.kind, this.params);

  final String kind;
  final Map<String, num> params;

  factory FilterDescriptor.preset(
    FilterPreset p, {
    double strength = 1.0,
  }) =>
      FilterDescriptor('preset', {
        'preset': p.index,
        'strength': strength,
      });

  factory FilterDescriptor.mood(
    MoodFilterPreset p, {
    double strength = 1.0,
  }) =>
      FilterDescriptor('mood', {
        'preset': p.index,
        'strength': strength,
      });

  /// True for swipe mood filters (not Filters-tab presets).
  bool get isMood => kind == 'mood';

  factory FilterDescriptor.blur({required int radius}) =>
      FilterDescriptor('blur', {'radius': radius});

  factory FilterDescriptor.sharpen() => const FilterDescriptor('sharpen', {});

  factory FilterDescriptor.brightness({required int amount}) =>
      FilterDescriptor('brightness', {'amount': amount});

  factory FilterDescriptor.contrast({required double amount}) =>
      FilterDescriptor('contrast', {'amount': amount});

  factory FilterDescriptor.saturation({required double amount}) =>
      FilterDescriptor('saturation', {'amount': amount});

  factory FilterDescriptor.hueRotate({required double degrees}) =>
      FilterDescriptor('hueRotate', {'degrees': degrees});

  factory FilterDescriptor.warmth({required double amount}) =>
      FilterDescriptor('warmth', {'amount': amount});

  factory FilterDescriptor.fade({required double amount}) =>
      FilterDescriptor('fade', {'amount': amount});

  factory FilterDescriptor.vignette({required double amount}) =>
      FilterDescriptor('vignette', {'amount': amount});

  factory FilterDescriptor.highlights({required double amount}) =>
      FilterDescriptor('highlights', {'amount': amount});

  factory FilterDescriptor.shadows({required double amount}) =>
      FilterDescriptor('shadows', {'amount': amount});

  factory FilterDescriptor.structure({required double amount}) =>
      FilterDescriptor('structure', {'amount': amount});

  /// Regional skin smooth (0–1); mask applied outside the edit graph.
  factory FilterDescriptor.skinSmooth({required double strength}) =>
      FilterDescriptor('skinSmooth', {'strength': strength});

  /// Regional beauty (Nexus B); masks applied outside the edit graph.
  factory FilterDescriptor.beauty({required BeautyParams params}) =>
      FilterDescriptor('beauty', {
        'skinSmooth': params.skinSmooth,
        'eyeBrighten': params.eyeBrighten,
        'lipTint': params.lipTint.index,
        'lipTintStrength': params.lipTintStrength,
        'lipPlump': params.lipPlump,
        'blush': params.blush,
        'underEye': params.underEye,
      });

  factory FilterDescriptor.oil({required int radius, required double intensity}) =>
      FilterDescriptor('oil', {'radius': radius, 'intensity': intensity});

  factory FilterDescriptor.frostedGlass() =>
      const FilterDescriptor('frostedGlass', {});

  factory FilterDescriptor.pixelize({required int size}) =>
      FilterDescriptor('pixelize', {'size': size});

  factory FilterDescriptor.solarize() => const FilterDescriptor('solarize', {});

  double get presetStrength =>
      (params['strength'] ?? 1.0).toDouble().clamp(0.0, 1.0);

  factory FilterDescriptor.fromImageFilter(ImageFilter filter) {
    return switch (filter) {
      ImageFilter_Blur(:final radius) => FilterDescriptor.blur(radius: radius),
      ImageFilter_Sharpen() => FilterDescriptor.sharpen(),
      ImageFilter_Brightness(:final amount) =>
        FilterDescriptor.brightness(amount: amount),
      ImageFilter_Contrast(:final amount) =>
        FilterDescriptor.contrast(amount: amount),
      ImageFilter_Saturation(:final amount) =>
        FilterDescriptor.saturation(amount: amount),
      ImageFilter_HueRotate(:final degrees) =>
        FilterDescriptor.hueRotate(degrees: degrees),
      ImageFilter_Warmth(:final amount) =>
        FilterDescriptor.warmth(amount: amount),
      ImageFilter_Fade(:final amount) => FilterDescriptor.fade(amount: amount),
      ImageFilter_Vignette(:final amount) =>
        FilterDescriptor.vignette(amount: amount),
      ImageFilter_Highlights(:final amount) =>
        FilterDescriptor.highlights(amount: amount),
      ImageFilter_Shadows(:final amount) =>
        FilterDescriptor.shadows(amount: amount),
      ImageFilter_Structure(:final amount) =>
        FilterDescriptor.structure(amount: amount),
      ImageFilter_Oil(:final radius, :final intensity) =>
        FilterDescriptor.oil(radius: radius, intensity: intensity),
      ImageFilter_FrostedGlass() => FilterDescriptor.frostedGlass(),
      ImageFilter_Pixelize(:final size) => FilterDescriptor.pixelize(size: size),
      ImageFilter_Solarize() => FilterDescriptor.solarize(),
      ImageFilter_Preset(:final preset, :final strength) =>
        FilterDescriptor.preset(preset, strength: strength),
      ImageFilter_Mood(:final preset, :final strength) =>
        FilterDescriptor.mood(preset, strength: strength),
      ImageFilter_SkinSmooth(:final strength) =>
        FilterDescriptor.skinSmooth(strength: strength),
      ImageFilter_Beauty(:final params) =>
        FilterDescriptor.beauty(params: params),
    };
  }

  ImageFilter toImageFilter() {
    switch (kind) {
      case 'preset':
        return ImageFilter.preset(
          preset: FilterPreset.values[params['preset']!.toInt()],
          strength: presetStrength,
        );
      case 'mood':
        return ImageFilter.mood(
          preset: MoodFilterPreset.values[params['preset']!.toInt()],
          strength: presetStrength,
        );
      case 'blur':
        return ImageFilter.blur(radius: params['radius']!.toInt());
      case 'sharpen':
        return const ImageFilter.sharpen();
      case 'brightness':
        return ImageFilter.brightness(amount: params['amount']!.toInt());
      case 'contrast':
        return ImageFilter.contrast(amount: params['amount']!.toDouble());
      case 'saturation':
        return ImageFilter.saturation(amount: params['amount']!.toDouble());
      case 'hueRotate':
        return ImageFilter.hueRotate(degrees: params['degrees']!.toDouble());
      case 'warmth':
        return ImageFilter.warmth(amount: params['amount']!.toDouble());
      case 'fade':
        return ImageFilter.fade(amount: params['amount']!.toDouble());
      case 'vignette':
        return ImageFilter.vignette(amount: params['amount']!.toDouble());
      case 'highlights':
        return ImageFilter.highlights(amount: params['amount']!.toDouble());
      case 'shadows':
        return ImageFilter.shadows(amount: params['amount']!.toDouble());
      case 'structure':
        return ImageFilter.structure(amount: params['amount']!.toDouble());
      case 'oil':
        return ImageFilter.oil(
          radius: params['radius']!.toInt(),
          intensity: params['intensity']!.toDouble(),
        );
      case 'frostedGlass':
        return const ImageFilter.frostedGlass();
      case 'pixelize':
        return ImageFilter.pixelize(size: params['size']!.toInt());
      case 'solarize':
        return const ImageFilter.solarize();
      case 'skinSmooth':
        return ImageFilter.skinSmooth(
          strength: (params['strength'] ?? 0).toDouble().clamp(0.0, 1.0),
        );
      case 'beauty':
        return ImageFilter.beauty(
          params: BeautyParams(
            skinSmooth: (params['skinSmooth'] ?? 0).toDouble(),
            eyeBrighten: (params['eyeBrighten'] ?? 0).toDouble(),
            lipTint: LipTintPreset.values[(params['lipTint'] ?? 0).toInt()],
            lipTintStrength: (params['lipTintStrength'] ?? 0).toDouble(),
            lipPlump: (params['lipPlump'] ?? 0).toDouble(),
            blush: (params['blush'] ?? 0).toDouble(),
            underEye: (params['underEye'] ?? 0).toDouble(),
          ),
        );
      default:
        throw ArgumentError('Unknown filter kind: $kind');
    }
  }
}
