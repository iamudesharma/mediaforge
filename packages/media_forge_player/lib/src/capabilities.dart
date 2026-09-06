import 'package:flutter/foundation.dart';
import 'package:media_forge/media_forge.dart'
    show DecodeCapabilities, probeDecodeCapabilities;

/// HW decode capability probing with automatic software fallback.
///
/// Probes once and caches; honours the same kill-switches as the engine:
/// `VFP_DISABLE_HW_DECODE=1` and `MEDIA_DISABLE_VT_ZERO_COPY=1`.
class MediaForgeCapabilities {
  MediaForgeCapabilities._(this.raw);

  final DecodeCapabilities raw;

  static MediaForgeCapabilities? _cached;

  /// Probe (cached). Logs once with tag `[MediaForgePlayer]`.
  static Future<MediaForgeCapabilities> probe({bool refresh = false}) async {
    final cached = _cached;
    if (cached != null && !refresh) return cached;
    final caps = await probeDecodeCapabilities();
    debugPrint(
      '[MediaForgePlayer] capabilities ffmpeg=${caps.ffmpegVersion} '
      'h264_vt=${caps.h264Videotoolbox} hevc_vt=${caps.hevcVideotoolbox} '
      'readyHevcHw=${caps.readyForHevcHw} hwDisabled=${caps.hwDecodeDisabledEnv} '
      'hint=${caps.hint}',
    );
    return _cached = MediaForgeCapabilities._(caps);
  }

  bool get hwDecodeAvailable =>
      !raw.hwDecodeDisabledEnv &&
      (raw.h264Videotoolbox || raw.hevcVideotoolbox);

  /// Best-guess decoder label for diagnostics until the engine reports
  /// per-stream decoder names.
  String decoderLabelFor({String? codec}) {
    final c = (codec ?? '').toLowerCase();
    final hw = hwDecodeAvailable;
    if (c.contains('hevc') || c.contains('h265') || c.contains('hvc')) {
      if (raw.hevcVideotoolbox && !raw.hwDecodeDisabledEnv) {
        return 'hevc_videotoolbox';
      }
      return 'hevc_software';
    }
    if (c.contains('avc') || c.contains('h264')) {
      if (raw.h264Videotoolbox && !raw.hwDecodeDisabledEnv) {
        return 'h264_videotoolbox';
      }
      return 'h264_software';
    }
    if (c.contains('av1')) return hw ? 'av1_hw_or_sw' : 'av1_software';
    if (c.contains('vp9')) return 'vp9_software';
    return hw ? 'unknown_hw' : 'unknown_sw';
  }

  /// Engine constructor flags for future zero-copy toggles.
  static bool get zeroCopyDisabled {
    // Mirrors Rust `MEDIA_DISABLE_VT_ZERO_COPY`.
    const env = String.fromEnvironment('MEDIA_DISABLE_VT_ZERO_COPY');
    return env == '1';
  }
}

/// Visible for tests: reset the cached probe result.
@visibleForTesting
void resetCapabilitiesCacheForTest() {
  MediaForgeCapabilities._cached = null;
}
