import 'package:flutter/foundation.dart';
import 'package:media_forge/media_forge.dart' as mf;

/// GPU video enhancement quality (experimental).
///
/// Enhancement runs entirely inside the native GPU stage between hardware
/// decode and presentation — never in Dart, never as a CPU FFmpeg filter. The
/// decoded frame stays on the GPU (VideoToolbox `CVPixelBuffer` → Metal
/// compute pass → presentation surface → `pixel_surface` → Flutter), so no
/// RGBA round-trip and no CPU resize/sharpen is involved.
///
/// The mode can be changed at any time, including during playback: it takes
/// effect on the next presented frame with no media reopen and no decoder
/// restart. [VideoEnhancementMode.off] is the default everywhere.
///
/// This enum is the public surface; it is deliberately independent of the
/// engine's own enum so apps only ever import `media_forge_player`.
enum VideoEnhancementMode {
  /// Untouched render path. No GPU work, no extra surface.
  off,

  /// Single-pass GPU sharpen at native size. For sources that already match
  /// the display resolution.
  sharp,

  /// High-quality GPU upscale plus adaptive sharpening and a light dither.
  enhanced,

  /// The best non-AI upscale that fits a real-time frame budget: separable
  /// Lanczos-3 plus adaptive sharpening. Most expensive.
  highQuality;

  /// Default mode for every player.
  static const VideoEnhancementMode defaultMode = VideoEnhancementMode.off;

  /// True when this mode runs a GPU pass.
  bool get isActive => this != VideoEnhancementMode.off;

  /// Short label for settings UI.
  String get displayName => switch (this) {
        VideoEnhancementMode.off => 'Off',
        VideoEnhancementMode.sharp => 'Sharp',
        VideoEnhancementMode.enhanced => 'Enhanced',
        VideoEnhancementMode.highQuality => 'High Quality',
      };

  /// One-line explanation for settings UI.
  String get description => switch (this) {
        VideoEnhancementMode.off => 'Leave the decoded image untouched',
        VideoEnhancementMode.sharp => 'Light GPU sharpening at native size',
        VideoEnhancementMode.enhanced => 'Upscale, sharpen and deband on the GPU',
        VideoEnhancementMode.highQuality =>
          'Best non-AI upscale; heaviest GPU cost',
      };

  /// Stable wire name (matches the native diagnostics string).
  String get wireName => switch (this) {
        VideoEnhancementMode.off => 'off',
        VideoEnhancementMode.sharp => 'sharp',
        VideoEnhancementMode.enhanced => 'enhanced',
        VideoEnhancementMode.highQuality => 'high_quality',
      };

  /// Map from the engine enum.
  static VideoEnhancementMode fromEngine(mf.VideoEnhancementMode mode) =>
      switch (mode) {
        mf.VideoEnhancementMode.off => VideoEnhancementMode.off,
        mf.VideoEnhancementMode.sharp => VideoEnhancementMode.sharp,
        mf.VideoEnhancementMode.enhanced => VideoEnhancementMode.enhanced,
        mf.VideoEnhancementMode.highQuality => VideoEnhancementMode.highQuality,
      };

  /// Map to the engine enum.
  mf.VideoEnhancementMode get toEngine => switch (this) {
        VideoEnhancementMode.off => mf.VideoEnhancementMode.off,
        VideoEnhancementMode.sharp => mf.VideoEnhancementMode.sharp,
        VideoEnhancementMode.enhanced => mf.VideoEnhancementMode.enhanced,
        VideoEnhancementMode.highQuality => mf.VideoEnhancementMode.highQuality,
      };

  /// Parse a stable wire name; unknown input maps to [VideoEnhancementMode.off].
  static VideoEnhancementMode fromWireName(String name) => switch (name) {
        'sharp' => VideoEnhancementMode.sharp,
        'enhanced' => VideoEnhancementMode.enhanced,
        'high_quality' => VideoEnhancementMode.highQuality,
        _ => VideoEnhancementMode.off,
      };
}

/// What this device and build can actually do.
///
/// Always safe to query: an unsupported device reports
/// [supported] `== false` and playback keeps the normal render path.
@immutable
class VideoEnhancementCapabilities {
  const VideoEnhancementCapabilities({
    required this.supported,
    required this.supportedModes,
    required this.backend,
    required this.maxOutputEdge,
    this.reason = '',
  });

  /// The conservative answer for platforms with no enhancement backend.
  static const unsupported = VideoEnhancementCapabilities(
    supported: false,
    supportedModes: [VideoEnhancementMode.off],
    backend: 'none',
    maxOutputEdge: 0,
  );

  /// True when a GPU enhancement backend is available on this device.
  final bool supported;

  /// Modes that will actually run. Always contains
  /// [VideoEnhancementMode.off].
  final List<VideoEnhancementMode> supportedModes;

  /// Backend identity, e.g. `metal_wgpu`.
  final String backend;

  /// Largest output longest edge the backend will produce.
  final int maxOutputEdge;

  /// Why enhancement is unavailable (empty when supported), or `probe_pending`
  /// before the first probe completes.
  final String reason;

  /// The feature is new and its quality/perf envelope is still being tuned.
  bool get isExperimental => true;

  /// True when the GPU probe has not run yet.
  bool get isProbePending => reason == 'probe_pending';

  bool supports(VideoEnhancementMode mode) =>
      supportedModes.contains(mode) && (!mode.isActive || supported);

  @override
  bool operator ==(Object other) =>
      other is VideoEnhancementCapabilities &&
      other.supported == supported &&
      listEquals(other.supportedModes, supportedModes) &&
      other.backend == backend &&
      other.maxOutputEdge == maxOutputEdge &&
      other.reason == reason;

  @override
  int get hashCode => Object.hash(supported, Object.hashAll(supportedModes),
      backend, maxOutputEdge, reason);

  @override
  String toString() =>
      'VideoEnhancementCapabilities(supported=$supported backend=$backend '
      'modes=$supportedModes maxEdge=$maxOutputEdge reason="$reason")';
}

/// Live enhancement state, for settings UI and support diagnostics.
@immutable
class VideoEnhancementStatus {
  const VideoEnhancementStatus({
    required this.supported,
    required this.requestedMode,
    required this.activeMode,
    this.backend = 'none',
    this.path = '',
    this.scaler = 'none',
    this.inputWidth = 0,
    this.inputHeight = 0,
    this.outputWidth = 0,
    this.outputHeight = 0,
    this.lastFrameMs = 0,
    this.averageFrameMs = 0,
    this.deadlineMs = 0,
    this.deadlineMisses = 0,
    this.hardDeadlineMisses = 0,
    this.enhancedFrames = 0,
    this.bypassedFrames = 0,
    this.failedFrames = 0,
    this.passes = 0,
    this.fallbackReason = '',
    this.bypassReason = '',
  });

  /// Nothing enhanced yet — the state before the first frame.
  static const idle = VideoEnhancementStatus(
    supported: false,
    requestedMode: VideoEnhancementMode.off,
    activeMode: VideoEnhancementMode.off,
  );

  final bool supported;

  /// What the app asked for.
  final VideoEnhancementMode requestedMode;

  /// What is actually running. Differs from [requestedMode] after an
  /// automatic quality downgrade under load.
  final VideoEnhancementMode activeMode;

  /// Backend identity, e.g. `metal_wgpu`.
  final String backend;

  /// Executed pass path, e.g. `metal_lanczos_cas`.
  final String path;

  /// `none` / `catmull_rom` / `lanczos3`.
  final String scaler;

  /// Decoder output resolution entering the enhancement stage.
  final int inputWidth;
  final int inputHeight;

  /// Resolution handed to the presentation texture.
  final int outputWidth;
  final int outputHeight;

  /// Enhancement stage time for the last frame (ms).
  final double lastFrameMs;

  /// Smoothed enhancement stage time (ms).
  final double averageFrameMs;

  /// Source frame interval the stage is measured against (ms).
  final double deadlineMs;

  /// Frames that used more than [VideoEnhancementPolicy.softDeadlineRatio] of
  /// the deadline.
  final int deadlineMisses;

  /// Frames that used the whole deadline or more.
  final int hardDeadlineMisses;

  final int enhancedFrames;
  final int bypassedFrames;
  final int failedFrames;

  /// GPU passes issued for the last frame.
  final int passes;

  /// Why enhancement fell back to a lower mode or off (empty when healthy).
  final String fallbackReason;

  /// Why the last frame skipped enhancement (empty when it was enhanced).
  final String bypassReason;

  /// True when a GPU pass is running right now.
  bool get isActive => activeMode.isActive;

  /// True when the running mode is below what was requested.
  bool get isDowngraded => activeMode != requestedMode;

  /// Output/input longest-edge ratio (1.0 when not scaling).
  double get upscaleRatio {
    final inEdge = inputWidth > inputHeight ? inputWidth : inputHeight;
    final outEdge = outputWidth > outputHeight ? outputWidth : outputHeight;
    if (inEdge <= 0) return 1;
    return outEdge / inEdge;
  }

  /// Last frame's share of the source deadline (1.0 == exactly on budget).
  double get deadlineUsage {
    if (deadlineMs <= 0) return 0;
    return lastFrameMs / deadlineMs;
  }

  /// `1920×1080 → 3840×2160`, for diagnostics rows.
  String get resolutionLabel => (inputWidth > 0 && outputWidth > 0)
      ? '${inputWidth}×$inputHeight → ${outputWidth}×$outputHeight'
      : '—';

  @override
  String toString() => 'VideoEnhancementStatus(supported=$supported '
      'requested=$requestedMode active=$activeMode backend=$backend '
      'path=$path $resolutionLabel scaler=$scaler '
      'last=${lastFrameMs.toStringAsFixed(2)}ms '
      'avg=${averageFrameMs.toStringAsFixed(2)}ms '
      'deadline=${deadlineMs.toStringAsFixed(2)}ms '
      'misses=$deadlineMisses/$hardDeadlineMisses '
      'frames=$enhancedFrames bypassed=$bypassedFrames failed=$failedFrames '
      'fallback="$fallbackReason" bypass="$bypassReason")';
}

/// Deadline-aware quality ladder knobs, mirrored from the native policy so
/// apps can reason about (and tests assert) the same numbers.
abstract final class VideoEnhancementPolicy {
  /// A frame using more than this share of the source deadline counts as a
  /// soft miss.
  static const double softDeadlineRatio = 0.75;

  /// Consecutive soft misses that trigger a downgrade.
  static const int downgradeStrikes = 3;

  /// Longest clean window required before stepping back up.
  static const Duration recoveryStable = Duration(seconds: 20);

  /// Pooled GPU surfaces kept ready (rotation depth).
  static const int surfaceRingSize = 3;
}
