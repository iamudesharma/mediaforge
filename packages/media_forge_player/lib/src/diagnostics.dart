import 'package:flutter/foundation.dart';
import 'package:media_forge/media_forge.dart' show PlaybackState;

/// Extended diagnostics combining engine state with player-side counters.
///
/// Engine fields come from a single `getDiagnostics()` call; FPS / dropped
/// frames are measured on the presentation (vsync) loop in the controller.
@immutable
class MediaForgeDiagnostics {
  const MediaForgeDiagnostics({
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
    this.decodedFps = 0,
    this.presentedFps = 0,
    this.droppedFrames = 0,
    this.bufferedDurationMs = 0,
    this.activeDecoder = 'unknown',
    this.hwDecode = false,
    this.networkBytesRead,
  });

  final PlaybackState state;
  final int mediaTimeMs;
  final int audioClockMs;
  final int wallClockMs;
  final int latestDecodedPtsMs;
  final int presentedPtsMs;

  /// `audioClock - presentedPts` (ms). Large values mean video is behind.
  final int avDriftMs;
  final int videoPacketsInQueue;
  final int audioPacketsInQueue;
  final int videoFramesInQueue;
  final int audioFramesInQueue;

  /// Decode-side throughput measured from `latestDecodedPtsMs` changes.
  final double decodedFps;

  /// Frames actually presented per second on the vsync loop.
  final double presentedFps;

  /// Frames skipped because no new decoder frame was ready while playing.
  final int droppedFrames;

  /// Forward-buffer estimate (ms) derived from queue depths.
  final int bufferedDurationMs;

  /// e.g. `h264_videotoolbox`, `hevc_software`, `vp9_software`.
  final String activeDecoder;
  final bool hwDecode;

  /// Reserved for the future `open_url` engine path that reports socket
  /// bytes (FFmpeg `avio_size` / interrupt stats). `null` until wired.
  final int? networkBytesRead;

  /// Total decoder queue depth (packets + frames, video + audio).
  int get decoderQueueDepth =>
      videoPacketsInQueue +
      audioPacketsInQueue +
      videoFramesInQueue +
      audioFramesInQueue;

  @override
  String toString() =>
      'MediaForgeDiagnostics(state=$state media=${mediaTimeMs}ms '
      'audio=${audioClockMs}ms drift=${avDriftMs}ms '
      'decFps=${decodedFps.toStringAsFixed(1)} '
      'presFps=${presentedFps.toStringAsFixed(1)} dropped=$droppedFrames '
      'q=$decoderQueueDepth buf=${bufferedDurationMs}ms decoder=$activeDecoder '
      'hw=$hwDecode)';
}
