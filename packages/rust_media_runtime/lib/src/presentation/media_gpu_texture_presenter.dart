import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:rust_gpu_texture/rust_gpu_texture.dart';
import '../frb_generated/api/runtime.dart' show MediaVideoFrame;

/// Uploads decoded RGBA frames to a Flutter [Texture] without rebuilding the widget tree.
///
/// Use with [MediaVideoSurface] — avoids [setState] and `decodeImageFromPixels` on the hot path.
class MediaGpuTexturePresenter {
  MediaGpuTexturePresenter({required this.textureHandle});

  final int textureHandle;

  /// Flutter texture id from [GpuTextureRegistry.createTexture].
  final ValueNotifier<int?> textureId = ValueNotifier<int?>(null);

  /// Decoded frame dimensions (logical pixels).
  final ValueNotifier<Size> frameSize = ValueNotifier(Size.zero);

  int _lastUploadedPtsMs = -1;
  int _width = 0;
  int _height = 0;

  bool get isReady => textureId.value != null && frameSize.value != Size.zero;

  /// Upload [frame] when PTS changes. Returns true if a new frame was uploaded.
  Future<bool> uploadIfNew(MediaVideoFrame frame) async {
    if (!gpuTextureSupported()) return false;
    final w = frame.width;
    final h = frame.height;
    if (w <= 0 || h <= 0) return false;

    final pts = frame.ptsMs.toInt();
    if (pts == _lastUploadedPtsMs && isReady) {
      return false;
    }

    if (textureId.value == null || _width != w || _height != h) {
      await _recreateTexture(w, h);
    }
    if (textureId.value == null) return false;

    await GpuTextureRegistry.updateTexture(
      handle: textureHandle,
      pixels: frame.pixels,
    );
    await GpuTextureRegistry.notifyFrameAvailable(textureHandle);
    _lastUploadedPtsMs = pts;
    return true;
  }

  /// Ensures a Flutter texture exists at [w]×[h] (VT pixel-buffer path).
  Future<void> ensureTextureForSize(int w, int h) async {
    if (!gpuTextureSupported()) return;
    if (textureId.value != null && _width == w && _height == h) return;
    await _recreateTexture(w, h);
  }

  Future<void> _recreateTexture(int w, int h) async {
    await disposeTexture();
    final id = await GpuTextureRegistry.createTexture(
      handle: textureHandle,
      width: w,
      height: h,
    );
    if (id == null) return;
    _width = w;
    _height = h;
    textureId.value = id;
    frameSize.value = Size(w.toDouble(), h.toDouble());
    if (kDebugMode) {
      debugPrint(
        '[MediaGpuTexture] texture ready handle=$textureHandle id=$id ${w}x$h',
      );
    }
  }

  Future<void> disposeTexture() async {
    if (textureId.value != null || _width > 0) {
      await GpuTextureRegistry.disposeTexture(textureHandle);
    }
    textureId.value = null;
    frameSize.value = Size.zero;
    _width = 0;
    _height = 0;
    _lastUploadedPtsMs = -1;
  }

  /// After seek — allow re-upload even if PTS matches pre-seek frame.
  void resetPtsTracking() {
    _lastUploadedPtsMs = -1;
  }

  void dispose() {
    disposeTexture();
    textureId.dispose();
    frameSize.dispose();
  }
}
