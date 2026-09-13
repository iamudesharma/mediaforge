import 'package:flutter_test/flutter_test.dart';
import 'package:media_forge/media_forge.dart' show PlaybackState;
import 'package:media_forge_player/media_forge_player.dart';

void main() {
  group('MediaForgePlayerValue', () {
    test('uninitialized defaults', () {
      const v = MediaForgePlayerValue.uninitialized;
      expect(v.isInitialized, isFalse);
      expect(v.isPlaying, isFalse);
      expect(v.duration, Duration.zero);
      expect(v.hasError, isFalse);
      expect(v.hasVideo, isFalse);
      expect(v.aspectRatio, 16 / 9);
    });

    test('aspectRatio honours rotation', () {
      const v = MediaForgePlayerValue(
        videoWidth: 1920,
        videoHeight: 1080,
        rotationDegrees: 90,
      );
      expect(v.aspectRatio, closeTo(1080 / 1920, 1e-9));
    });

    test('copyWith + equality', () {
      const a = MediaForgePlayerValue.uninitialized;
      final b = a.copyWith(isInitialized: true, volume: 0.5);
      expect(b.isInitialized, isTrue);
      expect(b.volume, 0.5);
      expect(a == b, isFalse);
      expect(b.copyWith(), equals(b));
    });

    test('error flag + clearError', () {
      const a = MediaForgePlayerValue(errorDescription: 'boom');
      expect(a.hasError, isTrue);
      expect(a.copyWith(clearError: true).hasError, isFalse);
    });
  });

  group('MediaForgeDiagnostics', () {
    test('decoderQueueDepth sums queues', () {
      const d = MediaForgeDiagnostics(
        state: PlaybackState.playing,
        mediaTimeMs: 0,
        audioClockMs: 0,
        wallClockMs: 0,
        latestDecodedPtsMs: 0,
        presentedPtsMs: 0,
        avDriftMs: 0,
        videoPacketsInQueue: 3,
        audioPacketsInQueue: 2,
        videoFramesInQueue: 4,
        audioFramesInQueue: 1,
      );
      expect(d.decoderQueueDepth, 10);
    });
  });
}
