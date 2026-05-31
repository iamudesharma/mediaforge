import '../frb_generated/api/runtime.dart' as frb;

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

  final frb.MediaPlaybackEngine engine;
  final MediaPlaybackPresenter presenter;

  /// ~30fps path: take paced frame + GPU upload only.
  Future<PresentationTickResult> presentationTick() async {
    final pts = await presenter.presentNext(engine);
    return PresentationTickResult(presentedPtsMs: pts);
  }

  /// Single FRB bridge call — returns all diagnostics at once.
  /// Replaces 11 individual `engine.getXxx()` calls per tick.
  Future<PlaybackDiagnostics> diagnosticsTick() async {
    final snap = await engine.getDiagnostics();
    return PlaybackDiagnostics.fromFrb(snap);
  }

  /// Acceptance check for custom-file playback dashboards.
  bool isHealthyPlayback(PlaybackDiagnostics d, {required bool isPlaying}) {
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

/// Dart-side diagnostics snapshot with `int` fields.
/// Converted from the FRB-generated `BigInt`-based struct to avoid
/// naming conflicts with the FRB-exported `DiagnosticsSnapshot`.
class PlaybackDiagnostics {
  const PlaybackDiagnostics({
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

  /// Convert from FRB-generated snapshot (BigInt fields → int fields).
  factory PlaybackDiagnostics.fromFrb(frb.DiagnosticsSnapshot snap) {
    return PlaybackDiagnostics(
      state: snap.state,
      mediaTimeMs: snap.mediaTimeMs.toInt(),
      audioClockMs: snap.audioClockMs.toInt(),
      wallClockMs: snap.wallClockMs.toInt(),
      latestDecodedPtsMs: snap.latestDecodedPtsMs.toInt(),
      presentedPtsMs: snap.presentedPtsMs.toInt(),
      avDriftMs: snap.avDriftMs.toInt(),
      videoPacketsInQueue: snap.videoPacketsInQueue.toInt(),
      audioPacketsInQueue: snap.audioPacketsInQueue.toInt(),
      videoFramesInQueue: snap.videoFramesInQueue.toInt(),
      audioFramesInQueue: snap.audioFramesInQueue.toInt(),
    );
  }

  final frb.PlaybackState state;
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
