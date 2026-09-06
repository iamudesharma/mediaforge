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
    this.bytesRead = 0,
    this.readBitrateBps = 0,
    this.decoderDroppedFrames = 0,
    this.subtitleCuesPending = 0,
    this.selectedVideoIndex = -1,
    this.selectedAudioIndex = -1,
    this.selectedSubtitleIndex = -1,
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

  /// Container bytes demuxed since open (engine reporting).
  final int? networkBytesRead;

  /// Same counter as [networkBytesRead], non-nullable engine field.
  final int bytesRead;

  /// Demuxed-bytes read bitrate estimate (bits/s).
  final int readBitrateBps;

  /// Pre-decode video drops reported by the engine (stale + catch-up).
  final int decoderDroppedFrames;

  /// Cues currently held for polling.
  final int subtitleCuesPending;

  /// Selected stream indices (−1 = none/off).
  final int selectedVideoIndex;
  final int selectedAudioIndex;
  final int selectedSubtitleIndex;

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
