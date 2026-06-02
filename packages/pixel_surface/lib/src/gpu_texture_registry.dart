import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'preview_surface_frame.dart';

/// Pixel byte order accepted by [GpuTextureRegistry] upload methods.
///
/// The native display texture is always 4-channel 8-bit (BGRA on Apple,
/// RGBA on Android), but callers can upload either layout and the platform
/// plugin handles the channel order. New code should prefer the most
/// efficient path for the target platform — see [updateTextureRgba] and
/// [updateTextureBgra].
enum PixelLayout {
  /// Packed RGBA8888 (`R`, `G`, `B`, `A` per pixel).
  rgba8888,

  /// Packed BGRA8888 (`B`, `G`, `R`, `A` per pixel). This is the natural
  /// byte order of [CVPixelBuffer] on Apple and avoids any CPU channel swap
  /// on upload. On Android the platform plugin will copy directly to the
  /// backing `Bitmap`.
  bgra8888,
}

/// Flutter [Texture] registration for GPU preview frames.
abstract final class GpuTextureRegistry {
  static const channelName = 'pixel_surface/texture';
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
  ///
  /// On Apple, the plugin will swizzle RGBA → BGRA into the underlying
  /// `CVPixelBuffer`. Prefer [updateTextureBgra] on Apple to skip the
  /// swizzle entirely when the producer (e.g. a wgpu readback) already
  /// emits BGRA bytes.
  static Future<void> updateTextureRgba({
    required int handle,
    required Uint8List pixels,
  }) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('updateTexture', {
        'handle': handle,
        'pixels': pixels,
        'layout': PixelLayout.rgba8888.name,
      });
    } on MissingPluginException {
      // no-op
    }
  }

  /// Uploads BGRA8888 pixels (width × height × 4) for [handle].
  ///
  /// On Apple this is the natural byte order of a `CVPixelBuffer` and the
  /// plugin performs a row-wise `memcpy` — no channel swap. On Android
  /// the platform plugin copies directly into the backing `Bitmap` and
  /// the bytes are read as little-endian BGRA.
  ///
  /// This is the preferred upload path for any producer that emits BGRA
  /// directly (wgpu readback, VideoToolbox CVPixelBuffer conversions, etc.).
  static Future<void> updateTextureBgra({
    required int handle,
    required Uint8List pixels,
  }) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('updateTexture', {
        'handle': handle,
        'pixels': pixels,
        'layout': PixelLayout.bgra8888.name,
      });
    } on MissingPluginException {
      // no-op
    }
  }

  /// Back-compat alias for [updateTextureRgba] — kept for downstream
  /// callers that import this method under its pre-1.1.0 name.
  static Future<void> updateTexture({
    required int handle,
    required Uint8List pixels,
  }) =>
      updateTextureRgba(handle: handle, pixels: pixels);

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

  /// Returns the raw `MTLTexture*` (as `int` bit-cast) and `CVPixelBuffer*`
  /// (as `int` bit-cast) for the Flutter display texture associated with
  /// [handle]. Rust adopts these into a `wgpu::Texture` for zero-copy
  /// beauty compute writes; on other platforms returns `null`.
  static Future<({int metalTexturePtr, int pixelBufferPtr})?>
      getMetalTexturePtrForBeauty({required int handle}) async {
    if (!isSupported) return null;
    try {
      final map = await _channel.invokeMapMethod<Object?, Object?>(
        'getMetalTexturePtr',
        {'handle': handle},
      );
      if (map == null) return null;
      final mtl = map['metalTexturePtr'];
      final pb = map['pixelBufferPtr'];
      if (mtl is! int || pb is! int) return null;
      if (mtl == 0 || pb == 0) return null;
      return (metalTexturePtr: mtl, pixelBufferPtr: pb);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Resize an existing texture in place. On Apple the plugin flushes the
  /// non-reusable buffers of the existing pool and dequeue a new one for
  /// the new dimensions; on Android the `SurfaceProducer` is resized via
  /// `setSize` and the backing bitmap is re-created lazily. No-op on
  /// platforms without a plugin implementation.
  static Future<void> resizeTexture({
    required int handle,
    required int width,
    required int height,
  }) async {
    if (!isSupported || width <= 0 || height <= 0) return;
    try {
      await _channel.invokeMethod<void>('resizeTexture', {
        'handle': handle,
        'width': width,
        'height': height,
      });
    } on MissingPluginException {
      // no-op
    }
  }

  /// Ask the native plugin to drop its GPU-side backlog. On Apple this
  /// flushes the `CVPixelBufferPool` backlog and the `CVMetalTextureCache`.
  /// On Android this recycles every backing bitmap; the next frame
  /// re-allocates lazily. Safe to call from a "release memory" debug
  /// action or in response to a Dart-level signal.
  static Future<void> flushPools() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('flushPools');
    } on MissingPluginException {
      // no-op
    }
  }

  /// Read-only snapshot of the native plugin's pool/memory state. Useful
  /// for diagnostic overlays and unit tests that need to assert that a
  /// memory-pressure handler actually fired. Returns `null` on platforms
  /// without a plugin implementation.
  static Future<PixelSurfaceStats?> debugStats() async {
    if (!isSupported) return null;
    try {
      final map = await _channel.invokeMapMethod<Object?, Object?>(
        'debugStats',
      );
      if (map == null) return null;
      return PixelSurfaceStats.fromMap(map);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}

/// Read-only snapshot of native plugin stats. Constructed by
/// [GpuTextureRegistry.debugStats] from a platform-channel map.
@immutable
class PixelSurfaceStats {
  const PixelSurfaceStats({
    required this.handleCount,
    required this.poolCount,
    required this.createCount,
    required this.lastFlushMs,
    required this.lastMemoryWarningMs,
    required this.trimEventCount,
    required this.recycledBitmapCount,
    required this.lastTrimLevel,
  });

  /// Live Flutter texture handles.
  final int handleCount;

  /// Number of `CVPixelBufferPool` buckets currently in use (Apple).
  final int poolCount;

  /// Total `CVPixelBufferPoolCreatePixelBuffer` calls served (Apple).
  /// Note that the standard `CVPixelBufferPool` may internally reuse
  /// memory across calls — this is the *call count*, not the
  /// *fresh allocation count*.
  final int createCount;

  /// `CFAbsoluteTimeGetCurrent()` of the last `pool.flushAll()` (Apple).
  final double lastFlushMs;

  /// `CFAbsoluteTimeGetCurrent()` of the last memory/thermal warning
  /// handled by the plugin (Apple).
  final double lastMemoryWarningMs;

  /// Cumulative `ComponentCallbacks2.onTrimMemory` events received (Android).
  final int trimEventCount;

  /// Cumulative backing-bitmap recycles (Android).
  final int recycledBitmapCount;

  /// Level code of the most recent `onTrimMemory` event (Android). -1 if
  /// the plugin has not seen any trim event yet.
  final int lastTrimLevel;

  static const empty = PixelSurfaceStats(
    handleCount: 0,
    poolCount: 0,
    createCount: 0,
    lastFlushMs: 0,
    lastMemoryWarningMs: 0,
    trimEventCount: 0,
    recycledBitmapCount: 0,
    lastTrimLevel: -1,
  );

  factory PixelSurfaceStats.fromMap(Map<Object?, Object?> map) {
    int intAt(Object? key, [int fallback = 0]) {
      final raw = map[key];
      if (raw is num) return raw.toInt();
      if (raw is String) return int.tryParse(raw) ?? fallback;
      return fallback;
    }

    double doubleAt(Object? key, [double fallback = 0]) {
      final raw = map[key];
      if (raw is num) return raw.toDouble();
      if (raw is String) return double.tryParse(raw) ?? fallback;
      return fallback;
    }

    return PixelSurfaceStats(
      handleCount: intAt('handleCount'),
      poolCount: intAt('poolCount'),
      createCount: intAt('createCount'),
      lastFlushMs: doubleAt('lastFlushMs'),
      lastMemoryWarningMs: doubleAt('lastMemoryWarningMs'),
      trimEventCount: intAt('trimEventCount'),
      recycledBitmapCount: intAt('recycledBitmapCount'),
      lastTrimLevel: intAt('lastTrimLevel', -1),
    );
  }

  @override
  String toString() => 'PixelSurfaceStats('
      'handleCount=$handleCount, '
      'poolCount=$poolCount, '
      'createCount=$createCount, '
      'lastFlushMs=$lastFlushMs, '
      'lastMemoryWarningMs=$lastMemoryWarningMs, '
      'trimEventCount=$trimEventCount, '
      'recycledBitmapCount=$recycledBitmapCount, '
      'lastTrimLevel=$lastTrimLevel'
      ')';
}
