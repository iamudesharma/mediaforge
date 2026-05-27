import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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
