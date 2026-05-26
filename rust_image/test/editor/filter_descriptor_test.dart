import 'package:flutter_test/flutter_test.dart';
import 'package:rust_image/rust_image.dart';

void _expectRoundTrip(FilterDescriptor original) {
  final filter = original.toImageFilter();
  final restored = FilterDescriptor.fromImageFilter(filter);

  expect(restored.kind, original.kind);
  expect(restored.params, original.params);
}

void main() {
  group('FilterDescriptor round-trips', () {
    test('preset', () {
      _expectRoundTrip(FilterDescriptor.preset(FilterPreset.cali, strength: 0.75));
    });

    test('mood', () {
      _expectRoundTrip(FilterDescriptor.mood(MoodFilterPreset.rose, strength: 1.0));
      _expectRoundTrip(FilterDescriptor.mood(MoodFilterPreset.clarendon, strength: 0.5));
    });

    test('warmth fade vignette', () {
      _expectRoundTrip(FilterDescriptor.warmth(amount: 25));
      _expectRoundTrip(FilterDescriptor.fade(amount: 0.4));
      _expectRoundTrip(FilterDescriptor.vignette(amount: 0.6));
    });

    test('highlights shadows structure', () {
      _expectRoundTrip(FilterDescriptor.highlights(amount: 30));
      _expectRoundTrip(FilterDescriptor.shadows(amount: -20));
      _expectRoundTrip(FilterDescriptor.structure(amount: 15));
    });

    test('highlights shadows structure', () {
      _expectRoundTrip(FilterDescriptor.highlights(amount: 30));
      _expectRoundTrip(FilterDescriptor.shadows(amount: -20));
      _expectRoundTrip(FilterDescriptor.structure(amount: 45));
    });

    test('blur', () {
      _expectRoundTrip(FilterDescriptor.blur(radius: 8));
    });

    test('sharpen', () {
      _expectRoundTrip(FilterDescriptor.sharpen());
    });

    test('brightness', () {
      _expectRoundTrip(FilterDescriptor.brightness(amount: 15));
    });

    test('contrast', () {
      _expectRoundTrip(FilterDescriptor.contrast(amount: 1.25));
    });

    test('saturation', () {
      _expectRoundTrip(FilterDescriptor.saturation(amount: 0.5));
    });

    test('hueRotate', () {
      _expectRoundTrip(FilterDescriptor.hueRotate(degrees: 90));
    });

    test('oil', () {
      _expectRoundTrip(FilterDescriptor.oil(radius: 3, intensity: 0.7));
    });

    test('frostedGlass', () {
      _expectRoundTrip(FilterDescriptor.frostedGlass());
    });

    test('pixelize', () {
      _expectRoundTrip(FilterDescriptor.pixelize(size: 12));
    });

    test('solarize', () {
      _expectRoundTrip(FilterDescriptor.solarize());
    });
  });

  group('FilterDescriptor.toImageFilter', () {
    test('throws ArgumentError for an unknown kind', () {
      const bogus = FilterDescriptor('garbage', <String, num>{});
      expect(bogus.toImageFilter, throwsArgumentError);
    });
  });
}
