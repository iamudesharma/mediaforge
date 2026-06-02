import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_surface/pixel_surface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('channel name is stable', () {
    expect(GpuTextureRegistry.channelName, 'pixel_surface/texture');
  });

  test('isSupported matches platform (not web)', () {
    // On macOS/iOS/Android CI hosts this may be true; on Linux CI false.
    expect(GpuTextureRegistry.isSupported, isA<bool>());
  });

  group('PixelSurfaceStats.fromMap', () {
    test('parses Apple-shape keys', () {
      final stats = PixelSurfaceStats.fromMap({
        'handleCount': 4,
        'poolCount': 3,
        'createCount': 120,
        'lastFlushMs': 1700000000000.5,
        'lastMemoryWarningMs': 1699999990000.0,
        'trimEventCount': 0,
        'recycledBitmapCount': 0,
        'lastTrimLevel': -1,
      });
      expect(stats.handleCount, 4);
      expect(stats.poolCount, 3);
      expect(stats.createCount, 120);
      expect(stats.lastFlushMs, closeTo(1700000000000.5, 0.001));
      expect(stats.lastMemoryWarningMs, closeTo(1699999990000.0, 0.001));
      expect(stats.lastTrimLevel, -1);
    });

    test('parses Android-shape keys', () {
      final stats = PixelSurfaceStats.fromMap({
        'handleCount': 2,
        'poolCount': 0,
        'createCount': 0,
        'lastFlushMs': 0,
        'lastMemoryWarningMs': 0,
        'trimEventCount': 5,
        'recycledBitmapCount': 12,
        'lastTrimLevel': 80, // TRIM_MEMORY_COMPLETE
      });
      expect(stats.handleCount, 2);
      expect(stats.trimEventCount, 5);
      expect(stats.recycledBitmapCount, 12);
      expect(stats.lastTrimLevel, 80);
    });

    test('handles missing keys via defaults', () {
      final stats = PixelSurfaceStats.fromMap(<Object?, Object?>{});
      expect(stats.handleCount, 0);
      expect(stats.lastTrimLevel, -1);
      expect(stats.lastFlushMs, 0);
    });
  });
}
