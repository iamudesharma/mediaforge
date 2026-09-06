import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_forge_player/media_forge_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MediaForgePlayerController (no engine)', () {
    test('starts uninitialized with stable handle', () {
      final c = MediaForgePlayerController(textureHandle: 0x4D465001);
      expect(c.value, MediaForgePlayerValue.uninitialized);
      expect(c.textureHandle, 0x4D465001);
      expect(c.presenter.textureHandle, 0x4D465001);
      c.dispose();
    });

    test('setVolume clamps and stores without engine', () async {
      final c = MediaForgePlayerController(textureHandle: 0x4D465002);
      await c.setVolume(2.0);
      expect(c.value.volume, 1.0);
      await c.setVolume(-1.0);
      expect(c.value.volume, 0.0);
      c.dispose();
    });

    test('setMuted stores flag without engine', () async {
      final c = MediaForgePlayerController(textureHandle: 0x4D465003);
      await c.setMuted(true);
      expect(c.value.isMuted, isTrue);
      c.dispose();
    });

    test('selectAudioTrack stores unknown id when undiscovered (v1)', () async {
      final c = MediaForgePlayerController(textureHandle: 0x4D465004);
      await c.selectAudioTrack(7);
      expect(c.value.selectedAudioTrackId, 7);
      c.dispose();
    });

    test('selectAudioTrack rejects unknown id once discovered', () async {
      final c = MediaForgePlayerController(textureHandle: 0x4D465005);
      c.value = c.value.copyWith(
        audioTracks: const [
          MediaForgeAudioTrack(id: 0, label: 'Default'),
        ],
      );
      expect(() => c.selectAudioTrack(9), throwsRangeError);
      c.dispose();
    });

    test('addExternalSubtitle appends sidecar track', () async {
      final c = MediaForgePlayerController(textureHandle: 0x4D465006);
      final id = await c.addExternalSubtitle(
        Uri.parse('http://127.0.0.1:8080/subs/en.vtt'),
        language: 'en',
      );
      expect(c.value.subtitleTracks.length, 1);
      final t = c.value.subtitleTracks.single;
      expect(t.id, id);
      expect(t.isEmbedded, isFalse);
      expect(t.language, 'en');
      c.dispose();
    });

    test('resolveTarget rejects missing file', () async {
      final c = MediaForgePlayerController(textureHandle: 0x4D465007);
      expect(
        () => c.resolveTargetForTest(
          const MediaForgeMedia.file('/definitely/not/here.mp4'),
        ),
        throwsArgumentError,
      );
      c.dispose();
    });

    test('resolveTarget rejects non-http scheme', () async {
      final c = MediaForgePlayerController(textureHandle: 0x4D465008);
      expect(
        () => c.resolveTargetForTest(
          const MediaForgeMedia.network('ftp://example.com/v.mp4'),
        ),
        throwsArgumentError,
      );
      c.dispose();
    });

    test('resolveTarget passes http URL through (engine reads it)', () async {
      final c = MediaForgePlayerController(textureHandle: 0x4D465009);
      final target = await c.resolveTargetForTest(
        const MediaForgeMedia.network('http://127.0.0.1:8080/stream'),
      );
      expect(target, 'http://127.0.0.1:8080/stream');
      c.dispose();
    });

    test('resolveTarget passes existing file through', () async {
      final tmp =
          await File('${Directory.systemTemp.path}/mfp_probe_test.mp4')
              .writeAsBytes([0, 1, 2, 3]);
      final c = MediaForgePlayerController(textureHandle: 0x4D46500A);
      try {
        final target = await c.resolveTargetForTest(
          MediaForgeMedia.file(tmp.path),
        );
        expect(target, tmp.path);
      } finally {
        c.dispose();
        await tmp.delete();
      }
    });
  });
}
