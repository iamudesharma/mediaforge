import 'package:flutter/foundation.dart';

import 'network_profile.dart';

/// Decode resolution policy for [MediaForgePlayerConfiguration].
///
/// Explicit enum — native resolution is a first-class value, never a magic
/// numeric sentinel such as `0` or `-1`.
enum MediaForgeDecodeResolution {
  /// Preserve source width/height through decode and presentation.
  ///
  /// 4K sources stay 4K; no automatic downscale to 1080 and no automatic
  /// reduction under load. Fallback is by decoder/render implementation,
  /// not resolution.
  native,

  /// Cap the longest decoded edge (preview modes).
  preview480,
  preview720,
  preview1080,
  preview1440,
}

/// Byte- and duration-aware budget for a compressed packet queue.
///
/// A packet is admitted only while **both** limits hold; whichever limit is
/// reached first applies. Replaces fixed packet-count caps (e.g. 2000).
@immutable
class MediaForgePacketBudget {
  const MediaForgePacketBudget({
    required this.maxBytes,
    required this.maxDuration,
  });

  /// Video default: 16 MiB OR 5 seconds, whichever first.
  static const video = MediaForgePacketBudget(
    maxBytes: 16 * 1024 * 1024,
    maxDuration: Duration(seconds: 5),
  );

  /// Audio default: 4 MiB OR 5 seconds.
  static const audio = MediaForgePacketBudget(
    maxBytes: 4 * 1024 * 1024,
    maxDuration: Duration(seconds: 5),
  );

  /// Subtitle queues remain independently small.
  static const subtitle = MediaForgePacketBudget(
    maxBytes: 256 * 1024,
    maxDuration: Duration(seconds: 30),
  );

  final int maxBytes;
  final Duration maxDuration;

  @override
  bool operator ==(Object other) =>
      other is MediaForgePacketBudget &&
      other.maxBytes == maxBytes &&
      other.maxDuration == maxDuration;

  @override
  int get hashCode => Object.hash(maxBytes, maxDuration);

  @override
  String toString() =>
      'MediaForgePacketBudget(${maxBytes}B, ${maxDuration.inMilliseconds}ms)';
}

/// Explicit player configuration.
///
/// Additive: existing [MediaForgePlayerController] constructor behaviour is
/// preserved. When [MediaForgePlayerConfiguration] is supplied it overrides
/// the legacy `maxQueueSize` / `previewMaxEdge` fields via
/// [resolvePreviewMaxEdge] / [resolveMaxQueueSize].
@immutable
class MediaForgePlayerConfiguration {
  const MediaForgePlayerConfiguration({
    this.decodeResolution = MediaForgeDecodeResolution.preview1080,
    this.customMaxEdge,
    this.videoPacketBudget = MediaForgePacketBudget.video,
    this.audioPacketBudget = MediaForgePacketBudget.audio,
    this.subtitlePacketBudget = MediaForgePacketBudget.subtitle,
    this.decodedVideoFramesHw = 3,
    this.decodedVideoFramesSw = 2,
    this.audioFrameBudget = 8,
    this.diagnosticsCadence = const Duration(milliseconds: 500),
    this.networkProfile = const MediaForgeNetworkProfile.directHttp(),
    this.suspendInBackground = true,
    this.subtitlePollMinimumInterval = const Duration(milliseconds: 200),
  });

  /// Native-resolution preset.
  const MediaForgePlayerConfiguration.native({
    MediaForgePacketBudget videoPacketBudget = MediaForgePacketBudget.video,
    MediaForgePacketBudget audioPacketBudget = MediaForgePacketBudget.audio,
    Duration diagnosticsCadence = const Duration(milliseconds: 500),
    MediaForgeNetworkProfile networkProfile =
        const MediaForgeNetworkProfile.directHttp(),
  }) : this(
          decodeResolution: MediaForgeDecodeResolution.native,
          videoPacketBudget: videoPacketBudget,
          audioPacketBudget: audioPacketBudget,
          diagnosticsCadence: diagnosticsCadence,
          networkProfile: networkProfile,
        );

  /// The requested decode resolution policy.
  final MediaForgeDecodeResolution decodeResolution;

  /// Explicit longest-edge cap for custom preview modes. Ignored unless
  /// [decodeResolution] is a preview value and a custom edge is desired.
  /// `null` means use the enum's canonical edge.
  final int? customMaxEdge;

  /// Compressed video packet budget (16 MiB / 5 s default).
  final MediaForgePacketBudget videoPacketBudget;

  /// Compressed audio packet budget (4 MiB / 5 s default).
  final MediaForgePacketBudget audioPacketBudget;

  /// Subtitle packet budget (independently small).
  final MediaForgePacketBudget subtitlePacketBudget;

  /// Maximum retained hardware-decoded frames (~3).
  final int decodedVideoFramesHw;

  /// Maximum retained software RGBA/BGRA frames (~2).
  final int decodedVideoFramesSw;

  /// Maximum retained decoded audio frames.
  final int audioFrameBudget;

  /// How often the controller polls `getDiagnostics()`.
  final Duration diagnosticsCadence;

  /// Default network profile for opens.
  final MediaForgeNetworkProfile networkProfile;

  /// When true, background/lifecycle suspension pauses the presentation
  /// pump, diagnostics timer and subtitle wakeups (resumed on foreground).
  final bool suspendInBackground;

  /// Minimum interval between subtitle polls when cues are active.
  final Duration subtitlePollMinimumInterval;

  /// True when native source dimensions must be preserved.
  bool get isNative => decodeResolution == MediaForgeDecodeResolution.native;

  /// Canonical longest edge for preview modes.
  int get canonicalPreviewEdge => switch (decodeResolution) {
        MediaForgeDecodeResolution.native => kNativePreservationEdge,
        MediaForgeDecodeResolution.preview480 => 480,
        MediaForgeDecodeResolution.preview720 => 720,
        MediaForgeDecodeResolution.preview1080 => 1080,
        MediaForgeDecodeResolution.preview1440 => 1440,
      };

  /// Resolve the integer edge forwarded to the native engine.
  ///
  /// Native maps to an intentionally large preservation ceiling so every
  /// practical source (up to 8K) passes through unscaled. This integer is
  /// an internal transport detail — public API uses the enum, never a
  /// magic sentinel.
  int resolvePreviewMaxEdge() => customMaxEdge ?? canonicalPreviewEdge;

  /// Legacy packet-count cap derived from byte budgets (for the still
  /// count-bounded native queue). Kept bounded: video+audio budgets imply
  /// a few hundred packets at most, never 2000 unbounded.
  int resolveMaxQueueSize() {
    // Rough estimate: assume ~64 KiB average packet → 16 MiB ≈ 256 packets.
    // Clamp to a sane range so legacy consumers see a bounded value.
    final videoPackets = (videoPacketBudget.maxBytes / (64 * 1024)).ceil();
    final audioPackets = (audioPacketBudget.maxBytes / (64 * 1024)).ceil();
    return (videoPackets + audioPackets).clamp(64, 512);
  }

  MediaForgePlayerConfiguration copyWith({
    MediaForgeDecodeResolution? decodeResolution,
    int? customMaxEdge,
    MediaForgePacketBudget? videoPacketBudget,
    MediaForgePacketBudget? audioPacketBudget,
    MediaForgePacketBudget? subtitlePacketBudget,
    int? decodedVideoFramesHw,
    int? decodedVideoFramesSw,
    int? audioFrameBudget,
    Duration? diagnosticsCadence,
    MediaForgeNetworkProfile? networkProfile,
    bool? suspendInBackground,
    Duration? subtitlePollMinimumInterval,
  }) {
    return MediaForgePlayerConfiguration(
      decodeResolution: decodeResolution ?? this.decodeResolution,
      customMaxEdge: customMaxEdge ?? this.customMaxEdge,
      videoPacketBudget: videoPacketBudget ?? this.videoPacketBudget,
      audioPacketBudget: audioPacketBudget ?? this.audioPacketBudget,
      subtitlePacketBudget: subtitlePacketBudget ?? this.subtitlePacketBudget,
      decodedVideoFramesHw:
          decodedVideoFramesHw ?? this.decodedVideoFramesHw,
      decodedVideoFramesSw:
          decodedVideoFramesSw ?? this.decodedVideoFramesSw,
      audioFrameBudget: audioFrameBudget ?? this.audioFrameBudget,
      diagnosticsCadence: diagnosticsCadence ?? this.diagnosticsCadence,
      networkProfile: networkProfile ?? this.networkProfile,
      suspendInBackground: suspendInBackground ?? this.suspendInBackground,
      subtitlePollMinimumInterval:
          subtitlePollMinimumInterval ?? this.subtitlePollMinimumInterval,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MediaForgePlayerConfiguration &&
      other.decodeResolution == decodeResolution &&
      other.customMaxEdge == customMaxEdge &&
      other.videoPacketBudget == videoPacketBudget &&
      other.audioPacketBudget == audioPacketBudget &&
      other.subtitlePacketBudget == subtitlePacketBudget &&
      other.decodedVideoFramesHw == decodedVideoFramesHw &&
      other.decodedVideoFramesSw == decodedVideoFramesSw &&
      other.audioFrameBudget == audioFrameBudget &&
      other.diagnosticsCadence == diagnosticsCadence &&
      other.networkProfile == networkProfile &&
      other.suspendInBackground == suspendInBackground &&
      other.subtitlePollMinimumInterval == subtitlePollMinimumInterval;

  @override
  int get hashCode => Object.hash(
        decodeResolution,
        customMaxEdge,
        videoPacketBudget,
        audioPacketBudget,
        subtitlePacketBudget,
        decodedVideoFramesHw,
        decodedVideoFramesSw,
        audioFrameBudget,
        diagnosticsCadence,
        networkProfile,
        suspendInBackground,
        subtitlePollMinimumInterval,
      );
}

/// Internal preservation ceiling forwarded for
/// [MediaForgeDecodeResolution.native].
///
/// 8192 preserves 4K (3840×2160) and 8K sources without scaling while the
/// native engine migrates to an explicit boolean flag (no public sentinel).
const int kNativePreservationEdge = 8192;

/// Legacy default preserved for backward compatibility:
/// `previewMaxEdge == 0 → 1080`.
const int kLegacyDefaultPreviewEdge = 1080;
