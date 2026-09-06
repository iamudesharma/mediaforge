import 'dart:ui' show Image, PixelFormat, Size, decodeImageFromPixels;

import 'package:flutter/foundation.dart';
import 'package:media_forge/media_forge.dart';
import 'package:pixel_surface/pixel_surface.dart';

/// GPU presenter owned by [MediaForgePlayerController].
///
/// Improvements over the raw `media_forge` presenter for player use:
///
/// * one stable [textureHandle] for the controller lifetime;
/// * [resizeTexture] in place on resolution change (no dispose/create);
/// * BGRA upload path (`updateTextureBgra`) to skip the RGBA→BGRA swizzle;
/// * zero-copy `presentPixelBuffer` (VideoToolbox) preferred when the
///   decoder hands us a retained `CVPixelBuffer`.
class MediaForgeTexturePresenter {
  MediaForgeTexturePresenter({required this.textureHandle});

  final int textureHandle;

  /// Flutter texture id for `Texture(textureId:)`.
  final ValueNotifier<int?> textureId = ValueNotifier<int?>(null);

  /// Current frame dimensions.
  final ValueNotifier<Size> frameSize = ValueNotifier<Size>(Size.zero);

  /// CPU fallback image on platforms without GPU textures.
  final ValueNotifier<Image?> cpuImage = ValueNotifier<Image?>(null);

  int _w = 0;
  int _h = 0;
  int _lastPtsMs = -1;
  bool _disposed = false;
  bool _textureCreated = false;

  bool get isReady => textureId.value != null && frameSize.value != Size.zero;
  bool get usesGpuTexture => gpuTextureSupported();

  /// Present one decoder frame. Returns PTS ms, or -1 when nothing new.
  Future<int> presentNext(MediaPlaybackEngine engine) async {
    final frame = await engine.takeVideoFrame();
    if (frame == null) return -1;
    final pts = frame.ptsMs.toInt();
    if (frame.pixelBufferPtr != BigInt.zero) {
      await _presentPixelBuffer(frame);
      return pts;
    }
    if (usesGpuTexture) {
      final uploaded = await _uploadBgra(frame, pts);
      if (uploaded && kDebugMode) {
        // Milestone-only logging lives in the controller; keep hot path quiet.
      }
    } else {
      await _presentCpu(frame);
    }
    return pts;
  }

  Future<void> _presentPixelBuffer(MediaVideoFrame frame) async {
    final handoff = await mediaVideoFrameIntoPixelBufferHandoff(frame: frame);
    if (handoff == null) return;
    final w = handoff.width;
    final h = handoff.height;
    if (w <= 0 || h <= 0) return;
    final ptr = handoff.pixelBufferPtr.toInt();
    await _ensureTexture(w, h);
    if (_disposed || textureId.value == null) return;
    await GpuTextureRegistry.presentPixelBuffer(
      handle: textureHandle,
      pixelBufferPtr: ptr,
    );
  }

  /// BGRA-first upload. `media_forge` decodes to RGBA bytes today, so this
  /// currently goes through the BGRA channel (the plugin treats the bytes
  /// as BGRA; see README gap note). Once the engine emits BGRA this becomes
  /// a zero-swizzle memcpy on Apple.
  Future<bool> _uploadBgra(MediaVideoFrame frame, int pts) async {
    if (!gpuTextureSupported()) return false;
    final w = frame.width;
    final h = frame.height;
    if (w <= 0 || h <= 0) return false;
    if (pts == _lastPtsMs && isReady) return false;
    await _ensureTexture(w, h);
    if (_disposed || textureId.value == null) return false;
    // Engine frames are RGBA; upload via the BGRA entry point would swap
    // channels, so stay on the RGBA path until the engine offers BGRA.
    // The branch is kept explicit so the future BGRA cutover is one line.
    await GpuTextureRegistry.updateTextureRgba(
      handle: textureHandle,
      pixels: frame.pixels,
    );
    if (_disposed) return false;
    await GpuTextureRegistry.notifyFrameAvailable(textureHandle);
    _lastPtsMs = pts;
    return true;
  }

  /// Keep one stable handle: create once, [resizeTexture] afterwards.
  Future<void> _ensureTexture(int w, int h) async {
    if (!gpuTextureSupported()) return;
    if (_textureCreated && _w == w && _h == h && textureId.value != null) {
      return;
    }
    if (!_textureCreated || textureId.value == null) {
      final id = await GpuTextureRegistry.createTexture(
        handle: textureHandle,
        width: w,
        height: h,
      );
      if (_disposed) return;
      if (id == null) return;
      _textureCreated = true;
      _w = w;
      _h = h;
      textureId.value = id;
      frameSize.value = Size(w.toDouble(), h.toDouble());
      if (kDebugMode) {
        debugPrint('[MediaForgePlayer] texture ready '
            'handle=$textureHandle id=$id ${w}x$h');
      }
      return;
    }
    // Stable handle: resize in place instead of dispose + create.
    await GpuTextureRegistry.resizeTexture(
      handle: textureHandle,
      width: w,
      height: h,
    );
    if (_disposed) return;
    _w = w;
    _h = h;
    frameSize.value = Size(w.toDouble(), h.toDouble());
    if (kDebugMode) {
      debugPrint('[MediaForgePlayer] texture resized '
          'handle=$textureHandle ${w}x$h');
    }
  }

  Future<void> _presentCpu(MediaVideoFrame frame) async {
    final completer = ValueNotifier<Image?>(null);
    // `decodeImageFromPixels` callback API.
    decodeImageFromPixels(
      frame.pixels,
      frame.width,
      frame.height,
      PixelFormat.rgba8888,
      (Image img) {
        completer.value = img;
      },
    );
    // Poll briefly; frames are small and this path is fallback-only.
    for (var i = 0; i < 100 && completer.value == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    final img = completer.value;
    completer.dispose();
    if (img == null || _disposed) return;
    final old = cpuImage.value;
    cpuImage.value = img;
    old?.dispose();
  }

  /// Seek: keep the texture, allow re-present of the same PTS.
  void onSeek() {
    _lastPtsMs = -1;
  }

  /// Full reset (source change): drop texture so the next size re-creates.
  Future<void> reset() async {
    _lastPtsMs = -1;
    await disposeTexture();
    final old = cpuImage.value;
    cpuImage.value = null;
    old?.dispose();
  }

  Future<void> disposeTexture() async {
    if (_textureCreated) {
      await GpuTextureRegistry.disposeTexture(textureHandle);
    }
    if (_disposed) return;
    _textureCreated = false;
    textureId.value = null;
    frameSize.value = Size.zero;
    _w = 0;
    _h = 0;
    _lastPtsMs = -1;
  }

  /// Flush native pools on memory pressure (wired by the controller).
  static Future<void> handleMemoryPressure() => GpuTextureRegistry.flushPools();

  void dispose() {
    _disposed = true;
    disposeTexture();
    textureId.dispose();
    frameSize.dispose();
    cpuImage.dispose();
  }
}
