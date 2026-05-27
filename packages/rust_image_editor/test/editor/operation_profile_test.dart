import 'package:flutter_test/flutter_test.dart';
import 'package:rust_image_editor/rust_image_editor.dart';

void main() {
  group('OperationProfile.statusSuffix', () {
    test('returns an empty string when both totalMs and filterMs are <= 0',
        () {
      const profile = OperationProfile(
        totalMs: 0,
        filterMs: 0,
        previewEncodeMs: 0,
        executionPath: '',
      );
      expect(profile.statusSuffix(), '');
    });

    test('includes executionPath and filterMs when both are present', () {
      const profile = OperationProfile(
        totalMs: 0,
        filterMs: 7,
        previewEncodeMs: 0,
        executionPath: 'path',
      );

      expect(profile.statusSuffix(), ' \u00b7 path \u00b7 filter 7ms');
    });

    test('joins executionPath, filterMs, and previewEncodeMs with \u00b7', () {
      const profile = OperationProfile(
        totalMs: 25,
        filterMs: 7,
        previewEncodeMs: 3,
        executionPath: 'gpu_adjust',
      );

      expect(
        profile.statusSuffix(),
        ' \u00b7 gpu_adjust \u00b7 filter 7ms \u00b7 preview 3ms',
      );
    });

    test('omits executionPath when empty but keeps the other parts', () {
      const profile = OperationProfile(
        totalMs: 12,
        filterMs: 4,
        previewEncodeMs: 2,
        executionPath: '',
      );

      expect(profile.statusSuffix(), ' \u00b7 filter 4ms \u00b7 preview 2ms');
    });

    test('renders only executionPath when filterMs/previewEncodeMs are zero',
        () {
      const profile = OperationProfile(
        totalMs: 9,
        filterMs: 0,
        previewEncodeMs: 0,
        executionPath: 'cpu_photon',
      );

      expect(profile.statusSuffix(), ' \u00b7 cpu_photon');
    });
  });
}
