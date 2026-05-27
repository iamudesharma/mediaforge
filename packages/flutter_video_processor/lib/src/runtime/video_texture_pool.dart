import 'dart:typed_data';

import 'package:rust_gpu_texture/rust_gpu_texture.dart';

/// Lifecycle for a single Flutter [Texture] used by [MediaRuntime].
///
/// One stable native [handle] per pool instance; recreates registration on resize.
final class VideoTexturePool {
  VideoTexturePool({this.handle = defaultHandle});

  static const defaultHandle = 9001;

  final int handle;

  int? _textureId;
  int _width = 0;
  int _height = 0;

  int? get textureId => _textureId;
  int get width => _width;
  int get height => _height;

  /// Ensures a registered texture exists for [width]×[height]. Returns null when unsupported.
  Future<int?> ensureTexture({required int width, required int height}) async {
    if (!gpuTextureSupported() || width <= 0 || height <= 0) {
      return null;
    }
    if (_textureId != null && _width == width && _height == height) {
      return _textureId;
    }
    await release();
    final id = await GpuTextureRegistry.createTexture(
      handle: handle,
      width: width,
      height: height,
    );
    _textureId = id;
    _width = width;
    _height = height;
    return id;
  }

  /// Uploads RGBA8888 pixels (must match [width]×[height]×4).
  Future<void> presentRgba(Uint8List rgba) async {
    if (_textureId == null) return;
    await GpuTextureRegistry.updateTexture(handle: handle, pixels: rgba);
  }

  /// MediaCodec → SurfaceTexture (Android V1.6). Texture must exist.
  Future<PreviewSurfaceFrame?> decodePreviewToSurface({
    required String path,
    required int positionMs,
    required int maxEdge,
  }) async {
    if (_textureId == null) return null;
    return GpuTextureRegistry.decodePreviewToSurface(
      handle: handle,
      path: path,
      positionMs: positionMs,
      maxEdge: maxEdge,
    );
  }

  /// Adopts a BGRA `CVPixelBuffer*` from VideoToolbox preview decode (Apple).
  Future<void> presentPixelBuffer(int pixelBufferPtr) async {
    if (_textureId == null || pixelBufferPtr == 0) return;
    await GpuTextureRegistry.presentPixelBuffer(
      handle: handle,
      pixelBufferPtr: pixelBufferPtr,
    );
  }

  Future<void> release() async {
    if (_textureId != null) {
      await GpuTextureRegistry.disposeTexture(handle);
      _textureId = null;
      _width = 0;
      _height = 0;
    }
  }
}
