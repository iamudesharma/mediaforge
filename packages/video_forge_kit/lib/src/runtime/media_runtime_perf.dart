import 'dart:async';
import 'dart:math' as math;

import 'media_runtime.dart';

/// ROADMAP perf matrix targets for Sprint V1.7.
abstract final class MediaRuntimePerfTargets {
  static const int scrubP95Ms = 300;
  static const double playbackMinFps = 24;
  static const int openDisposeCycles = 10;
  static const Duration scrubDuration = Duration(seconds: 5);
  static const Duration playbackDuration = Duration(seconds: 10);
}

/// Result of an automated I/J/K scenario run.
class MediaRuntimePerfResult {
  const MediaRuntimePerfResult({
    required this.id,
    required this.title,
    required this.passed,
    required this.elapsedMs,
    required this.summary,
    this.details = const {},
  });

  final String id;
  final String title;
  final bool passed;
  final int elapsedMs;
  final String summary;
  final Map<String, String> details;
}

/// Runs perf matrix scenarios I/J/K against an open [MediaRuntime].
abstract final class MediaRuntimePerf {
  /// **I** — Debounced scrub for [MediaRuntimePerfTargets.scrubDuration].
  static Future<MediaRuntimePerfResult> runScenarioI(
    MediaRuntime runtime, {
    Duration duration = MediaRuntimePerfTargets.scrubDuration,
    int scrubIntervalMs = 320,
  }) async {
    if (!runtime.isOpen) {
      throw StateError('MediaRuntime must be open before scenario I');
    }
    final sw = Stopwatch()..start();
    final metrics = runtime.metrics;
    final before = metrics.scrubCompleted;
    final trimStart = runtime.trimStartMs;
    final trimEnd = runtime.trimEndMs;
    final span = (trimEnd - trimStart).clamp(1, 1 << 30);

    final endAt = DateTime.now().add(duration);
    var tick = 0;
    while (DateTime.now().isBefore(endAt)) {
      final frac = (tick % 20) / 19.0;
      final targetMs = trimStart + (span * frac).round();
      runtime.scheduleScrub(Duration(milliseconds: targetMs));
      tick++;
      await Future<void>.delayed(Duration(milliseconds: scrubIntervalMs));
    }

    // Allow last debounced scrub to finish.
    await _waitForScrubIdle(runtime, timeout: const Duration(seconds: 2));

    sw.stop();
    final snap = runtime.metricsSnapshot;
    final newScrubs = snap.scrubCompleted - before;
    final p95 = snap.scrubP95Ms;
    final passed = newScrubs > 0 &&
        p95 != null &&
        p95 <= MediaRuntimePerfTargets.scrubP95Ms &&
        snap.scrubAvoidsDiskThumbnail;

    return MediaRuntimePerfResult(
      id: 'I',
      title: 'Scrub playhead ${duration.inSeconds}s',
      passed: passed,
      elapsedMs: sw.elapsedMilliseconds,
      summary: passed
          ? 'p95=${p95}ms · $newScrubs scrubs · ${snap.previewPathLabel}'
          : 'p95=${p95 ?? "—"}ms (target ≤${MediaRuntimePerfTargets.scrubP95Ms}) · path=${snap.previewPathLabel}',
      details: {
        'scrubs': '$newScrubs',
        'p95_ms': '${p95 ?? "—"}',
        'max_ms': '${snap.scrubMaxMs ?? "—"}',
        'preview_path': snap.previewPathLabel,
        'disk_jpeg_hot_path': snap.scrubAvoidsDiskThumbnail ? 'no' : 'yes',
      },
    );
  }

  /// **J** — Play [duration] within trim; sustained FPS ≥ target.
  static Future<MediaRuntimePerfResult> runScenarioJ(
    MediaRuntime runtime, {
    Duration duration = MediaRuntimePerfTargets.playbackDuration,
  }) async {
    if (!runtime.isOpen) {
      throw StateError('MediaRuntime must be open before scenario J');
    }
    final sw = Stopwatch()..start();
    final framesBefore = runtime.metrics.playbackFramesPresented;

    final endMs = math.min(
      runtime.trimStartMs + duration.inMilliseconds,
      runtime.trimEndMs,
    );
    runtime.setTrimRange(
      startMs: runtime.trimStartMs,
      endMs: endMs,
    );
    await runtime.seekTo(Duration(milliseconds: runtime.trimStartMs));
    await runtime.play();

    await Future<void>.delayed(duration);
    runtime.pause();
    await _waitForScrubIdle(runtime);

    sw.stop();
    final snap = runtime.metricsSnapshot;
    final frames = snap.playbackFramesPresented - framesBefore;
    final elapsedSec = duration.inMilliseconds / 1000.0;
    final avgFps = frames / elapsedSec;
    final sustained = snap.playbackFpsMin ?? snap.playbackFps ?? avgFps;
    final passed = sustained >= MediaRuntimePerfTargets.playbackMinFps;

    return MediaRuntimePerfResult(
      id: 'J',
      title: 'Play ${duration.inSeconds}s (trim)',
      passed: passed,
      elapsedMs: sw.elapsedMilliseconds,
      summary: passed
          ? '${sustained.toStringAsFixed(1)} fps (avg ${avgFps.toStringAsFixed(1)}) · ${snap.previewPathLabel}'
          : '${sustained.toStringAsFixed(1)} fps < ${MediaRuntimePerfTargets.playbackMinFps} target',
      details: {
        'frames': '$frames',
        'avg_fps': avgFps.toStringAsFixed(1),
        'min_fps': snap.playbackFpsMin?.toStringAsFixed(1) ?? "—",
        'max_fps': snap.playbackFpsMax?.toStringAsFixed(1) ?? "—",
        'preview_path': snap.previewPathLabel,
      },
    );
  }

  /// **K** — [cycles] open/close on the same runtime (texture pool reuse).
  static Future<MediaRuntimePerfResult> runScenarioK(
    String path, {
    int cycles = MediaRuntimePerfTargets.openDisposeCycles,
    int previewMaxEdge = 720,
  }) async {
    final sw = Stopwatch()..start();
    final runtime = MediaRuntime(
      previewMaxEdge: previewMaxEdge,
      targetPreviewFps: 30,
      loopPlayback: false,
    );

    try {
      for (var i = 0; i < cycles; i++) {
        await runtime.open(path);
        await runtime.close();
      }
    } finally {
      runtime.dispose();
    }

    sw.stop();
    final snap = runtime.metricsSnapshot;
    final passed = snap.textureLeaksOnClose == 0;

    return MediaRuntimePerfResult(
      id: 'K',
      title: 'Open/dispose ×$cycles',
      passed: passed,
      elapsedMs: sw.elapsedMilliseconds,
      summary: passed
          ? '$cycles cycles · 0 texture leaks'
          : '${snap.textureLeaksOnClose} leak(s) in $cycles cycles',
      details: {
        'cycles': '$cycles',
        'texture_leaks': '${snap.textureLeaksOnClose}',
        'last_texture_id': '${snap.lastTextureId}',
      },
    );
  }

  static Future<void> _waitForScrubIdle(
    MediaRuntime runtime, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      if (!runtime.isLoading) return;
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
  }
}
