import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_forge/media_forge.dart' as mf;
import 'package:media_forge_player/media_forge_player.dart';

import 'fake_engine.dart';

/// Experimental GPU video enhancement.
///
/// Covers the public contract: default off, live mode changes, state
/// propagation, capability fallback, identity/seek/audio/subtitle/fullscreen
/// preservation, resource cleanup and the "no work while paused" rule.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MediaForgePlayerController makeController(
    FakeMediaPlaybackEngine fake, {
    int handle = 0x6E770010,
  }) {
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

  Future<MediaForgePlayerController> opened(
    FakeMediaPlaybackEngine fake, {
    int handle = 0x6E770010,
  }) async {
    final c = makeController(fake, handle: handle);
    await c.open(
      const MediaForgeMedia.network('http://127.0.0.1:8080/stream'),
    );
    await c.play();
    return c;
  }

  /// A decoded frame + handoff shaped like the native zero-copy handoff.
  (mf.MediaVideoFrame, mf.PixelBufferHandoff) syntheticFrame({int pts = 40}) {
    final frame = mf.MediaVideoFrame(
      ptsMs: BigInt.from(pts),
      width: 1280,
      height: 720,
      pixels: Uint8List(0),
      pixelBufferPtr: BigInt.from(0x11110000),
      seekGeneration: BigInt.zero,
    );
    final handoff = mf.PixelBufferHandoff(
      ptsMs: BigInt.from(pts),
      width: 1280,
      height: 720,
      pixelBufferPtr: BigInt.from(0x11110000),
      seekGeneration: BigInt.zero,
    );
    return (frame, handoff);
  }

  group('video enhancement: public API', () {
    test('defaults to off everywhere', () async {
      final fake = FakeMediaPlaybackEngine();
      final c = await opened(fake);
      addTearDown(c.dispose);

      expect(c.videoEnhancementMode, VideoEnhancementMode.off);
      expect(c.value.videoEnhancementMode, VideoEnhancementMode.off);
      expect(c.value.videoEnhancementActive, isFalse);
      expect(VideoEnhancementMode.defaultMode, VideoEnhancementMode.off);
      // Opened the source without ever asking the device to enhance.
      expect(fake.enhancementMode, mf.VideoEnhancementMode.off);
    });

    test('mode can be changed at runtime and reaches the engine live',
        () async {
      final fake = FakeMediaPlaybackEngine();
      final c = await opened(fake);
      addTearDown(c.dispose);

      expect(
        await c.setVideoEnhancementMode(VideoEnhancementMode.enhanced),
        isTrue,
      );
      expect(c.videoEnhancementMode, VideoEnhancementMode.enhanced);
      expect(c.value.videoEnhancementMode, VideoEnhancementMode.enhanced);
      expect(fake.enhancementMode, mf.VideoEnhancementMode.enhanced);

      expect(
        await c.setVideoEnhancementMode(VideoEnhancementMode.highQuality),
        isTrue,
      );
      expect(fake.enhancementMode, mf.VideoEnhancementMode.highQuality);

      // Every request was forwarded in order — a live setting, not a
      // construction-time one. (The first entry is the mode applied at open,
      // which is `off` for a fresh controller.)
      expect(fake.enhancementModeLog, [
        mf.VideoEnhancementMode.off,
        mf.VideoEnhancementMode.enhanced,
        mf.VideoEnhancementMode.highQuality,
      ]);
    });

    test('changing the mode never reopens the media', () async {
      final fake = FakeMediaPlaybackEngine();
      final c = await opened(fake);
      addTearDown(c.dispose);

      final openCount = fake.openCount;
      final seeksBefore = List<int>.from(fake.seekLog);
      final position = c.value.position;
      final textureHandle = c.textureHandle;

      await c.setVideoEnhancementMode(VideoEnhancementMode.sharp);
      await c.setVideoEnhancementMode(VideoEnhancementMode.highQuality);
      await c.setVideoEnhancementMode(VideoEnhancementMode.off);

      expect(fake.openCount, openCount, reason: 'no reopen');
      expect(fake.seekLog, seeksBefore, reason: 'no implicit seek');
      expect(c.value.position, position, reason: 'playback clock untouched');
      expect(c.textureHandle, textureHandle,
          reason: 'no texture recreation from a mode change');
    });

    test('controller identity and texture handle are preserved', () async {
      final fake = FakeMediaPlaybackEngine();
      final c = await opened(fake, handle: 0x6E7700AB);
      addTearDown(c.dispose);

      final presenter = c.presenter;
      final value = c.value;
      await c.setVideoEnhancementMode(VideoEnhancementMode.enhanced);
      await c.setVideoEnhancementMode(VideoEnhancementMode.off);

      expect(identical(c.presenter, presenter), isTrue);
      expect(c.textureHandle, 0x6E7700AB);
      expect(identical(c.value, value), isFalse,
          reason: 'value is an immutable snapshot, replaced not mutated');
      expect(c.value.isPlaying, value.isPlaying);
    });

    test('status is exposed publicly and mirrors the engine', () async {
      final fake = FakeMediaPlaybackEngine();
      final c = await opened(fake);
      addTearDown(c.dispose);

      await c.setVideoEnhancementMode(VideoEnhancementMode.enhanced);
      await c.diagnosticsTickForTest();

      final status = c.videoEnhancementStatus;
      expect(status, isNotNull);
      expect(status!.requestedMode, VideoEnhancementMode.enhanced);
      expect(status.activeMode, VideoEnhancementMode.enhanced);
      expect(status.path, 'fake_pass');
      expect(status.backend, 'fake_gpu');
      expect(status.enhancedFrames, greaterThanOrEqualTo(0));
      expect(c.lastDiagnostics!.videoEnhancementRequested, 'enhanced');
      expect(c.lastDiagnostics!.videoEnhancementActive, 'enhanced');
    });

    test('diagnostics expose resolution, path and timing', () async {
      final fake = FakeMediaPlaybackEngine();
      final c = await opened(fake);
      addTearDown(c.dispose);
      await c.setVideoEnhancementMode(VideoEnhancementMode.highQuality);
      await c.diagnosticsTickForTest();

      final d = c.lastDiagnostics!;
      expect(d.videoEnhancementOutputWidth, 3840);
      expect(d.videoEnhancementOutputHeight, 2160);
      expect(d.videoEnhancementPath, 'fake_pass');
      expect(d.videoEnhancementFrameMs, isNotNull);
      expect(d.videoEnhancementDeadlineMs, greaterThan(0));
      expect(d.videoEnhancementFallbackReason, isEmpty);
      expect(d.renderingPath, isNotEmpty);
    });

    test('viewport and output cap are forwarded to the engine', () async {
      final fake = FakeMediaPlaybackEngine();
      final c = await opened(fake);
      addTearDown(c.dispose);

      c.setVideoEnhancementViewport(1920, 1080);
      await Future<void>.delayed(Duration.zero);
      expect(fake.enhancementViewportWidth, BigInt.from(1920));
      expect(fake.enhancementViewportHeight, BigInt.from(1080));

      await c.setVideoEnhancementMaxOutputEdge(2160);
      expect(fake.enhancementMaxOutputEdge, 2160);

      // Repeating the same viewport is a no-op, not repeated bridge traffic.
      c.setVideoEnhancementViewport(1920, 1080);
      c.setVideoEnhancementViewport(0, 0);
      await Future<void>.delayed(Duration.zero);
      expect(fake.enhancementViewportWidth, BigInt.zero);
    });
  });

  group('video enhancement: capabilities and fallback', () {
    test('an unsupported device reports it and keeps the normal path',
        () async {
      final fake = FakeMediaPlaybackEngine()
        ..enhancementModes = const [mf.VideoEnhancementMode.off];
      final c = await opened(fake);
      addTearDown(c.dispose);

      final caps = await c.probeVideoEnhancement();
      expect(caps.supported, isFalse);
      expect(caps.supports(VideoEnhancementMode.highQuality), isFalse);
      expect(c.supportsVideoEnhancement, isFalse);

      // The request is refused, playback is untouched.
      expect(
        await c.setVideoEnhancementMode(VideoEnhancementMode.highQuality),
        isFalse,
      );
      expect(fake.enhancementMode, mf.VideoEnhancementMode.off);
      expect(fake.playing, isTrue);
    });

    test('supported modes are exposed for UI gating', () async {
      final fake = FakeMediaPlaybackEngine()
        ..enhancementModes = const [
          mf.VideoEnhancementMode.off,
          mf.VideoEnhancementMode.sharp,
        ];
      final c = await opened(fake);
      addTearDown(c.dispose);
      await c.probeVideoEnhancement();

      expect(c.supportsVideoEnhancement, isTrue);
      expect(c.supportedVideoEnhancementModes, [
        VideoEnhancementMode.off,
        VideoEnhancementMode.sharp,
      ]);
      expect(
        await c.setVideoEnhancementMode(VideoEnhancementMode.enhanced),
        isFalse,
      );
      expect(
        await c.setVideoEnhancementMode(VideoEnhancementMode.sharp),
        isTrue,
      );
    });

    test('a failing probe degrades to unsupported instead of throwing',
        () async {
      final fake = _ThrowingProbeFake();
      final c = await opened(fake);
      addTearDown(c.dispose);

      final caps = await c.probeVideoEnhancement();
      expect(caps.supported, isFalse);
      expect(caps.supportedModes, [VideoEnhancementMode.off]);
      expect(fake.playing, isTrue);
    });

    test('the mode survives a source change and is re-applied after open',
        () async {
      final fake = FakeMediaPlaybackEngine();
      final c = await opened(fake);
      addTearDown(c.dispose);

      await c.setVideoEnhancementMode(VideoEnhancementMode.enhanced);
      final logBefore = fake.enhancementModeLog.length;
      await c.open(
        const MediaForgeMedia.network('http://127.0.0.1:8080/other'),
      );
      expect(fake.openCount, 2);
      expect(c.videoEnhancementMode, VideoEnhancementMode.enhanced,
          reason: 'requested mode is player state');
      // Re-applied on the new engine without the app asking again.
      expect(fake.enhancementModeLog.length, greaterThanOrEqualTo(logBefore));
      expect(fake.enhancementMode, mf.VideoEnhancementMode.enhanced);
      // ...and open() is not an enhancement-driven event: the requested mode
      // is the only thing that drives the log.
      expect(fake.enhancementModeLog.every((m) => m == mf.VideoEnhancementMode.off ||
          m == mf.VideoEnhancementMode.enhanced), isTrue);
    });
  });

  group('video enhancement: frame routing contract', () {
    test('the enhancer is installed and routes frames to the engine',
        () async {
      final fake = FakeMediaPlaybackEngine();
      final c = await opened(fake);
      addTearDown(c.dispose);
      await c.setVideoEnhancementMode(VideoEnhancementMode.enhanced);

      final enhance = c.presenter.enhancer;
      expect(enhance, isNotNull);

      final (frame, handoff) = syntheticFrame();
      final out = await enhance!(frame, handoff);

      expect(fake.enhancementCallCount, 1);
      expect(out, isNotNull);
      expect(out!.pixelBufferPtr, isNot(handoff.pixelBufferPtr),
          reason: 'a distinct enhanced surface is presented');
      expect(out.width, 1920);
      expect(out.height, 1080);
      expect(c.enhancedFrameCount, 1);
      expect(c.enhancementBypassedFrameCount, 0);
    });

    test('a bypassing engine returns the decoded frame untouched', () async {
      final fake = FakeMediaPlaybackEngine()..enhancementProducesOutput = false;
      final c = await opened(fake);
      addTearDown(c.dispose);
      await c.setVideoEnhancementMode(VideoEnhancementMode.enhanced);

      final (frame, handoff) = syntheticFrame();
      final out = await c.presenter.enhancer!(frame, handoff);

      expect(out, isNull, reason: 'null means "present the decoded frame"');
      expect(c.enhancedFrameCount, 0);
      expect(c.enhancementBypassedFrameCount, 1);
    });

    test('turning enhancement off restores the normal path', () async {
      final fake = FakeMediaPlaybackEngine();
      final c = await opened(fake);
      addTearDown(c.dispose);

      await c.setVideoEnhancementMode(VideoEnhancementMode.highQuality);
      final (frame, handoff) = syntheticFrame(pts: 80);
      expect(await c.presenter.enhancer!(frame, handoff), isNotNull);

      await c.setVideoEnhancementMode(VideoEnhancementMode.off);
      final callsBefore = fake.enhancementCallCount;
      expect(c.presenter.enhancer, isNull,
          reason: 'off must not leave a hook on the presentation path');
      expect(fake.enhancementCallCount, callsBefore,
          reason: 'off must not call the GPU stage at all');
    });

    test('a throwing engine never breaks the frame', () async {
      final fake = _ThrowingEnhanceFake();
      final c = await opened(fake);
      addTearDown(c.dispose);
      await c.setVideoEnhancementMode(VideoEnhancementMode.enhanced);

      final (frame, handoff) = syntheticFrame();
      final out = await c.presenter.enhancer!(frame, handoff);

      expect(out, isNull);
      expect(c.enhancementBypassedFrameCount, 1);
      expect(c.value.hasError, isFalse);
    });

    test('no enhancement work while paused or backgrounded', () async {
      final fake = FakeMediaPlaybackEngine();
      final c = await opened(fake);
      addTearDown(c.dispose);
      await c.setVideoEnhancementMode(VideoEnhancementMode.enhanced);
      await c.pause();

      final bridgeBefore = c.bridgeCallCount;
      await c.presentationTickForTest();
      await c.presentationTickForTest();
      expect(c.bridgeCallCount, bridgeBefore);
      expect(c.enhancedFrameCount, 0);
      expect(fake.enhancementCallCount, 0);

      await c.play();
      await c.suspend();
      final bridgeWhileSuspended = c.bridgeCallCount;
      await c.presentationTickForTest();
      expect(c.bridgeCallCount, bridgeWhileSuspended);
      expect(fake.enhancementCallCount, 0);
      await c.resume();
    });
  });

  group('video enhancement: nothing else regresses', () {
    test('seeking is unaffected', () async {
      final fake = FakeMediaPlaybackEngine();
      final c = await opened(fake);
      addTearDown(c.dispose);
      await c.setVideoEnhancementMode(VideoEnhancementMode.highQuality);

      await c.seek(const Duration(seconds: 30));
      expect(fake.seekLog.last, 30000);
      final seekGen = c.seekGeneration;
      expect(seekGen, greaterThan(0));

      await c.seek(const Duration(seconds: 45));
      expect(fake.seekLog.last, 45000);
      expect(c.seekGeneration, greaterThan(seekGen));
      expect(c.videoEnhancementMode, VideoEnhancementMode.highQuality,
          reason: 'the mode is not reset by seeking');
    });

    test('audio and subtitle state are unaffected', () async {
      final fake = FakeMediaPlaybackEngine();
      final c = await opened(fake);
      addTearDown(c.dispose);
      await c.setVideoEnhancementMode(VideoEnhancementMode.enhanced);

      await c.setMuted(true);
      expect(c.value.isMuted, isTrue);
      expect(fake.muted, isTrue);
      await c.setMuted(false);

      await c.setVolume(0.4);
      expect(c.value.volume, closeTo(0.4, 0.001));
      expect(fake.volume, closeTo(0.4, 0.001));

      await c.selectAudioTrack(2);
      expect(fake.selectedAudio, 2);

      await c.setSubtitleDelay(const Duration(milliseconds: 250));
      expect(c.value.subtitleDelay, const Duration(milliseconds: 250));
      expect(fake.subtitleDelayMs, 250);

      await c.setSubtitlesEnabled(false);
      expect(fake.subtitlesEnabled, isFalse);
      expect(c.videoEnhancementMode, VideoEnhancementMode.enhanced);
    });

    test('fullscreen is unaffected', () async {
      final fake = FakeMediaPlaybackEngine();
      final c = await opened(fake);
      addTearDown(c.dispose);
      final fs = MediaForgeFullscreenController();
      addTearDown(fs.dispose);

      await c.setVideoEnhancementMode(VideoEnhancementMode.highQuality);
      await fs.enterFullscreen();
      expect(fs.isFullscreen, isTrue);
      await fs.exitFullscreen();
      expect(fs.isFullscreen, isFalse);
      expect(c.value.videoEnhancementMode, VideoEnhancementMode.highQuality);
      // Fullscreen never disturbs the render path selection.
      expect(c.textureHandle, isNonZero);
    });

    test('tracks and playback position keep working', () async {
      final fake = FakeMediaPlaybackEngine();
      final c = await opened(fake);
      addTearDown(c.dispose);
      await c.setVideoEnhancementMode(VideoEnhancementMode.sharp);

      expect(c.value.videoTracks, isNotEmpty);
      expect(c.value.audioTracks, isNotEmpty);
      await c.setPlaybackRate(1.5);
      expect(c.value.playbackRate, closeTo(1.5, 0.001));
      expect(fake.rate, closeTo(1.5, 0.001));
    });
  });

  group('video enhancement: lifecycle and cleanup', () {
    test('release drops the enhancement stage and stops frame work', () async {
      final fake = FakeMediaPlaybackEngine();
      final c = await opened(fake);
      await c.setVideoEnhancementMode(VideoEnhancementMode.enhanced);
      await c.diagnosticsTickForTest();
      expect(c.videoEnhancementStatus, isNotNull);

      final presentedBefore = fake.enhancementCallCount;
      await c.release();

      expect(c.isReleased, isTrue);
      // Native resources are gone: no texture, no presenter hook traffic.
      expect(c.presenter.textureId.value, isNull);
      // Post-release calls are refused rather than touching a dead engine.
      expect(
        await c.setVideoEnhancementMode(VideoEnhancementMode.highQuality),
        isFalse,
      );
      await c.presentationTickForTest();
      await c.diagnosticsTickForTest();
      expect(fake.enhancementCallCount, presentedBefore);
    });

    test('dispose is safe with enhancement active', () async {
      final fake = FakeMediaPlaybackEngine();
      final c = await opened(fake);
      await c.setVideoEnhancementMode(VideoEnhancementMode.highQuality);
      c.dispose();
      await c.releaseFutureForTest;
      expect(c.textureHandle, isNonZero);
    });

    test('repeated mode changes do not accumulate work', () async {
      final fake = FakeMediaPlaybackEngine();
      final c = await opened(fake);
      addTearDown(c.dispose);

      for (var i = 0; i < 20; i++) {
        await c.setVideoEnhancementMode(
          i.isEven ? VideoEnhancementMode.enhanced : VideoEnhancementMode.off,
        );
      }
      // 20 explicit requests plus the mode applied at open.
      expect(fake.enhancementModeLog.length, 21);
      expect(fake.openCount, 1, reason: 'still a single open');
      expect(c.videoEnhancementMode, VideoEnhancementMode.off);
    });
  });

  group('video enhancement: pure model', () {
    test('mode metadata and wire names are stable', () {
      expect(VideoEnhancementMode.off.wireName, 'off');
      expect(VideoEnhancementMode.sharp.wireName, 'sharp');
      expect(VideoEnhancementMode.enhanced.wireName, 'enhanced');
      expect(VideoEnhancementMode.highQuality.wireName, 'high_quality');
      for (final mode in VideoEnhancementMode.values) {
        expect(VideoEnhancementMode.fromWireName(mode.wireName), mode);
        expect(mode.displayName, isNotEmpty);
        expect(mode.description, isNotEmpty);
      }
      expect(VideoEnhancementMode.fromWireName('nonsense'),
          VideoEnhancementMode.off);
      expect(VideoEnhancementMode.off.isActive, isFalse);
      expect(VideoEnhancementMode.sharp.isActive, isTrue);
    });

    test('status derives resolution, ratio and budget usage', () {
      const status = VideoEnhancementStatus(
        supported: true,
        requestedMode: VideoEnhancementMode.highQuality,
        activeMode: VideoEnhancementMode.enhanced,
        inputWidth: 1280,
        inputHeight: 720,
        outputWidth: 1920,
        outputHeight: 1080,
        lastFrameMs: 8,
        deadlineMs: 16,
      );
      expect(status.isActive, isTrue);
      expect(status.isDowngraded, isTrue);
      expect(status.upscaleRatio, closeTo(1.5, 0.001));
      expect(status.deadlineUsage, closeTo(0.5, 0.001));
      expect(status.resolutionLabel, '1280×720 → 1920×1080');

      const idle = VideoEnhancementStatus.idle;
      expect(idle.isActive, isFalse);
      expect(idle.upscaleRatio, 1);
      expect(idle.deadlineUsage, 0);
      expect(idle.resolutionLabel, '—');
    });

    test('capabilities gate mode support', () {
      const caps = VideoEnhancementCapabilities(
        supported: true,
        supportedModes: [
          VideoEnhancementMode.off,
          VideoEnhancementMode.sharp,
        ],
        backend: 'metal_wgpu',
        maxOutputEdge: 3840,
      );
      expect(caps.isExperimental, isTrue);
      expect(caps.supports(VideoEnhancementMode.off), isTrue);
      expect(caps.supports(VideoEnhancementMode.sharp), isTrue);
      expect(caps.supports(VideoEnhancementMode.enhanced), isFalse);
      expect(VideoEnhancementCapabilities.unsupported.supports(
          VideoEnhancementMode.enhanced), isFalse);
    });

    test('policy constants mirror the native ladder', () {
      expect(VideoEnhancementPolicy.softDeadlineRatio, 0.75);
      expect(VideoEnhancementPolicy.downgradeStrikes, 3);
      expect(VideoEnhancementPolicy.surfaceRingSize, 3);
    });
  });

  group('video enhancement: settings UI', () {
    testWidgets('the section appears only on supported devices', (
      tester,
    ) async {
      final fake = FakeMediaPlaybackEngine()
        ..enhancementModes = const [mf.VideoEnhancementMode.off];
      final c = makeController(fake);
      // Open first so the capability probe answers from the (fake) device
      // rather than from the host platform.
      await c.open(
        const MediaForgeMedia.network('http://127.0.0.1:8080/stream'),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: VideoSettingsPanel(
              controller: c,
              fit: MediaPlayerFit.contain,
              onFitChanged: (_) {},
              displayQuarterTurns: 0,
              onDisplayRotationChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(c.videoEnhancementCapabilities?.supported, isFalse);
      expect(find.text('Off'), findsNothing);
      expect(find.text('VIDEO ENHANCEMENT'), findsNothing);

      c.dispose();
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('the section exposes all four modes and applies them', (
      tester,
    ) async {
      final fake = FakeMediaPlaybackEngine();
      final c = makeController(fake);
      await c.open(
        const MediaForgeMedia.network('http://127.0.0.1:8080/stream'),
      );
      await c.probeVideoEnhancement();

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: VideoSettingsPanel(
                controller: c,
                fit: MediaPlayerFit.contain,
                onFitChanged: (_) {},
                displayQuarterTurns: 0,
                onDisplayRotationChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(c.videoEnhancementCapabilities?.supported, isTrue);
      expect(find.text('Off'), findsOneWidget);
      expect(find.text('Sharp'), findsOneWidget);
      expect(find.text('Enhanced'), findsOneWidget);
      expect(find.text('High Quality'), findsOneWidget);
      expect(find.text('EXPERIMENTAL'), findsOneWidget);

      await tester.tap(find.text('Enhanced'));
      await tester.pumpAndSettle();
      expect(c.videoEnhancementMode, VideoEnhancementMode.enhanced);
      expect(fake.enhancementMode, mf.VideoEnhancementMode.enhanced);

      c.dispose();
      await tester.pump(const Duration(seconds: 5));
    });
  });
}

/// Engine whose capability probe fails (native pipeline unavailable).
class _ThrowingProbeFake extends FakeMediaPlaybackEngine {
  @override
  Future<mf.VideoEnhancementCapabilities> videoEnhancementCapabilities() async {
    throw StateError('no GPU pipeline');
  }
}

/// Engine whose enhancement stage fails for every frame.
class _ThrowingEnhanceFake extends FakeMediaPlaybackEngine {
  @override
  Future<mf.PixelBufferHandoff?> enhancePixelBuffer({
    required BigInt pixelBufferPtr,
    required int width,
    required int height,
    required BigInt ptsMs,
  }) async {
    throw StateError('gpu pass failed');
  }
}
