import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'preview_surface_frame.dart';

/// Flutter [Texture] registration for GPU preview frames.
abstract final class GpuTextureRegistry {
  static const channelName = 'rust_gpu_texture/texture';
  static const _channel = MethodChannel(channelName);

  static bool get isSupported =>
      !kIsWeb &&
      (Platform.isMacOS || Platform.isIOS || Platform.isAndroid);

  /// Registers a Flutter [Texture] for [handle]. Returns Flutter texture id.
  static Future<int?> createTexture({
    required int handle,
    required int width,
    required int height,
  }) async {
    if (!isSupported || width <= 0 || height <= 0) return null;
    try {
      final id = await _channel.invokeMethod<int>('createTexture', {
        'handle': handle,
        'width': width,
        'height': height,
      });
      return id;
    } on MissingPluginException {
      return null;
    }
  }

  static Future<void> notifyFrameAvailable(int handle) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('notifyFrameAvailable', {
        'handle': handle,
      });
    } on MissingPluginException {
      // no-op
    }
  }

  /// MediaCodec decode directly into the [handle] SurfaceTexture (Android only).
  ///
  /// The Flutter texture must already exist ([createTexture]). Frame is rendered before return.
  static Future<PreviewSurfaceFrame?> decodePreviewToSurface({
    required int handle,
    required String path,
    required int positionMs,
    int maxEdge = 0,
  }) async {
    if (!Platform.isAndroid || path.isEmpty) return null;
    try {
      final map = await _channel.invokeMethod<Map<Object?, Object?>>(
        'decodePreviewToSurface',
        {
          'handle': handle,
          'path': path,
          'positionMs': positionMs,
          'maxEdge': maxEdge,
        },
      );
      if (map == null) return null;
      final ptsMs = (map['ptsMs'] as num?)?.toInt();
      final width = (map['width'] as num?)?.toInt();
      final height = (map['height'] as num?)?.toInt();
      if (ptsMs == null || width == null || height == null) return null;
      if (width <= 0 || height <= 0) return null;
      return PreviewSurfaceFrame(
        ptsMs: ptsMs,
        width: width,
        height: height,
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Adopts a native `CVPixelBuffer*` ([pixelBufferPtr]) into the Flutter texture (Apple only).
  ///
  /// [pixelBufferPtr] must be +1 retained; ownership transfers to the plugin.
  static Future<void> presentPixelBuffer({
    required int handle,
    required int pixelBufferPtr,
  }) async {
    if (!isSupported || pixelBufferPtr == 0) return;
    if (!Platform.isMacOS && !Platform.isIOS) return;
    try {
      await _channel.invokeMethod<void>('presentPixelBuffer', {
        'handle': handle,
        'pixelBufferPtr': pixelBufferPtr,
      });
    } on MissingPluginException {
      // no-op
    }
  }

  /// Uploads RGBA8888 pixels (width × height × 4) for [handle].
  static Future<void> updateTexture({
    required int handle,
    required Uint8List pixels,
  }) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('updateTexture', {
        'handle': handle,
        'pixels': pixels,
      });
    } on MissingPluginException {
      // no-op
    }
  }

  static Future<void> disposeTexture(int handle) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('disposeTexture', {
        'handle': handle,
      });
    } on MissingPluginException {
      // no-op
    }
  }
}
