import 'package:flutter_test/flutter_test.dart';
import 'package:media_forge/media_forge.dart' as mf;
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

    test('default subtitle auto-selects, switch on/off + poll text',
        () async {
      final fake = FakeMediaPlaybackEngine();
      final c = makeController(fake);
      addTearDown(c.dispose);
      await c.open(
        const MediaForgeMedia.network('http://127.0.0.1:8080/stream'),
      );
      // Index 3 is flagged default → selected on open, cues flow.
      expect(c.value.selectedSubtitleTrackId, 3);
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
      // Explicit Off → no cues and no bridge poll.
      final pollsBefore = c.subtitlePollCountForTest;
      await c.selectSubtitleTrack(null);
      expect(fake.subtitleSelectLog, [3, -1]);
      expect(
        await c.subtitleTextAt(const Duration(seconds: 6)),
        isNull,
      );
      expect(c.subtitlePollCountForTest, pollsBefore);
      // Switching to the non-default track still works.
      await c.selectSubtitleTrack(4);
      expect(fake.subtitleSelectLog, [3, -1, 4]);
      expect(c.value.selectedSubtitleTrackId, 4);
      expect(
        await c.subtitleTextAt(const Duration(seconds: 6)),
        'Hello',
      );
      expect(() => c.selectSubtitleTrack(99), throwsRangeError);
    });

    test('forced embedded track wins over default', () async {
      final fake = FakeMediaPlaybackEngine(
        streams: [
          ...FakeMediaPlaybackEngine()
              .streams
              .where((s) => s.kind != mf.StreamKind.subtitle),
          _subtitleStream(4, isForced: true),
          _subtitleStream(3, isDefault: true),
        ],
      );
      final c = makeController(fake);
      addTearDown(c.dispose);
      await c.open(
        const MediaForgeMedia.network('http://127.0.0.1:8080/stream'),
      );
      expect(c.value.selectedSubtitleTrackId, 4);
      expect(fake.subtitleSelectLog, [4]);
    });

    test('auto-select is skipped while subtitles are disabled', () async {
      final fake = FakeMediaPlaybackEngine();
      final c = makeController(fake);
      addTearDown(c.dispose);
      await c.setSubtitlesEnabled(false);
      await c.open(
        const MediaForgeMedia.network('http://127.0.0.1:8080/stream'),
      );
      expect(c.value.selectedSubtitleTrackId, isNull);
      expect(fake.subtitleSelectLog, isEmpty);
      expect(
        await c.subtitleTextAt(const Duration(seconds: 6)),
        isNull,
      );
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

    test('file:// URIs reach the engine as plain paths', () async {
      final fake = FakeMediaPlaybackEngine();
      final c = makeController(fake);
      addTearDown(c.dispose);
      await c.open(
        const MediaForgeMedia.network('http://127.0.0.1:8080/stream'),
      );
      final id = await c.addExternalSubtitle(Uri.file('/tmp/a.srt'));
      // FFmpeg's file protocol wants /tmp/a.srt, never file:///tmp/a.srt.
      expect(fake.externalOpened, ['/tmp/a.srt']);
      expect(fake.externalOpened.single, isNot(startsWith('file://')));
      await c.selectSubtitleTrack(id);
      expect(c.value.selectedSubtitleTrackId, id);
      expect(
        await c.subtitleTextAt(const Duration(seconds: 6)),
        'Hello',
      );
    });

    test('plain path, file:// and http(s) variants all deliver cues',
        () async {
      final fake = FakeMediaPlaybackEngine();
      final c = makeController(fake);
      addTearDown(c.dispose);
      await c.open(
        const MediaForgeMedia.network('http://127.0.0.1:8080/stream'),
      );
      // Bare path: passed through as a path.
      final plain = await c.addExternalSubtitle(Uri.parse('/plain/path.srt'));
      expect(fake.externalOpened.last, '/plain/path.srt');
      await c.selectSubtitleTrack(plain);
      expect(
        await c.subtitleTextAt(const Duration(seconds: 6)),
        'Hello',
      );
      // file:// URL: decoded to the same path.
      final fileUrl = await c.addExternalSubtitle(
        Uri.parse('file:///tmp/a.srt'),
      );
      expect(fake.externalOpened.last, '/tmp/a.srt');
      await c.selectSubtitleTrack(fileUrl);
      expect(
        await c.subtitleTextAt(const Duration(seconds: 12)),
        'World',
      );
      // http(s): verbatim (Range reads keep working).
      final url = await c.addExternalSubtitle(
        Uri.parse('https://example.com/a.vtt'),
      );
      expect(fake.externalOpened.last, 'https://example.com/a.vtt');
      expect(c.value.subtitleTracks.length, 5); // 2 embedded + 3 sidecars
      await c.selectSubtitleTrack(url);
      expect(
        await c.subtitleTextAt(const Duration(seconds: 6)),
        'Hello',
      );
    });

    test('selecting Off hides an open sidecar session deterministically',
        () async {
      final fake = FakeMediaPlaybackEngine();
      final c = makeController(fake);
      addTearDown(c.dispose);
      await c.open(
        const MediaForgeMedia.network('http://127.0.0.1:8080/stream'),
      );
      final id = await c.addExternalSubtitle(Uri.file('/tmp/a.srt'));
      await c.selectSubtitleTrack(id);
      expect(
        await c.subtitleTextAt(const Duration(seconds: 6)),
        'Hello',
      );
      final pollsBefore = c.subtitlePollCountForTest;
      await c.selectSubtitleTrack(null);
      // Embedded forwarding stops and the open sidecar session is hidden:
      // no cue, no bridge poll.
      expect(fake.subtitleSelectLog.last, -1);
      expect(
        await c.subtitleTextAt(const Duration(seconds: 6)),
        isNull,
      );
      expect(c.subtitlePollCountForTest, pollsBefore);
      // Nothing is lost: re-selecting the sidecar track resumes delivery.
      await c.selectSubtitleTrack(id);
      expect(
        await c.subtitleTextAt(const Duration(seconds: 7)),
        'Hello',
      );
    });

    test('open() replaces the sidecar session and clears external tracks',
        () async {
      final fake = FakeMediaPlaybackEngine();
      final c = makeController(fake);
      addTearDown(c.dispose);
      await c.open(
        const MediaForgeMedia.network('http://127.0.0.1:8080/stream'),
      );
      final id = await c.addExternalSubtitle(Uri.file('/tmp/a.srt'));
      await c.selectSubtitleTrack(id);
      expect(c.value.subtitleTracks.any((t) => !t.isEmbedded), isTrue);
      await c.open(
        const MediaForgeMedia.network('http://127.0.0.1:8081/next'),
      );
      expect(c.value.subtitleTracks.any((t) => !t.isEmbedded), isFalse);
      expect(fake.externalOpen, isFalse);
      // Fresh session: the default embedded track auto-selects again.
      expect(c.value.selectedSubtitleTrackId, 3);
      expect(
        await c.subtitleTextAt(const Duration(seconds: 6)),
        'Hello',
      );
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

mf.MediaStreamInfo _subtitleStream(
  int index, {
  bool isDefault = false,
  bool isForced = false,
}) =>
    mf.MediaStreamInfo(
      index: index,
      kind: mf.StreamKind.subtitle,
      codecName: 'subrip',
      language: '',
      title: '',
      bitrate: BigInt.zero,
      width: 0,
      height: 0,
      channels: 0,
      sampleRate: 0,
      isDefault: isDefault,
      isForced: isForced,
    );
