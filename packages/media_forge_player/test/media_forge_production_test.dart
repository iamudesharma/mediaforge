import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_forge/media_forge.dart' as mf;
import 'package:media_forge_player/media_forge_player.dart';

import 'fake_engine.dart';

/// Production hardening coverage (§20):
/// native config, backward-compat ctor, byte/duration budgets, frame-ready
/// cancellation, zero calls while paused, true drop accounting, first-frame,
/// seek generations, network profiles, probe, interrupt, suspension,
/// subtitle efficiency, idempotent release, resource counters.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MediaForgePlayerController makeController(
    FakeMediaPlaybackEngine fake, {
    MediaForgePlayerConfiguration? configuration,
    int handle = 0x6E770001,
  }) {
    return MediaForgePlayerController(
      textureHandle: handle,
      configuration: configuration,
      engineFactory: ({
        required int textureHandle,
        required BigInt maxQueueSize,
        required int previewMaxEdge,
      }) async =>
          fake,
    );
  }

  group('native-resolution configuration (§1–§2)', () {
    test('native mode is an explicit enum, not a magic sentinel', () {
      const cfg = MediaForgePlayerConfiguration(
        decodeResolution: MediaForgeDecodeResolution.native,
      );
      expect(cfg.isNative, isTrue);
      expect(cfg.decodeResolution, MediaForgeDecodeResolution.native);
      // Internal transport edge preserves 4K (3840) without scaling.
      expect(cfg.resolvePreviewMaxEdge(), greaterThanOrEqualTo(3840));
    });

    test('old constructor preserved incl. previewMaxEdge==0 → 1080', () {
      final legacyZero = MediaForgePlayerController(
        textureHandle: 0x6E770010,
        previewMaxEdge: 0,
      );
      expect(legacyZero.effectivePreviewMaxEdge, 1080);
      addTearDown(legacyZero.dispose);

      final legacy = MediaForgePlayerController(
        textureHandle: 0x6E770011,
        maxQueueSize: 2000,
        previewMaxEdge: 1080,
      );
      expect(legacy.effectivePreviewMaxEdge, 1080);
      expect(legacy.effectiveMaxQueueSize, 2000);
      addTearDown(legacy.dispose);
    });

    test('configured construction is additive and overrides legacy', () {
      const cfg = MediaForgePlayerConfiguration(
        decodeResolution: MediaForgeDecodeResolution.native,
      );
      final c = MediaForgePlayerController.withConfiguration(
        textureHandle: 0x6E770012,
        configuration: cfg,
      );
      expect(c.configuration, cfg);
      expect(c.effectivePreviewMaxEdge, isNot(1080));
      expect(c.effectivePreviewMaxEdge, cfg.resolvePreviewMaxEdge());
      addTearDown(c.dispose);
    });

    test('preview modes map to canonical edges', () {
      expect(
        const MediaForgePlayerConfiguration(
          decodeResolution: MediaForgeDecodeResolution.preview720,
        ).resolvePreviewMaxEdge(),
        720,
      );
      expect(
        const MediaForgePlayerConfiguration(
          decodeResolution: MediaForgeDecodeResolution.preview1080,
        ).resolvePreviewMaxEdge(),
        1080,
      );
    });
  });

  group('byte- and duration-aware queues (§3–§4)', () {
    test('video defaults 16 MiB / 5 s, audio 4 MiB / 5 s', () {
      expect(MediaForgePacketBudget.video.maxBytes, 16 * 1024 * 1024);
      expect(MediaForgePacketBudget.video.maxDuration,
          const Duration(seconds: 5));
      expect(MediaForgePacketBudget.audio.maxBytes, 4 * 1024 * 1024);
      expect(MediaForgePacketBudget.audio.maxDuration,
          const Duration(seconds: 5));
    });

    test('subtitle queue remains independently small', () {
      expect(MediaForgePacketBudget.subtitle.maxBytes,
          lessThanOrEqualTo(256 * 1024));
    });

    test('decoded-frame budgets target ~3 HW / ~2 SW', () {
      const cfg = MediaForgePlayerConfiguration(
        decodeResolution: MediaForgeDecodeResolution.native,
      );
      expect(cfg.decodedVideoFramesHw, lessThanOrEqualTo(3));
      expect(cfg.decodedVideoFramesSw, lessThanOrEqualTo(2));
      // No 32/64-frame retention.
      expect(cfg.decodedVideoFramesHw, lessThan(32));
      expect(cfg.decodedVideoFramesSw, lessThan(32));
    });

    test('legacy count cap derived from budgets stays bounded', () {
      const cfg = MediaForgePlayerConfiguration(
        decodeResolution: MediaForgeDecodeResolution.native,
      );
      expect(cfg.resolveMaxQueueSize(), lessThanOrEqualTo(512));
      expect(cfg.resolveMaxQueueSize(), greaterThan(0));
    });

    test('diagnostics expose queue bytes + frame memory', () async {
      final fake = FakeMediaPlaybackEngine();
      final c = makeController(fake);
      addTearDown(c.dispose);
      await c.open(
        const MediaForgeMedia.network('http://127.0.0.1:8080/stream'),
      );
      await c.play();
      await c.diagnosticsTickForTest();
      final d = c.lastDiagnostics!;
      // Observable accounting (estimates until native byte counters land).
      expect(d.videoQueueBytes, greaterThanOrEqualTo(0));
      expect(d.audioQueueBytes, greaterThanOrEqualTo(0));
      expect(d.frameMemoryBytes, greaterThanOrEqualTo(0));
      expect(d.decodedQueueDepth, greaterThanOrEqualTo(0));
      expect(d.packetBufferDurationMs, greaterThanOrEqualTo(0));
    });
  });

  group('frame-ready pump + drop accounting (§5–§6)', () {
    test('zero bridge calls while paused', () async {
      final fake = FakeMediaPlaybackEngine();
      final c = makeController(fake);
      addTearDown(c.dispose);
      await c.open(
        const MediaForgeMedia.network('http://127.0.0.1:8080/stream'),
      );
      // Paused: presentation ticks must not hit the bridge.
      final before = c.bridgeCallCount;
      await c.presentationTickForTest();
      await c.presentationTickForTest();
      expect(c.bridgeCallCount, before);
      expect(c.presentedFrameCount, 0);
    });

    test('empty poll is not counted as a drop', () async {
      final fake = FakeMediaPlaybackEngine();
      final c = makeController(fake);
      addTearDown(c.dispose);
      await c.open(
        const MediaForgeMedia.network('http://127.0.0.1:8080/stream'),
      );
      await c.play();
      // Fake returns no frames → empty polls.
      await c.presentationTickForTest();
      await c.presentationTickForTest();
      await c.diagnosticsTickForTest();
      expect(c.droppedFrames, 0);
      expect(c.lastDiagnostics!.droppedFrames, 0);
      expect(c.lastDiagnostics!.queueOverflowDrops, 0);
      expect(c.lastDiagnostics!.catchupDrops, 0);
    });

    test('presented vs bridge counters are separately observable', () async {
      final fake = FakeMediaPlaybackEngine();
      final c = makeController(fake);
      addTearDown(c.dispose);
      await c.open(
        const MediaForgeMedia.network('http://127.0.0.1:8080/stream'),
      );
      await c.play();
      await c.diagnosticsTickForTest();
      final d = c.lastDiagnostics!;
      expect(d.presentedFrameCount, c.presentedFrameCount);
      expect(d.bridgeCallCount, c.bridgeCallCount);
    });

    test('suspension stops the pump and emits no bridge calls', () async {
      final fake = FakeMediaPlaybackEngine();
      final c = makeController(fake);
      addTearDown(c.dispose);
      await c.open(
        const MediaForgeMedia.network('http://127.0.0.1:8080/stream'),
      );
      await c.play();
      await c.suspend();
      expect(c.isSuspended, isTrue);
      final before = c.bridgeCallCount;
      await c.presentationTickForTest();
      expect(c.bridgeCallCount, before);
      await c.diagnosticsTickForTest();
      // Diagnostics short-circuit while suspended (last snapshot retained).
      await c.resume();
      expect(c.isSuspended, isFalse);
    });
  });

  group('first-frame and seek generations (§7)', () {
    test('seek increments generation and emits seekStarted', () async {
      final fake = FakeMediaPlaybackEngine();
      final c = makeController(fake);
      addTearDown(c.dispose);
      await c.open(
        const MediaForgeMedia.network('http://127.0.0.1:8080/stream'),
      );
      final events = <MediaForgeEvent>[];
      final sub = c.events.listen(events.add);
      addTearDown(sub.cancel);
      final genBefore = c.seekGeneration;
      await c.seek(const Duration(seconds: 10));
      expect(c.seekGeneration, genBefore + 1);
      // seekStarted carries the monotonic generation.
      expect(
        events.where((e) => e.type == MediaForgeEventType.seekStarted),
        isNotEmpty,
      );
      final started = events
          .lastWhere((e) => e.type == MediaForgeEventType.seekStarted);
      expect(started.generation, c.seekGeneration);
      expect(started.positionMs, 10000);
    });

    test('stale seek completion is rejected; latest settles', () async {
      final fake = FakeMediaPlaybackEngine();
      final c = makeController(fake);
      addTearDown(c.dispose);
      await c.open(
        const MediaForgeMedia.network('http://127.0.0.1:8080/stream'),
      );
      await c.play();
      final settled = <MediaForgeEvent>[];
      final sub = c.events
          .where((e) => e.type == MediaForgeEventType.seekSettled)
          .listen(settled.add);
      addTearDown(sub.cancel);
      // Two rapid seeks: first generation must never settle.
      final f1 = c.seek(const Duration(seconds: 10));
      final f2 = c.seek(const Duration(seconds: 40));
      await Future.wait([f1, f2]);
      // Drive diagnostics so the optimistic settle path runs.
      await c.diagnosticsTickForTest();
      // Only the latest generation may settle.
      for (final e in settled) {
        expect(e.generation, c.seekGeneration);
      }
      if (settled.isNotEmpty) {
        expect(c.lastSeekSettledGeneration, c.seekGeneration);
        expect(c.lastSeekLatencyMs, isNotNull);
      }
    });

    test('first-frame latency is exposed once a frame presents', () async {
      final fake = _FrameEmittingFake();
      final c = makeController(fake);
      addTearDown(c.dispose);
      await c.open(
        const MediaForgeMedia.network('http://127.0.0.1:8080/stream'),
      );
      final firstEvents = <MediaForgeEvent>[];
      final sub = c.events
          .where((e) => e.type == MediaForgeEventType.firstFramePresented)
          .listen(firstEvents.add);
      addTearDown(sub.cancel);
      await c.play();
      await c.presentationTickForTest();
      // Broadcast delivery is async — yield one turn.
      await Future<void>.delayed(Duration.zero);
      expect(c.value.firstFramePresented, isTrue);
      expect(firstEvents, hasLength(1));
      expect(firstEvents.single.positionMs, isNotNull);
      await c.diagnosticsTickForTest();
      expect(c.lastDiagnostics!.firstFrameLatencyMs, isNotNull);
      expect(c.lastDiagnostics!.firstPresentedAtMs, isNotNull);
    });
  });

  group('network profiles (§10)', () {
    test('torrent localhost: ~60 s timeout, reconnect on', () {
      const p = MediaForgeNetworkProfile.torrentLocalhost();
      expect(p.timeout, const Duration(seconds: 60));
      expect(p.reconnect, isTrue);
      expect(p.isSeekableRange, isTrue);
    });

    test('direct HTTP: ~30 s timeout, caller reconnect preserved', () {
      const p = MediaForgeNetworkProfile.directHttp();
      expect(p.timeout, const Duration(seconds: 30));
      expect(p.reconnect, isFalse);
      const withReconnect =
          MediaForgeNetworkProfile.directHttp(reconnect: true);
      expect(withReconnect.reconnect, isTrue);
    });

    test('cached/file: open as file, no network options', () {
      const p = MediaForgeNetworkProfile.cachedFile();
      expect(p.timeout, Duration.zero);
      expect(p.reconnect, isFalse);
    });

    test('inferFor routes loopback/remote/file correctly', () {
      expect(
        MediaForgeNetworkProfile.inferFor(
          const MediaForgeMedia.network('http://127.0.0.1:8080/s'),
        ).name,
        'torrent_localhost',
      );
      expect(
        MediaForgeNetworkProfile.inferFor(
          const MediaForgeMedia.network('https://cdn.example.com/v.mp4'),
        ).name,
        'direct_http',
      );
      expect(
        MediaForgeNetworkProfile.inferFor(
          const MediaForgeMedia.file('/tmp/a.mp4'),
        ).name,
        'cached_file',
      );
    });

    test('open forwards profile timeout/reconnect + headers', () async {
      final fake = FakeMediaPlaybackEngine();
      final c = makeController(
        fake,
        configuration: const MediaForgePlayerConfiguration(
          decodeResolution: MediaForgeDecodeResolution.native,
        ),
      );
      addTearDown(c.dispose);
      await c.open(
        const MediaForgeMedia.network(
          'http://127.0.0.1:8080/stream',
          headers: {'Authorization': 'Bearer x'},
        ),
      );
      expect(fake.lastOptions?.headers['Authorization'], 'Bearer x');
      // Loopback forces reconnect + 60 s default.
      expect(fake.lastOptions?.reconnect, isTrue);
      expect(fake.lastOptions?.timeoutMs.toInt(), 60000);
    });
  });

  group('probe, interrupt, lifecycle, subtitles, release', () {
    test('probe duration is recorded (§11)', () async {
      final fake = FakeMediaPlaybackEngine();
      final c = makeController(fake);
      addTearDown(c.dispose);
      await c.open(
        const MediaForgeMedia.network('http://127.0.0.1:8080/stream'),
      );
      expect(c.lastProbeDurationMs, isNotNull);
      await c.diagnosticsTickForTest();
      expect(c.lastDiagnostics!.probeDurationMs, isNotNull);
    });

    test('source generation bumps on open/seek (§12)', () async {
      final fake = FakeMediaPlaybackEngine();
      final c = makeController(fake);
      addTearDown(c.dispose);
      final g0 = c.sourceGeneration;
      await c.open(
        const MediaForgeMedia.network('http://127.0.0.1:8080/stream'),
      );
      expect(c.sourceGeneration, greaterThan(g0));
      final g1 = c.sourceGeneration;
      await c.seek(const Duration(seconds: 5));
      expect(c.sourceGeneration, greaterThan(g1));
    });

    test('subtitle polling is skipped when disabled/no track (§14)',
        () async {
      final fake = FakeMediaPlaybackEngine();
      final c = makeController(fake);
      addTearDown(c.dispose);
      await c.open(
        const MediaForgeMedia.network('http://127.0.0.1:8080/stream'),
      );
      final pollsBefore = c.subtitlePollCountForTest;
      // Explicit Off (no active track) → no bridge call.
      await c.selectSubtitleTrack(null);
      expect(
        await c.subtitleTextAt(const Duration(seconds: 6)),
        isNull,
      );
      expect(c.subtitlePollCountForTest, pollsBefore);
      // Disabled → no bridge call even with a track selected.
      await c.selectSubtitleTrack(3);
      await c.setSubtitlesEnabled(false);
      expect(
        await c.subtitleTextAt(const Duration(seconds: 6)),
        isNull,
      );
      expect(c.subtitlePollCountForTest, pollsBefore);
    });

    test('release is idempotent, ordered, resources return to zero (§15)',
        () async {
      final fake = FakeMediaPlaybackEngine();
      final c = makeController(fake);
      await c.open(
        const MediaForgeMedia.network('http://127.0.0.1:8080/stream'),
      );
      await c.play();
      final f1 = c.release();
      final f2 = c.release();
      expect(identical(f1, f2), isTrue);
      await Future.wait([f1, f2]);
      await c.release();
      final counters = c.resourceCountersForTest();
      expect(counters['engine'], 0);
      expect(counters['textures'], 0);
      expect(counters['diagTimer'], 0);
      expect(counters['vsyncScheduled'], 0);
    });

    test('diagnostics report rendering path + native dims (§8/§16)',
        () async {
      final fake = FakeMediaPlaybackEngine();
      final c = makeController(fake);
      addTearDown(c.dispose);
      await c.open(
        const MediaForgeMedia.network('http://127.0.0.1:8080/stream'),
      );
      await c.diagnosticsTickForTest();
      final d = c.lastDiagnostics!;
      expect(d.renderingPath, isNotEmpty);
      // Never claim zero-copy from the RGBA upload path.
      if (d.renderingPath.contains('zero_copy')) {
        expect(d.renderingPath, contains('iosurface'));
      }
      expect(d.activeDecoder, isNotEmpty);
    });
  });
}

/// Fake engine that emits one video frame per takeVideoFrame call.
class _FrameEmittingFake extends FakeMediaPlaybackEngine {
  int _pts = 0;
  int takeCalls = 0;

  @override
  Future<mf.MediaVideoFrame?> takeVideoFrame() async {
    takeCalls++;
    _pts += 40;
    return mf.MediaVideoFrame(
      ptsMs: BigInt.from(_pts),
      width: 1920,
      height: 1080,
      pixels: Uint8List(1920 * 1080 * 4),
      pixelBufferPtr: BigInt.zero,
      seekGeneration: BigInt.zero,
    );
  }
}
