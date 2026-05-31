import 'package:flutter_test/flutter_test.dart';
import 'package:video_forge_kit/src/playback/native_playback_trim.dart';

void main() {
  group('clampPositionToTrim', () {
    test('clamps inside range', () {
      expect(clampPositionToTrim(500, 100, 900), 500);
      expect(clampPositionToTrim(50, 100, 900), 100);
      expect(clampPositionToTrim(1000, 100, 900), 900);
    });
  });

  group('clampSeekMs', () {
    test('respects trim and duration', () {
      expect(
        clampSeekMs(
          requestedMs: 50,
          startMs: 100,
          endMs: 900,
          durationMs: 1000,
        ),
        100,
      );
      expect(
        clampSeekMs(
          requestedMs: 950,
          startMs: 100,
          endMs: 900,
          durationMs: 1000,
        ),
        900,
      );
    });
  });

  group('shouldPauseAtTrimEnd', () {
    test('pauses near end when not looping', () {
      expect(
        shouldPauseAtTrimEnd(
          positionMs: 850,
          endMs: 900,
          isPlaying: true,
          loopPlayback: false,
        ),
        isTrue,
      );
      expect(
        shouldPauseAtTrimEnd(
          positionMs: 850,
          endMs: 900,
          isPlaying: true,
          loopPlayback: true,
        ),
        isFalse,
      );
    });
  });

  group('timelineSecFromSourcePts', () {
    test('maps source PTS into timeline seconds', () {
      const clips = [
        TimelineClipMapping(
          sourcePath: '/a.mov',
          sourceStartMs: 0,
          sourceEndMs: 5000,
          timelineStartMs: 0,
        ),
        TimelineClipMapping(
          sourcePath: '/a.mov',
          sourceStartMs: 5000,
          sourceEndMs: 10000,
          timelineStartMs: 5000,
        ),
      ];
      expect(
        timelineSecFromSourcePts(
          sourcePtsMs: 2500,
          sourcePath: '/a.mov',
          clips: clips,
        ),
        2.5,
      );
      expect(
        timelineSecFromSourcePts(
          sourcePtsMs: 7000,
          sourcePath: '/a.mov',
          clips: clips,
        ),
        7.0,
      );
    });
  });
}
