import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_forge_player/media_forge_player.dart';

import 'fake_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MediaForgePlayerController makeController(
    FakeMediaPlaybackEngine fake, {
    int handle = 0xB0FF0001,
  }) {
    return MediaForgePlayerController(
      textureHandle: handle,
      engineFactory:
          ({
            required int textureHandle,
            required BigInt maxQueueSize,
            required int previewMaxEdge,
          }) async => fake,
    );
  }

  group('buffered range model', () {
    test('range invariants + duration', () {
      const r = MediaForgeBufferedRange(
        start: Duration(seconds: 10),
        end: Duration(seconds: 20),
      );
      expect(r.duration, const Duration(seconds: 10));
      expect(r.isEmpty, isFalse);
      expect(r.contains(const Duration(seconds: 15)), isTrue);
      expect(r.contains(const Duration(seconds: 25)), isFalse);
    });

    test('normalize merges overlapping and drops empty/invalid', () {
      final out = normalizeBufferedRanges([
        const MediaForgeBufferedRange(
          start: Duration(seconds: 0),
          end: Duration(seconds: 10),
        ),
        const MediaForgeBufferedRange(
          start: Duration(seconds: 5),
          end: Duration(seconds: 15),
        ),
        const MediaForgeBufferedRange(
          start: Duration(seconds: 20),
          end: Duration(seconds: 20),
        ),
        const MediaForgeBufferedRange(
          start: Duration(seconds: 30),
          end: Duration(seconds: 25),
        ),
      ]);
      expect(out.length, 1);
      expect(out.single.start, Duration.zero);
      expect(out.single.end, const Duration(seconds: 15));
    });

    test('contiguous buffered-ahead calculation', () {
      final ranges = normalizeBufferedRanges([
        const MediaForgeBufferedRange(
          start: Duration(seconds: 0),
          end: Duration(seconds: 60),
        ),
      ]);
      expect(
        contiguousBufferedPosition(ranges, const Duration(seconds: 10)),
        const Duration(seconds: 60),
      );
      expect(
        bufferedAhead(ranges, const Duration(seconds: 10)),
        const Duration(seconds: 50),
      );
    });

    test('multiple non-contiguous ranges: gap returns playhead', () {
      final ranges = normalizeBufferedRanges([
        const MediaForgeBufferedRange(
          start: Duration(seconds: 0),
          end: Duration(seconds: 30),
        ),
        const MediaForgeBufferedRange(
          start: Duration(seconds: 50),
          end: Duration(seconds: 80),
        ),
      ]);
      expect(ranges.length, 2);
      // Inside first window → end of first.
      expect(
        contiguousBufferedPosition(ranges, const Duration(seconds: 10)),
        const Duration(seconds: 30),
      );
      // In the gap → playhead itself (cannot continue without stall).
      expect(
        contiguousBufferedPosition(ranges, const Duration(seconds: 40)),
        const Duration(seconds: 40),
      );
      expect(bufferedAhead(ranges, const Duration(seconds: 40)), Duration.zero);
      // Inside second window → end of second.
      expect(
        contiguousBufferedPosition(ranges, const Duration(seconds: 60)),
        const Duration(seconds: 80),
      );
    });

    test('merge does not double-count overlapping availability', () {
      final internal = [
        const MediaForgeBufferedRange(
          start: Duration(seconds: 285),
          end: Duration(seconds: 292),
        ),
      ];
      final external = [
        const MediaForgeBufferedRange(
          start: Duration(seconds: 290),
          end: Duration(seconds: 310),
        ),
      ];
      final merged = mergeBufferedRanges(internal, external);
      expect(merged.length, 1);
      expect(merged.single.start, const Duration(seconds: 285));
      expect(merged.single.end, const Duration(seconds: 310));
    });
  });

  group('engine-backed buffering (real queues, no faking from position)', () {
    test('network buffering derives from queues, not full duration', () async {
      final fake = FakeMediaPlaybackEngine();
      final c = makeController(fake);
      addTearDown(c.dispose);
      await c.open(
        const MediaForgeMedia.network('http://127.0.0.1:8080/stream'),
      );
      await c.diagnosticsTickForTest();
      // Fake: 10 video packets (~400ms) + 2000ms decoded-ahead.
      // Must NOT claim the entire 120s duration as buffered.
      expect(c.value.duration, const Duration(milliseconds: 120000));
      expect(c.value.bufferedPosition.inMilliseconds, lessThan(120000));
      expect(c.value.bufferedPosition, c.value.buffered);
      expect(c.value.bufferedRanges, isNotEmpty);
      // Contiguous ahead matches position + honest window.
      expect(
        c.value.bufferedAhead,
        c.value.bufferedPosition - c.value.position,
      );
      // Diagnostics separate compressed vs decoded.
      expect(c.value.packetBufferedBytes, greaterThan(0));
      expect(c.value.decodedVideoFrames, greaterThanOrEqualTo(0));
      final diag = c.lastDiagnostics!;
      expect(diag.videoPacketsInQueue, 10);
      expect(diag.videoQueueBytes, greaterThan(0));
    });

    test('file source reports full availability, no network spinner', () async {
      final fake = FakeMediaPlaybackEngine();
      final c = makeController(fake);
      addTearDown(c.dispose);
      // Stage a real temp file so open() takes the file path.
      final tmp = File(
        '${Directory.systemTemp.path}/mfp_buf_${DateTime.now().microsecondsSinceEpoch}.mp4',
      );
      await tmp.writeAsBytes([0, 1, 2, 3]);
      addTearDown(() async {
        try {
          await tmp.delete();
        } catch (_) {}
      });
      await c.open(MediaForgeMedia.file(tmp.path));
      await c.play();
      await c.diagnosticsTickForTest();
      expect(c.value.bufferedRanges.length, 1);
      expect(c.value.bufferedRanges.single.start, Duration.zero);
      expect(c.value.bufferedRanges.single.end, c.value.duration);
      expect(c.value.bufferedPosition, c.value.duration);
      // Files never preload in the network sense.
      expect(c.value.isPreloading, isFalse);
    });

    test('buffering advances while paused until budget/backpressure', () async {
      final fake = FakeMediaPlaybackEngine();
      final c = makeController(fake);
      addTearDown(c.dispose);
      await c.open(
        const MediaForgeMedia.network('http://127.0.0.1:8080/stream'),
      );
      await c.play();
      await c.pause();
      expect(c.value.isPlaying, isFalse);
      await c.diagnosticsTickForTest();
      final before = c.value.bufferedPosition.inMilliseconds;

      // Demux read-ahead continues while paused: grow compressed packets.
      fake.videoPacketQueueLen = 60; // ~2400ms
      fake.audioPacketQueueLen = 40;
      await c.diagnosticsTickForTest();
      final grown = c.value.bufferedPosition.inMilliseconds;
      expect(grown, greaterThan(before));
      // Still paused: presentation did not advance, but buffer did.
      expect(c.value.isPlaying, isFalse);
      expect(c.value.bufferedAhead.inMilliseconds, greaterThan(0));
      // Background preloading while paused: no big spinner.
      expect(c.value.isPreloading, isTrue);
      expect(c.value.isRebuffering, isFalse);

      // Unbounded growth is capped by the 5s packet budget.
      fake.videoPacketQueueLen = 10000;
      fake.audioPacketQueueLen = 10000;
      await c.diagnosticsTickForTest();
      final capped = c.value.bufferedPosition.inMilliseconds;
      // 2000ms decoded + 5000ms budget cap = ~7000ms ahead max.
      final ahead = capped - c.value.position.inMilliseconds;
      expect(ahead, lessThanOrEqualTo(7000 + 500));
      expect(capped, lessThanOrEqualTo(120000));
    });

    test('decoded-frame queue does not grow while paused', () async {
      final fake = FakeMediaPlaybackEngine();
      final c = makeController(fake);
      addTearDown(c.dispose);
      await c.open(
        const MediaForgeMedia.network('http://127.0.0.1:8080/stream'),
      );
      await c.play();
      await c.pause();
      fake.videoPacketQueueLen = 80;
      fake.videoFrameQueueLenOverride = 0;
      await c.diagnosticsTickForTest();
      expect(c.value.decodedVideoFrames, 0);
      expect(c.value.packetBufferedBytes, greaterThan(0));
      // No presentation work while paused.
      final bridgesBefore = c.bridgeCallCount;
      await c.presentationTickForTest();
      expect(c.bridgeCallCount, bridgesBefore);
      expect(c.presentedFrameCount, 0);
    });

    test('rebuffering vs preloading are distinct', () async {
      final fake = FakeMediaPlaybackEngine();
      final c = makeController(fake);
      addTearDown(c.dispose);
      await c.open(
        const MediaForgeMedia.network('http://127.0.0.1:8080/stream'),
      );
      await c.play();
      // Stall: playing but no decoded frames → rebuffering (spinner ok).
      fake.videoFrameQueueLenOverride = 0;
      fake.videoPacketQueueLen = 0;
      fake.audioPacketQueueLen = 0;
      fake.bufferedDurationMs = 0;
      await c.diagnosticsTickForTest();
      // Hysteresis prevents a one-tick empty decode queue from showing a
      // spinner or changing transport state.
      await Future<void>.delayed(const Duration(milliseconds: 800));
      await c.diagnosticsTickForTest();
      expect(c.value.isRebuffering, isTrue);
      expect(c.runtimeState.value, MediaForgePlayerRuntimeState.rebuffering);
      // Rebuffering is observational only. The controller must retain the
      // current source/position rather than issuing a recovery seek.
      expect(fake.seekLog, isEmpty);
      // Healthy read-ahead while playing → preloading, not rebuffering.
      fake.videoFrameQueueLenOverride = 3;
      fake.videoPacketQueueLen = 20;
      fake.bufferedDurationMs = 2000;
      await c.diagnosticsTickForTest();
      // Recovery hysteresis needs the ready condition to hold for
      // _rebufferExitDelay (350ms) before the spinner clears.
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await c.diagnosticsTickForTest();
      expect(c.value.isRebuffering, isFalse);
      expect(c.value.isPreloading, isTrue);
      expect(c.value.bufferedAhead.inMilliseconds, greaterThan(0));
    });

    test('external buffered ranges are accepted and merged', () async {
      final fake = FakeMediaPlaybackEngine();
      final c = makeController(fake);
      addTearDown(c.dispose);
      await c.open(
        const MediaForgeMedia.network('http://127.0.0.1:8080/stream'),
      );
      await c.diagnosticsTickForTest();
      final internalEnd = c.value.bufferedPosition;
      // Host knows pieces far ahead (e.g. torrent cache) the engine has
      // not demuxed yet.
      c.setExternalBufferedRanges([
        MediaForgeBufferedRange(
          start: internalEnd + const Duration(seconds: 30),
          end: internalEnd + const Duration(seconds: 90),
        ),
      ]);
      expect(c.externalBufferedRanges.length, 1);
      expect(c.value.bufferedRanges.length, 2);
      // Contiguous point is still the internal head (gap ahead).
      expect(c.value.bufferedPosition, internalEnd);
      // Overlapping external is display-only. It must not convince the
      // decoder that compressed data is available for playback.
      c.setExternalBufferedRanges([
        MediaForgeBufferedRange(
          start: c.value.position,
          end: internalEnd + const Duration(seconds: 60),
        ),
      ]);
      expect(c.value.bufferedRanges.length, 1);
      expect(c.value.bufferedPosition, internalEnd);
      c.clearExternalBufferedRanges();
      expect(c.externalBufferedRanges, isEmpty);
    });

    test(
      'bufferState notifier mirrors value without texture rebuild',
      () async {
        final fake = FakeMediaPlaybackEngine();
        final c = makeController(fake);
        addTearDown(c.dispose);
        await c.open(
          const MediaForgeMedia.network('http://127.0.0.1:8080/stream'),
        );
        var notifications = 0;
        void listener() => notifications++;
        c.bufferState.addListener(listener);
        addTearDown(() => c.bufferState.removeListener(listener));
        await c.diagnosticsTickForTest();
        expect(notifications, greaterThan(0));
        expect(c.bufferState.value.bufferedPosition, c.value.bufferedPosition);
        expect(c.bufferState.value.ranges, c.value.bufferedRanges);
      },
    );
  });

  group('generic external API (no torrent dependency)', () {
    test('external API uses generic ranges, not torrent types', () {
      // Compile-time proof: the setter accepts plain time ranges.
      final fake = FakeMediaPlaybackEngine();
      final c = MediaForgePlayerController(
        textureHandle: 0xB0FF00FF,
        engineFactory:
            ({
              required int textureHandle,
              required BigInt maxQueueSize,
              required int previewMaxEdge,
            }) async => fake,
      );
      addTearDown(c.dispose);
      expect(
        () => c.setExternalBufferedRanges([
          const MediaForgeBufferedRange(
            start: Duration(seconds: 285),
            end: Duration(seconds: 300),
          ),
        ]),
        returnsNormally,
      );
      // Generic model carries no torrent/piece fields.
      const r = MediaForgeBufferedRange(
        start: Duration(seconds: 1),
        end: Duration(seconds: 2),
      );
      expect(r.toString(), contains('1000ms'));
    });

    testWidgets('timeline renders merged ranges while paused', (tester) async {
      final fake = FakeMediaPlaybackEngine();
      final controller = makeController(fake);
      await controller.open(
        const MediaForgeMedia.network('http://127.0.0.1:8080/v'),
      );
      await controller.pause();
      controller.setExternalBufferedRanges([
        const MediaForgeBufferedRange(
          start: Duration(seconds: 60),
          end: Duration(seconds: 90),
        ),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(body: MediaPlayerScreen(controller: controller)),
        ),
      );
      await tester.pump();
      expect(find.byType(PlayerTimeline), findsOneWidget);
      // Paused: no stall spinner from background caching.
      expect(find.text('Buffering…'), findsNothing);
      controller.dispose();
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('buffered UI updates without rebuilding video surface', (
      tester,
    ) async {
      final fake = FakeMediaPlaybackEngine();
      final controller = makeController(fake);
      await controller.open(
        const MediaForgeMedia.network('http://127.0.0.1:8080/v'),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(body: MediaPlayerScreen(controller: controller)),
        ),
      );
      await tester.pump();
      final surfaceBefore = find.byType(MediaForgeVideo);
      expect(surfaceBefore, findsOneWidget);
      final surfaceElement = tester.element(surfaceBefore);
      // Advance only buffering (external cache grows).
      controller.setExternalBufferedRanges([
        const MediaForgeBufferedRange(
          start: Duration.zero,
          end: Duration(seconds: 45),
        ),
      ]);
      await tester.pump();
      // Same element (no surface rebuild), timeline still present.
      expect(
        tester.element(find.byType(MediaForgeVideo)),
        same(surfaceElement),
      );
      expect(find.byType(PlayerTimeline), findsOneWidget);
      controller.dispose();
      await tester.pump(const Duration(seconds: 5));
    });
  });
}
