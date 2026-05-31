import 'package:flutter_test/flutter_test.dart';
import 'package:video_forge_kit/video_forge_kit.dart';

void main() {
  group('MediaRuntimeMetrics', () {
    test('percentileMs returns p95', () {
      final samples = List<int>.generate(20, (i) => (i + 1) * 10);
      expect(MediaRuntimeMetrics.percentileMs(samples, 0.95), 190);
    });

    test('snapshot status line includes path', () {
      final m = MediaRuntimeMetrics()
        ..recordScrubComplete(120)
        ..recordPreviewPath(PreviewDeliveryPath.textureRgba, textureId: 42)
        ..recordPlaybackFpsSample(28.5);
      final line = m.snapshot().toStatusLine();
      expect(line, contains('texture_rgba'));
      expect(line, contains('scrub_p95'));
    });
  });

  group('MediaRuntimePerfTargets', () {
    test('targets match ROADMAP matrix', () {
      expect(MediaRuntimePerfTargets.scrubP95Ms, 300);
      expect(MediaRuntimePerfTargets.playbackMinFps, 24);
      expect(MediaRuntimePerfTargets.openDisposeCycles, 10);
    });
  });
}
