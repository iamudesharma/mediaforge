/// V1.7 — observability for [MediaRuntime] (scrub latency, playback FPS, texture lifecycle).
library;

/// How the last preview frame reached the UI (no disk JPEG on scrub hot path).
enum PreviewDeliveryPath {
  none,
  /// Android MediaCodec rendered into pool [SurfaceTexture].
  textureSurface,
  /// RGBA uploaded via [GpuTextureRegistry.updateTexture].
  textureRgba,
  /// Apple CVPixelBuffer presented to texture.
  texturePixelBuffer,
  /// CPU RGBA only (no texture id).
  rgbaOnly,
}

/// Rolling stats updated by [MediaRuntime] during scrub, play, and open/close.
class MediaRuntimeMetrics {
  MediaRuntimeMetrics();

  int scrubCompleted = 0;
  final List<int> scrubLatenciesMs = <int>[];
  int? lastScrubLatencyMs;
  int maxScrubLatencyMs = 0;

  int playbackFramesPresented = 0;
  double? lastPlaybackFps;
  double? minPlaybackFps;
  double? maxPlaybackFps;

  int openCloseCycles = 0;
  int textureLeaksOnClose = 0;

  PreviewDeliveryPath lastPreviewPath = PreviewDeliveryPath.none;
  int lastTextureId = 0;

  void reset() {
    scrubCompleted = 0;
    scrubLatenciesMs.clear();
    lastScrubLatencyMs = null;
    maxScrubLatencyMs = 0;
    playbackFramesPresented = 0;
    lastPlaybackFps = null;
    minPlaybackFps = null;
    maxPlaybackFps = null;
    openCloseCycles = 0;
    textureLeaksOnClose = 0;
    lastPreviewPath = PreviewDeliveryPath.none;
    lastTextureId = 0;
  }

  void recordScrubComplete(int latencyMs) {
    scrubCompleted++;
    scrubLatenciesMs.add(latencyMs);
    lastScrubLatencyMs = latencyMs;
    if (latencyMs > maxScrubLatencyMs) {
      maxScrubLatencyMs = latencyMs;
    }
  }

  void recordPlaybackFrame() {
    playbackFramesPresented++;
  }

  void recordPlaybackFpsSample(double fps) {
    lastPlaybackFps = fps;
    minPlaybackFps = minPlaybackFps == null
        ? fps
        : (fps < minPlaybackFps! ? fps : minPlaybackFps);
    maxPlaybackFps = maxPlaybackFps == null
        ? fps
        : (fps > maxPlaybackFps! ? fps : maxPlaybackFps);
  }

  void recordPreviewPath(PreviewDeliveryPath path, {int? textureId}) {
    lastPreviewPath = path;
    if (textureId != null) {
      lastTextureId = textureId;
    }
  }

  void recordOpenCloseCycle({required bool textureReleased}) {
    openCloseCycles++;
    if (!textureReleased) {
      textureLeaksOnClose++;
    }
  }

  /// Immutable snapshot for UI / perf matrix export.
  MediaRuntimeMetricsSnapshot snapshot() {
    return MediaRuntimeMetricsSnapshot(
      scrubCompleted: scrubCompleted,
      scrubP95Ms: percentileMs(scrubLatenciesMs, 0.95),
      scrubMaxMs: scrubLatenciesMs.isEmpty ? null : maxScrubLatencyMs,
      scrubLastMs: lastScrubLatencyMs,
      playbackFramesPresented: playbackFramesPresented,
      playbackFps: lastPlaybackFps,
      playbackFpsMin: minPlaybackFps,
      playbackFpsMax: maxPlaybackFps,
      openCloseCycles: openCloseCycles,
      textureLeaksOnClose: textureLeaksOnClose,
      previewPath: lastPreviewPath,
      lastTextureId: lastTextureId,
    );
  }

  /// Nearest-rank percentile on sorted copy; returns null when empty.
  static int? percentileMs(List<int> samples, double p) {
    if (samples.isEmpty) return null;
    final sorted = List<int>.from(samples)..sort();
    final rank = ((sorted.length - 1) * p).round().clamp(0, sorted.length - 1);
    return sorted[rank];
  }
}

/// Point-in-time metrics for status lines and Markdown export.
class MediaRuntimeMetricsSnapshot {
  const MediaRuntimeMetricsSnapshot({
    required this.scrubCompleted,
    required this.scrubP95Ms,
    required this.scrubMaxMs,
    required this.scrubLastMs,
    required this.playbackFramesPresented,
    required this.playbackFps,
    required this.playbackFpsMin,
    required this.playbackFpsMax,
    required this.openCloseCycles,
    required this.textureLeaksOnClose,
    required this.previewPath,
    required this.lastTextureId,
  });

  final int scrubCompleted;
  final int? scrubP95Ms;
  final int? scrubMaxMs;
  final int? scrubLastMs;
  final int playbackFramesPresented;
  final double? playbackFps;
  final double? playbackFpsMin;
  final double? playbackFpsMax;
  final int openCloseCycles;
  final int textureLeaksOnClose;
  final PreviewDeliveryPath previewPath;
  final int lastTextureId;

  String get previewPathLabel => switch (previewPath) {
        PreviewDeliveryPath.none => 'none',
        PreviewDeliveryPath.textureSurface => 'texture_surface',
        PreviewDeliveryPath.textureRgba => 'texture_rgba',
        PreviewDeliveryPath.texturePixelBuffer => 'texture_pixel_buffer',
        PreviewDeliveryPath.rgbaOnly => 'rgba_only',
      };

  /// Hot scrub path must not use disk thumbnail JPEG.
  bool get scrubAvoidsDiskThumbnail =>
      previewPath == PreviewDeliveryPath.textureSurface ||
      previewPath == PreviewDeliveryPath.textureRgba ||
      previewPath == PreviewDeliveryPath.texturePixelBuffer ||
      previewPath == PreviewDeliveryPath.rgbaOnly;

  String toStatusLine() {
    final scrub = scrubP95Ms != null
        ? 'scrub_p95=${scrubP95Ms}ms max=$scrubMaxMs'
        : 'scrub=—';
    final fps = playbackFps != null
        ? 'fps=${playbackFps!.toStringAsFixed(1)}'
        : 'fps=—';
    return '$scrub · $fps · path=$previewPathLabel · tex=$lastTextureId · leaks=$textureLeaksOnClose';
  }
}
