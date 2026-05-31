import 'package:flutter_test/flutter_test.dart';
import 'package:video_forge_kit/src/runtime/playback_clock.dart';

void main() {
  group('PlaybackClock', () {
    test('advanceToFramePts sets media time from decode', () {
      final clock = PlaybackClock()..mediaTimeMs = 1000;
      clock.advanceToFramePts(1523);
      expect(clock.lastPresentedPtsMs, 1523);
      expect(clock.mediaTimeMs, 1000);
    });

    test('pause only from playing', () {
      final clock = PlaybackClock()
        ..state = PlaybackState.playing
        ..mediaTimeMs = 500;
      clock.pause();
      expect(clock.state, PlaybackState.paused);
      expect(clock.isPaused, isTrue);
    });

    test('reset clears state', () {
      final clock = PlaybackClock()
        ..state = PlaybackState.playing
        ..mediaTimeMs = 999
        ..rate = 2.0;
      clock.reset(mediaTimeMs: 0);
      expect(clock.state, PlaybackState.idle);
      expect(clock.mediaTimeMs, 0);
      expect(clock.rate, 1.0);
    });
  });
}
