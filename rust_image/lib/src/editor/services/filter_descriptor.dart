import 'package:rust_image/src/rust_image_editor.dart';

/// Serializable filter spec for isolate messages.
class FilterDescriptor {
  const FilterDescriptor(this.kind, this.params);

  final String kind;
  final Map<String, num> params;

  factory FilterDescriptor.preset(FilterPreset p) =>
      FilterDescriptor('preset', {'preset': p.index});

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

  factory FilterDescriptor.oil({required int radius, required double intensity}) =>
      FilterDescriptor('oil', {'radius': radius, 'intensity': intensity});

  factory FilterDescriptor.frostedGlass() =>
      const FilterDescriptor('frostedGlass', {});

  factory FilterDescriptor.pixelize({required int size}) =>
      FilterDescriptor('pixelize', {'size': size});

  factory FilterDescriptor.solarize() => const FilterDescriptor('solarize', {});

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
      ImageFilter_Oil(:final radius, :final intensity) =>
        FilterDescriptor.oil(radius: radius, intensity: intensity),
      ImageFilter_FrostedGlass() => FilterDescriptor.frostedGlass(),
      ImageFilter_Pixelize(:final size) => FilterDescriptor.pixelize(size: size),
      ImageFilter_Solarize() => FilterDescriptor.solarize(),
      ImageFilter_Preset(:final field0) => FilterDescriptor.preset(field0),
    };
  }

  ImageFilter toImageFilter() {
    switch (kind) {
      case 'preset':
        return ImageFilter.preset(FilterPreset.values[params['preset']!.toInt()]);
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
      default:
        throw ArgumentError('Unknown filter kind: $kind');
    }
  }
}
