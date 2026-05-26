import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// macOS Flutter [Texture] registration for GPU preview readback (Sprint 11b.2).
abstract final class GpuTextureRegistry {
  static const _channel = MethodChannel('rust_image/texture');

  static bool get isSupported =>
      !kIsWeb && Platform.isMacOS;

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
      // Fallback: no-op when plugin not registered.
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
