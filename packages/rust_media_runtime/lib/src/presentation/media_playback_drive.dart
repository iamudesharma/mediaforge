import '../frb_generated/api/runtime.dart';

import 'media_playback_presenter.dart';

/// Thresholds aligned with Rust `presenter_runtime` / `video_decode` (acceptance).
abstract final class MediaPlaybackAcceptance {
  static const int presenterIntervalMs = 16;
  static const int catchupSkipNonKeyframeMs = 500;
  static const int catchupKeyframeOnlyMs = 1500;
  static const int hardResyncDriftMs = 2000;
  static const int healthyMaxDriftMs = 500;
  static const int minHealthyVideoQueueDepth = 1;
}

/// Lightweight helpers for splitting presentation vs diagnostics timers.
class MediaPlaybackDrive {
  const MediaPlaybackDrive({
    required this.engine,
    required this.presenter,
  });

  final MediaPlaybackEngine engine;
  final MediaPlaybackPresenter presenter;

  /// ~30fps path: take paced frame + GPU upload only.
  Future<PresentationTickResult> presentationTick() async {
    final pts = await presenter.presentNext(engine);
    return PresentationTickResult(presentedPtsMs: pts);
  }

  /// Slower path: queue depths, clocks, drift (safe for [setState]).
  Future<DiagnosticsSnapshot> diagnosticsTick() async {
    return DiagnosticsSnapshot(
      state: await engine.getPlaybackState(),
      mediaTimeMs: (await engine.getMediaTimeMs()).toInt(),
      audioClockMs: (await engine.getAudioClockMs()).toInt(),
      wallClockMs: (await engine.getWallClockMs()).toInt(),
      latestDecodedPtsMs: (await engine.getLatestDecodedVideoPtsMs()).toInt(),
      presentedPtsMs: (await engine.getLastPresentedPtsMs()).toInt(),
      avDriftMs: (await engine.getAvDriftMs()).toInt(),
      videoPacketsInQueue: (await engine.getVideoPacketQueueLen()).toInt(),
      audioPacketsInQueue: (await engine.getAudioPacketQueueLen()).toInt(),
      videoFramesInQueue: (await engine.getVideoFrameQueueLen()).toInt(),
      audioFramesInQueue: (await engine.getAudioFrameQueueLen()).toInt(),
    );
  }

  /// Acceptance check for custom-file playback dashboards.
  bool isHealthyPlayback(DiagnosticsSnapshot d, {required bool isPlaying}) {
    if (!isPlaying) return true;
    return d.avDriftMs < MediaPlaybackAcceptance.healthyMaxDriftMs &&
        d.videoFramesInQueue >= MediaPlaybackAcceptance.minHealthyVideoQueueDepth;
  }
}

class PresentationTickResult {
  const PresentationTickResult({required this.presentedPtsMs});
  final int presentedPtsMs;
  bool get hasFrame => presentedPtsMs >= 0;
}

class DiagnosticsSnapshot {
  const DiagnosticsSnapshot({
    required this.state,
    required this.mediaTimeMs,
    required this.audioClockMs,
    required this.wallClockMs,
    required this.latestDecodedPtsMs,
    required this.presentedPtsMs,
    required this.avDriftMs,
    required this.videoPacketsInQueue,
    required this.audioPacketsInQueue,
    required this.videoFramesInQueue,
    required this.audioFramesInQueue,
  });

  final PlaybackState state;
  final int mediaTimeMs;
  final int audioClockMs;
  final int wallClockMs;
  final int latestDecodedPtsMs;
  final int presentedPtsMs;
  final int avDriftMs;
  final int videoPacketsInQueue;
  final int audioPacketsInQueue;
  final int videoFramesInQueue;
  final int audioFramesInQueue;

  bool get videoStarved =>
      videoFramesInQueue == 0 && videoPacketsInQueue == 0;
}
