import 'package:flutter_test/flutter_test.dart';
import 'package:media_forge_player/media_forge_player.dart';

import 'fake_engine.dart';

/// Engine-backed stress tests using [FakeMediaPlaybackEngine] (no natives).
///
/// Real-decode coverage (1080p H.264 / 4K HEVC, long-playback memory) needs
/// a device build; see `docs/BENCHMARKS.md` for the manual procedure.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  var nextHandle = 0x5EED0000;
  MediaForgePlayerController makeController(FakeMediaPlaybackEngine fake) {
    final handle = nextHandle++;
    return MediaForgePlayerController(
      textureHandle: handle,
      engineFactory: ({
        required int textureHandle,
        required BigInt maxQueueSize,
        required int previewMaxEdge,
      }) async =>
          fake,
    );
  }

  group('network open (PeerStream acceptance)', () {
    test('URL + headers reach openUrl untouched', () async {
      final fake = FakeMediaPlaybackEngine();
      final c = makeController(fake);
      addTearDown(c.dispose);
      await c.open(
        const MediaForgeMedia.network(
          'http://127.0.0.1:8080/stream',
          headers: {'Authorization': 'Bearer peerstream'},
          userAgent: 'PeerStream/1.0',
          reconnect: true,
        ),
      );
      expect(fake.openedUrls, ['http://127.0.0.1:8080/stream']);
      expect(
        fake.lastOptions?.headers['Authorization'],
        'Bearer peerstream',
      );
      expect(fake.lastOptions?.userAgent, 'PeerStream/1.0');
      expect(fake.lastOptions?.reconnect, isTrue);
      expect(c.value.isInitialized, isTrue);
      expect(c.value.duration, const Duration(milliseconds: 120000));
    });

    test('open populates audio + subtitle tracks', () async {
      final fake = FakeMediaPlaybackEngine();
      final c = makeController(fake);
      addTearDown(c.dispose);
      await c.open(
        const MediaForgeMedia.network('http://127.0.0.1:8080/stream'),
      );
      expect(c.value.audioTracks.length, 2);
      expect(
        c.value.audioTracks.map((t) => t.language),
        ['en', 'es'],
      );
      expect(c.value.audioTracks.first.codec, 'aac');
      expect(c.value.audioTracks.first.isDefault, isTrue);
      expect(c.value.subtitleTracks.length, 2);
      expect(c.value.subtitleTracks.first.codec, 'mov_text');
    });
  });

  group('seek patterns', () {
    test('repeated seeks land in order (incl. 20-min PeerStream jump)',
        () async {
      final fake = FakeMediaPlaybackEngine();
      final c = makeController(fake);
      addTearDown(c.dispose);
      await c.open(
        const MediaForgeMedia.network('http://127.0.0.1:8080/stream'),
      );
      const targets = [
        0,
        5000,
        1200000, // 20 min — clamped to duration
        30000,
        119999,
        0,
        60000,
      ];
      for (final ms in targets) {
        await c.seek(Duration(milliseconds: ms));
      }
      expect(fake.seekLog.length, targets.length);
      expect(
        fake.seekLog,
        [0, 5000, 120000, 30000, 119999, 0, 60000],
      );
      expect(c.value.position, const Duration(milliseconds: 60000));
    });
  });

  group('track switching', () {
    test('audio switch calls engine + updates value', () async {
      final fake = FakeMediaPlaybackEngine();
      final c = makeController(fake);
      addTearDown(c.dispose);
      await c.open(
        const MediaForgeMedia.network('http://127.0.0.1:8080/stream'),
      );
      await c.selectAudioTrack(2);
      expect(fake.audioSelectLog, [2]);
      expect(c.value.selectedAudioTrackId, 2);
      expect(() => c.selectAudioTrack(99), throwsRangeError);
    });

    test('subtitle switch on/off + poll text', () async {
      final fake = FakeMediaPlaybackEngine();
      final c = makeController(fake);
      addTearDown(c.dispose);
      await c.open(
        const MediaForgeMedia.network('http://127.0.0.1:8080/stream'),
      );
      // Nothing selected → no cues.
      expect(
        await c.subtitleTextAt(const Duration(seconds: 6)),
        isNull,
      );
      await c.selectSubtitleTrack(3);
      expect(fake.subtitleSelectLog, [3]);
      expect(
        await c.subtitleTextAt(const Duration(seconds: 6)),
        'Hello',
      );
      expect(
        await c.subtitleTextAt(const Duration(seconds: 12)),
        'World',
      );
      expect(
        await c.subtitleTextAt(const Duration(seconds: 20)),
        isNull,
      );
      await c.selectSubtitleTrack(null);
      expect(fake.subtitleSelectLog, [3, -1]);
      expect(
        await c.subtitleTextAt(const Duration(seconds: 6)),
        isNull,
      );
      expect(() => c.selectSubtitleTrack(99), throwsRangeError);
    });

    test('subtitle delay shifts cues', () async {
      final fake = FakeMediaPlaybackEngine();
      final c = makeController(fake);
      addTearDown(c.dispose);
      await c.open(
        const MediaForgeMedia.network('http://127.0.0.1:8080/stream'),
      );
      await c.selectSubtitleTrack(3);
      await c.setSubtitleDelay(const Duration(seconds: 2));
      expect(fake.subtitleDelayMs, 2000);
      // Cue [5s,9s) now reads at 7s, silent at 5s.
      expect(
        await c.subtitleTextAt(const Duration(seconds: 5)),
        isNull,
      );
      expect(
        await c.subtitleTextAt(const Duration(seconds: 7)),
        'Hello',
      );
    });

    test('subtitlesEnabled gates delivery', () async {
      final fake = FakeMediaPlaybackEngine();
      final c = makeController(fake);
      addTearDown(c.dispose);
      await c.open(
        const MediaForgeMedia.network('http://127.0.0.1:8080/stream'),
      );
      await c.selectSubtitleTrack(3);
      await c.setSubtitlesEnabled(false);
      expect(
        await c.subtitleTextAt(const Duration(seconds: 6)),
        isNull,
      );
      await c.setSubtitlesEnabled(true);
      expect(
        await c.subtitleTextAt(const Duration(seconds: 6)),
        'Hello',
      );
    });

    test('external subtitle opens engine session + records track',
        () async {
      final fake = FakeMediaPlaybackEngine();
      final c = makeController(fake);
      addTearDown(c.dispose);
      await c.open(
        const MediaForgeMedia.network('http://127.0.0.1:8080/stream'),
      );
      final id = await c.addExternalSubtitle(
        Uri.parse('http://127.0.0.1:8080/subs/en.srt'),
        language: 'en',
      );
      expect(
        fake.externalOpened,
        ['http://127.0.0.1:8080/subs/en.srt'],
      );
      final track = c.value.subtitleTracks.singleWhere((t) => t.id == id);
      expect(track.isEmbedded, isFalse);
      await c.selectSubtitleTrack(id);
      expect(c.value.selectedSubtitleTrackId, id);
      await c.closeExternalSubtitles();
      expect(
        c.value.subtitleTracks.any((t) => t.id == id),
        isFalse,
      );
      expect(c.value.selectedSubtitleTrackId, isNull);
    });
  });

  group('volume', () {
    test('setVolume reaches engine gain', () async {
      final fake = FakeMediaPlaybackEngine();
      final c = makeController(fake);
      addTearDown(c.dispose);
      await c.open(
        const MediaForgeMedia.network('http://127.0.0.1:8080/stream'),
      );
      await c.setVolume(0.25);
      expect(fake.volume, 0.25);
      expect(c.value.volume, 0.25);
    });
  });

  group('diagnostics mapping', () {
    test('engine telemetry surfaces in MediaForgeDiagnostics', () async {
      final fake = FakeMediaPlaybackEngine();
      final c = makeController(fake);
      addTearDown(c.dispose);
      await c.open(
        const MediaForgeMedia.network('http://127.0.0.1:8080/stream'),
      );
      // Drive one diagnostics tick directly.
      await c.diagnosticsTickForTest();
      final d = c.lastDiagnostics;
      expect(d, isNotNull);
      expect(d!.bytesRead, 1024 * 1024);
      expect(d.networkBytesRead, 1024 * 1024);
      expect(d.readBitrateBps, 800000);
      expect(d.bufferedDurationMs, 2000);
      expect(d.activeDecoder, 'h264-videotoolbox');
      expect(d.hwDecode, isTrue);
      expect(d.subtitleCuesPending, 2);
      expect(d.selectedAudioIndex, 1);
    });
  });

  group('lifecycle stability', () {
    test('repeated open/dispose leaves no dangling engine', () async {
      for (var i = 0; i < 25; i++) {
        final fake = FakeMediaPlaybackEngine();
        final c = MediaForgePlayerController(
          textureHandle: 0x5EED0000 + i,
          engineFactory: ({
            required int textureHandle,
            required BigInt maxQueueSize,
            required int previewMaxEdge,
          }) async =>
              fake,
        );
        await c.open(
          MediaForgeMedia.network('http://127.0.0.1:8080/s$i'),
        );
        await c.play();
        await c.seek(const Duration(seconds: 30));
        await c.pause();
        expect(fake.openedUrls, ['http://127.0.0.1:8080/s$i']);
        c.dispose();
      }
    });

    test('reopen replaces source and resets position', () async {
      final fake = FakeMediaPlaybackEngine();
      final c = makeController(fake);
      addTearDown(c.dispose);
      await c.open(
        const MediaForgeMedia.network('http://127.0.0.1:8080/a'),
      );
      await c.seek(const Duration(seconds: 60));
      await c.open(
        const MediaForgeMedia.network('http://127.0.0.1:8080/b'),
      );
      expect(fake.openedUrls,
          ['http://127.0.0.1:8080/a', 'http://127.0.0.1:8080/b']);
      expect(c.value.position, Duration.zero);
    });
  });
}
