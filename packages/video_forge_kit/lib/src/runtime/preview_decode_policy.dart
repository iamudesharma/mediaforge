import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:video_forge/video_forge.dart';

/// How preview frames reach the Flutter texture (chosen once per asset).
enum PreviewDecodePath {
  /// Try Apple HW pixel-buffer once, then lock to [swRgba] if it fails.
  auto,

  /// VideoToolbox → CVPixelBuffer (H.264 and similar on Apple).
  hwPixelBuffer,

  /// Persistent session → RGBA upload (HEVC / Dolby Vision / after HW failure).
  swRgba,
}

/// Decides preview decode path from probe + platform (matches Rust `prefer_software_preview`).
final class PreviewDecodePolicy {
  PreviewDecodePolicy._(
    this.decodePath,
    this._mediaInfo,
    this._hwPreviewDisabled,
  );

  final MediaInfo _mediaInfo;
  final bool _hwPreviewDisabled;

  PreviewDecodePath decodePath;

  static PreviewDecodePolicy fromProbe({
    required MediaInfo mediaInfo,
    required bool hwPreviewDisabled,
  }) =>
      PreviewDecodePolicy._(
        _initialPath(mediaInfo, hwPreviewDisabled),
        mediaInfo,
        hwPreviewDisabled,
      );

  static PreviewDecodePath _initialPath(
    MediaInfo info,
    bool hwDisabled,
  ) {
    if (hwDisabled || info.preferSoftwarePreview || info.hasDolbyVision) {
      return PreviewDecodePath.swRgba;
    }
    if (!kIsWeb &&
        (Platform.isMacOS || Platform.isIOS) &&
        !info.videoCodec.toLowerCase().contains('hevc')) {
      return PreviewDecodePath.auto;
    }
    return PreviewDecodePath.swRgba;
  }

  bool get useHwPixelBuffer =>
      !kIsWeb &&
      (Platform.isMacOS || Platform.isIOS) &&
      !_hwPreviewDisabled &&
      (decodePath == PreviewDecodePath.auto ||
          decodePath == PreviewDecodePath.hwPixelBuffer);

  bool get useSoftwareRgba =>
      decodePath == PreviewDecodePath.swRgba ||
      _mediaInfo.preferSoftwarePreview ||
      _mediaInfo.hasDolbyVision;

  /// After a failed HW seek/decode, never call VT again for this asset.
  void lockSoftwareRgba() {
    if (decodePath != PreviewDecodePath.swRgba) {
      decodePath = PreviewDecodePath.swRgba;
    }
  }

  /// True for errors that mean "call RGBA instead" (not user-visible failures).
  static bool isRgbaRedirectError(Object error) {
    final msg = error.toString();
    return msg.contains('PREVIEW_RGBA_ONLY') ||
        msg.contains('software decoder ready') ||
        msg.contains('pixel-buffer preview requires VideoToolbox');
  }
}
