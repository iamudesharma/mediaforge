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

  Future<void> release() async {
    if (_textureId != null) {
      await GpuTextureRegistry.disposeTexture(handle);
      _textureId = null;
      _width = 0;
      _height = 0;
    }
  }
}
