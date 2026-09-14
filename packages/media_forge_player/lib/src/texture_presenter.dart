import 'dart:ui' show Image, PixelFormat, Size, decodeImageFromPixels;

import 'package:flutter/foundation.dart';
import 'package:media_forge/media_forge.dart';
import 'package:pixel_surface/pixel_surface.dart';

/// Hook that runs the GPU enhancement stage for one decoded frame.
///
/// Returns the enhanced handoff (whose `+1` the presenter then hands to
/// Flutter), or `null` to present [handoff] untouched. Implemented by
/// [MediaForgePlayerController]; kept as a function type so the presenter has
/// no dependency on the controller.
typedef MediaForgeFrameEnhancer = Future<PixelBufferHandoff?> Function(
  MediaVideoFrame frame,
  PixelBufferHandoff handoff,
);

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

  /// Optional GPU enhancement stage, run on the decoded frame before
  /// presentation. `null` leaves the existing render path untouched.
  MediaForgeFrameEnhancer? enhancer;

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

  // ---- §6/§8 observability ----
  int _bridgeCalls = 0;
  int _presentedFrames = 0;
  String _renderingPath = 'unknown';
  int _nativeW = 0;
  int _nativeH = 0;
  double? _lastPresentationMs;
  bool _enhancementActive = false;

  bool get isReady => textureId.value != null && frameSize.value != Size.zero;
  bool get usesGpuTexture => gpuTextureSupported();

  /// Bridge presentation calls (every native present/upload attempt).
  int get bridgeCallCount => _bridgeCalls;

  /// Actually presented frames (new PTS accepted).
  int get presentedFrameCount => _presentedFrames;

  /// Exact active rendering path. One of:
  /// `videotoolbox_iosurface_zero_copy`, `videotoolbox_bgra_copy`,
  /// `software_bgra_upload`, `software_rgba_upload`, `cpu_fallback`,
  /// `android_surface_zero_copy` (only when verified), `android_bitmap_upload`.
  String get activeRenderingPath => _renderingPath;

  int get nativeWidth => _nativeW;
  int get nativeHeight => _nativeH;
  double? get lastPresentationMs => _lastPresentationMs;

  /// True when the last presented frame came out of the GPU enhancement stage.
  bool get enhancementActive => _enhancementActive;

  /// Present one decoder frame. Returns PTS ms, or -1 when nothing new.
  Future<int> presentNext(MediaPlaybackEngine engine) async {
    if (_disposed) return -1;
    final t0 = DateTime.now();
    final frame = await engine.takeVideoFrame();
    if (frame == null) return -1;
    final pts = frame.ptsMs.toInt();
    if (frame.pixelBufferPtr != BigInt.zero) {
      _bridgeCalls++;
      await _presentPixelBuffer(frame);
      _presentedFrames++;
      _lastPresentationMs =
          DateTime.now().difference(t0).inMicroseconds / 1000.0;
      return pts;
    }
    if (usesGpuTexture) {
      final uploaded = await _uploadBgra(frame, pts);
      if (uploaded) {
        _presentedFrames++;
        _lastPresentationMs =
            DateTime.now().difference(t0).inMicroseconds / 1000.0;
      }
    } else {
      _bridgeCalls++;
      await _presentCpu(frame);
      _presentedFrames++;
      _renderingPath = 'cpu_fallback';
      _lastPresentationMs =
          DateTime.now().difference(t0).inMicroseconds / 1000.0;
    }
    return pts;
  }

  Future<void> _presentPixelBuffer(MediaVideoFrame frame) async {
    var handoff = await mediaVideoFrameIntoPixelBufferHandoff(frame: frame);
    if (handoff == null) return;

    // GPU enhancement, when enabled: the engine consumes the decoded frame's
    // retain and returns its own surface, so `handoff` must not be presented
    // as well. A `null` result means "not enhanced" and the decoded frame is
    // presented unchanged.
    var present = handoff;
    final enhance = enhancer;
    _enhancementActive = false;
    if (enhance != null) {
      try {
        final enhanced = await enhance(frame, handoff);
        if (_disposed) return;
        if (enhanced != null) {
          present = enhanced;
          _enhancementActive = true;
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[MediaForgePlayer] enhancement stage failed: $e');
        }
      }
    }

    final w = present.width;
    final h = present.height;
    if (w <= 0 || h <= 0) return;
    // Native diagnostics keep reporting the *decoder* dimensions; the
    // enhanced size is what the presentation texture actually holds.
    if (frame.width > 0 && frame.height > 0) {
      _nativeW = frame.width;
      _nativeH = frame.height;
    }
    final ptr = present.pixelBufferPtr.toInt();
    await _ensureTexture(w, h);
    if (_disposed || textureId.value == null) return;
    await GpuTextureRegistry.presentPixelBuffer(
      handle: textureHandle,
      pixelBufferPtr: ptr,
    );
    // The VT handoff buffer is IOSurface-backed by construction
    // (see media_forge vt_pixel_buffer.rs); Swift adopts it without copy
    // when canAdoptPixelBufferDirectly succeeds. Report zero-copy only for
    // this path — never for RGBA uploads.
    _renderingPath = _enhancementActive
        ? 'videotoolbox_iosurface_zero_copy+enhanced'
        : 'videotoolbox_iosurface_zero_copy';
  }

  /// BGRA-first upload. `media_forge` decodes to RGBA bytes today, so this
  /// currently goes through the RGBA channel until the engine emits BGRA;
  /// the branch is explicit so the BGRA cutover is one line.
  Future<bool> _uploadBgra(MediaVideoFrame frame, int pts) async {
    if (!gpuTextureSupported()) return false;
    final w = frame.width;
    final h = frame.height;
    if (w <= 0 || h <= 0) return false;
    if (pts == _lastPtsMs && isReady) return false;
    _nativeW = w;
    _nativeH = h;
    await _ensureTexture(w, h);
    if (_disposed || textureId.value == null) return false;
    _bridgeCalls++;
    // Engine frames are RGBA today; uploading via the BGRA entry point
    // would swap channels, so stay on the RGBA path until the engine
    // offers BGRA. Prefer updateTextureBgra the moment the engine emits
    // BGRA directly (software fallback on Apple).
    await GpuTextureRegistry.updateTextureRgba(
      handle: textureHandle,
      pixels: frame.pixels,
    );
    if (_disposed) return false;
    await GpuTextureRegistry.notifyFrameAvailable(textureHandle);
    _bridgeCalls++;
    _renderingPath = 'software_rgba_upload';
    _lastPtsMs = pts;
    return true;
  }

  /// Direct BGRA upload (software fallback on Apple when the engine emits
  /// BGRA). Skips the RGBA→BGRA swizzle via `updateTextureBgra`.
  Future<bool> uploadBgraDirect({
    required int width,
    required int height,
    required Uint8List bgra,
    required int ptsMs,
  }) async {
    if (!gpuTextureSupported() || _disposed) return false;
    if (width <= 0 || height <= 0) return false;
    if (ptsMs == _lastPtsMs && isReady) return false;
    _nativeW = width;
    _nativeH = height;
    await _ensureTexture(width, height);
    if (_disposed || textureId.value == null) return false;
    _bridgeCalls++;
    await GpuTextureRegistry.updateTextureBgra(
      handle: textureHandle,
      pixels: bgra,
    );
    if (_disposed) return false;
    await GpuTextureRegistry.notifyFrameAvailable(textureHandle);
    _bridgeCalls++;
    _renderingPath = 'software_bgra_upload';
    _lastPtsMs = ptsMs;
    _presentedFrames++;
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
    // NOTE: the ValueNotifiers are intentionally left undisposed. Widgets
    // (MediaForgeVideo, captions) may still be mounted during route
    // transitions when the controller is released; notifying/disposed
    // asserts would crash them. The notifiers hold no native resources
    // and are GC-safe once unreferenced — only the GPU texture needs
    // explicit release (above).
    textureId.value = null;
    frameSize.value = Size.zero;
    final old = cpuImage.value;
    cpuImage.value = null;
    old?.dispose();
  }
}
