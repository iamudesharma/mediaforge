import 'package:flutter_test/flutter_test.dart';
import 'package:video_forge_editor/src/editor/video_editor_session.dart';
import 'package:video_forge_editor/src/services/video_export_service.dart';
import 'package:video_forge_editor/src/services/video_input.dart';
import 'package:video_forge_kit/video_forge_kit.dart';

void main() {
  group('VideoEditorSession', () {
    test('exportTrimMs intersects filmstrip with timeline range', () {
      final session = VideoEditorSession();
      session.timeline.loadPrimaryVideo(
        sourcePath: '/tmp/test.mp4',
        durationMs: 10000,
      );
      session.startSec = 1;
      session.endSec = 8;
      session.timeline.updateVideoClip(
        session.timeline.videoClips.first.copyWith(
          sourceStartMs: 2000,
          sourceEndMs: 7000,
        ),
      );

      final (startMs, endMs) = session.exportTrimMs();
      expect(startMs, 2000);
      expect(endMs, 7000);
      session.dispose();
    });

    test('exportAudioTracks skips muted clips', () {
      final session = VideoEditorSession();
      session.timeline.loadPrimaryVideo(
        sourcePath: '/tmp/test.mp4',
        durationMs: 5000,
      );
      final muted = session.timeline.addAudioClip(
        sourcePath: '/tmp/bgm.m4a',
        sourceDurationMs: 5000,
        volume: 0.8,
      );
      session.timeline.updateAudioClip(muted.copyWith(muted: true));
      session.timeline.addAudioClip(
        sourcePath: '/tmp/bgm2.m4a',
        sourceDurationMs: 3000,
        volume: 1.0,
      );

      expect(session.exportAudioTracks(), hasLength(1));
      expect(session.exportAudioTracks().first.sourcePath, '/tmp/bgm2.m4a');
      session.dispose();
    });
  });

  group('VideoExportService', () {
    test('shortExportError trims backtrace noise', () {
      const raw = 'AnyhowException(encode failed)\nStack backtrace:\n  line 1';
      expect(
        VideoExportService.shortExportError(raw),
        'encode failed',
      );
    });
  });

  group('VideoInput', () {
    test('normalizes Google http URLs to https', () {
      expect(
        VideoInput.normalizeUrl('http://storage.googleapis.com/foo.mp4'),
        'https://storage.googleapis.com/foo.mp4',
      );
    });
  });
}
