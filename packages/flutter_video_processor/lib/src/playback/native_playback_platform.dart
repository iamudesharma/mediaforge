import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

/// Human-readable native engine name for preview HUD / status lines.
String nativePlaybackEngineLabel() {
  if (kIsWeb) return 'video_player';
  if (Platform.isIOS || Platform.isMacOS) return 'AVPlayer';
  if (Platform.isAndroid) return 'ExoPlayer';
  return 'video_player';
}

/// Short path label for metrics (Apple texture vs Android surface vs CPU RGBA).
String texturePreviewPathLabel({required bool useSurfaceTexture}) {
  if (kIsWeb) return 'texture';
  if (Platform.isAndroid && useSurfaceTexture) return 'texture_surface';
  if (Platform.isIOS || Platform.isMacOS) return 'texture_pixel_buffer';
  return 'texture_rgba';
}
