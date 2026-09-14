import 'package:flutter/foundation.dart';
import 'package:media_forge/media_forge.dart' show PlaybackState;

/// Extended diagnostics combining engine state with player-side counters.
///
/// Engine fields come from a single `getDiagnostics()` call; FPS / dropped
/// frames are measured on the frame-ready presentation pump in the
/// controller. All pre-existing fields are preserved verbatim for backward
/// compatibility — every §16 expansion field is optional with a default.
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
    // ---- §16 expansion (all additive, defaulted) ----
    this.firstDecodedAtMs,
    this.firstPresentedAtMs,
    this.firstFrameLatencyMs,
    this.lastSeekStartedAtMs,
    this.lastSeekSettledAtMs,
    this.lastSeekLatencyMs,
    this.lastSeekGeneration = -1,
    this.presentedFrameCount = 0,
    this.bridgeCallCount = 0,
    this.queueOverflowDrops = 0,
    this.catchupDrops = 0,
    this.decodedQueueDepth = 0,
    this.videoQueueBytes = 0,
    this.audioQueueBytes = 0,
    this.videoQueueDurationMs = 0,
    this.audioQueueDurationMs = 0,
    this.packetBufferDurationMs = 0,
    this.frameMemoryBytes = 0,
    this.reconnectCount = 0,
    this.probeDurationMs,
    this.decodeTimeMs,
    this.presentationTimeMs,
    this.renderingPath = 'unknown',
    this.nativeWidth = 0,
    this.nativeHeight = 0,
    this.presentedWidth = 0,
    this.presentedHeight = 0,
    this.retainedPixelBufferCount = 0,
    this.retainedTextureCount = 0,
    this.isSuspended = false,
    // ---- experimental GPU video enhancement ----
    this.videoEnhancementSupported = false,
    this.videoEnhancementRequested = 'off',
    this.videoEnhancementActive = 'off',
    this.videoEnhancementBackend = 'none',
    this.videoEnhancementPath = '',
    this.videoEnhancementInputWidth = 0,
    this.videoEnhancementInputHeight = 0,
    this.videoEnhancementOutputWidth = 0,
    this.videoEnhancementOutputHeight = 0,
    this.videoEnhancementFrameMs,
    this.videoEnhancementAverageMs,
    this.videoEnhancementDeadlineMs,
    this.videoEnhancementDeadlineMisses = 0,
    this.videoEnhancementFallbackReason = '',
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

  /// Frames actually presented per second on the frame-ready pump.
  final double presentedFps;

  /// Legacy total drops (kept for backward compat).
  ///
  /// Prefer the split counters below: an empty frame poll is never counted
  /// here — only actual discards (queue overflow / catch-up / decoder).
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

  // ---- §16 expansion ----

  /// Wall-clock time of the first decoded frame since open (ms epoch).
  final int? firstDecodedAtMs;

  /// Wall-clock time of the first presented frame since open (ms epoch).
  final int? firstPresentedAtMs;

  /// `firstPresented - openStarted` latency (ms).
  final int? firstFrameLatencyMs;

  final int? lastSeekStartedAtMs;
  final int? lastSeekSettledAtMs;

  /// `seekSettled - seekStarted` for the latest settled generation.
  final int? lastSeekLatencyMs;

  /// Monotonic generation of the latest settled seek (-1 = none).
  final int lastSeekGeneration;

  /// Actual presented frames since open (never bridge-call count).
  final int presentedFrameCount;

  /// Flutter/native bridge presentation calls since open.
  final int bridgeCallCount;

  /// Frames discarded because a queue overflowed.
  final int queueOverflowDrops;

  /// Frames discarded by catch-up policy (deadline miss / skip-non-key).
  final int catchupDrops;

  /// Decoded queue depth (video+audio frames waiting for presentation).
  final int decodedQueueDepth;

  /// Estimated compressed video packet bytes currently buffered.
  final int videoQueueBytes;

  /// Estimated compressed audio packet bytes currently buffered.
  final int audioQueueBytes;

  /// Buffered compressed video duration (ms).
  final int videoQueueDurationMs;

  /// Buffered compressed audio duration (ms).
  final int audioQueueDurationMs;

  /// Total packet-buffer duration (ms) — max(video,audio) estimate.
  final int packetBufferDurationMs;

  /// Estimated retained decoded-frame memory (bytes).
  final int frameMemoryBytes;

  /// Network reconnects since open.
  final int reconnectCount;

  /// Initial probe duration (ms) when measured (fast + fallback).
  final int? probeDurationMs;

  /// Last decode batch time (ms, when measured).
  final double? decodeTimeMs;

  /// Last presentation time (ms, when measured).
  final double? presentationTimeMs;

  /// Exact active rendering path, e.g. `videotoolbox_iosurface_zero_copy`,
  /// `videotoolbox_bgra_copy`, `software_bgra_upload`,
  /// `software_rgba_upload`, `cpu_fallback`, `android_surface_zero_copy`
  /// (only when verified), `android_bitmap_upload`.
  final String renderingPath;

  /// Native decoded dimensions reported by the engine/container.
  final int nativeWidth;
  final int nativeHeight;

  /// Actually presented dimensions.
  final int presentedWidth;
  final int presentedHeight;

  /// Retained native pixel-buffer references (must return to 0 on release).
  final int retainedPixelBufferCount;

  /// Retained Flutter textures (must return to 0 on release).
  final int retainedTextureCount;

  final bool isSuspended;

  // ---- experimental GPU video enhancement ----

  /// True when this device can run GPU enhancement at all.
  final bool videoEnhancementSupported;

  /// Mode the app requested (`off` / `sharp` / `enhanced` / `high_quality`).
  final String videoEnhancementRequested;

  /// Mode actually running; lags the request after an automatic downgrade.
  final String videoEnhancementActive;

  /// Backend identity, e.g. `metal_wgpu`.
  final String videoEnhancementBackend;

  /// Executed pass path, e.g. `metal_lanczos_cas`.
  final String videoEnhancementPath;

  /// Decoder resolution entering the enhancement stage.
  final int videoEnhancementInputWidth;
  final int videoEnhancementInputHeight;

  /// Resolution handed to the presentation texture.
  final int videoEnhancementOutputWidth;
  final int videoEnhancementOutputHeight;

  /// Enhancement stage time for the last frame (ms), when measured.
  final double? videoEnhancementFrameMs;

  /// Smoothed enhancement stage time (ms).
  final double? videoEnhancementAverageMs;

  /// Source frame interval the stage is measured against (ms).
  final double? videoEnhancementDeadlineMs;

  /// Frames that used more than 75% of the source deadline.
  final int videoEnhancementDeadlineMisses;

  /// Why enhancement is not running at the requested level (empty when fine).
  final String videoEnhancementFallbackReason;

  /// Total decoder queue depth (packets + frames, video + audio).
  int get decoderQueueDepth =>
      videoPacketsInQueue +
      audioPacketsInQueue +
      videoFramesInQueue +
      audioFramesInQueue;

  /// Bridge overhead: calls beyond actual presented frames.
  int get bridgeOverhead => (bridgeCallCount - presentedFrameCount).clamp(
        0,
        1 << 31,
      );

  @override
  String toString() =>
      'MediaForgeDiagnostics(state=$state media=${mediaTimeMs}ms '
      'audio=${audioClockMs}ms drift=${avDriftMs}ms '
      'decFps=${decodedFps.toStringAsFixed(1)} '
      'presFps=${presentedFps.toStringAsFixed(1)} dropped=$droppedFrames '
      '(overflow=$queueOverflowDrops catchup=$catchupDrops dec=$decoderDroppedFrames) '
      'presented=$presentedFrameCount bridge=$bridgeCallCount '
      'q=$decoderQueueDepth qBytes=v$videoQueueBytes/a$audioQueueBytes '
      'frameMem=${frameMemoryBytes}B buf=${bufferedDurationMs}ms decoder=$activeDecoder '
      'hw=$hwDecode path=$renderingPath native=${nativeWidth}x$nativeHeight)';
}
