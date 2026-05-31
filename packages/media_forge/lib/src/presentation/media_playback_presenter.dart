import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:pixel_surface/pixel_surface.dart';
import '../frb_generated/api/runtime.dart';

import 'media_gpu_texture_presenter.dart';

/// How decoded video reaches the screen.
enum MediaPresentationMode {
  /// [GpuTextureRegistry] when supported, else CPU fallback.
  auto,

  /// Always GPU texture upload (no `decodeImageFromPixels`).
  gpuOnly,

  /// CPU `decodeImageFromPixels` (debug / platforms without GPU texture).
  cpuFallback,
}

/// Bridges [MediaPlaybackEngine.takeVideoFrame] → GPU texture or CPU image.
///
/// Intended for a ~16ms presentation tick separate from diagnostics [setState].
class MediaPlaybackPresenter {
  MediaPlaybackPresenter({
    required int textureHandle,
    this.mode = MediaPresentationMode.auto,
  }) : _gpu = MediaGpuTexturePresenter(textureHandle: textureHandle);

  final MediaPresentationMode mode;
  final MediaGpuTexturePresenter _gpu;

  /// Last CPU-decoded image (only when not using GPU path).
  final ValueNotifier<ui.Image?> cpuImage = ValueNotifier<ui.Image?>(null);

  int _lastGpuLogPtsMs = -1;
  DateTime? _lastGpuLogAt;
  MediaGpuTexturePresenter get gpu => _gpu;

  bool get usesGpuTexture {
    switch (mode) {
      case MediaPresentationMode.gpuOnly:
        return gpuTextureSupported();
      case MediaPresentationMode.cpuFallback:
        return false;
      case MediaPresentationMode.auto:
        return gpuTextureSupported();
    }
  }

  /// Pull one display frame from the engine and present it.
  ///
  /// Returns presentation PTS in ms, or `-1` if no new frame.
  Future<int> presentNext(MediaPlaybackEngine engine) async {
    final frame = await engine.takeVideoFrame();
    if (frame == null) return -1;

    final pts = frame.ptsMs.toInt();
    if (usesGpuTexture && frame.pixelBufferPtr != BigInt.zero) {
      await _presentPixelBuffer(frame);
      return pts;
    }

    if (usesGpuTexture) {
      final uploaded = await _gpu.uploadIfNew(frame);
      if (uploaded) {
        _logGpuPts(pts, frame.width, frame.height, path: 'rgba');
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

    final pts = handoff.ptsMs.toInt();
    final ptr = handoff.pixelBufferPtr.toInt();

    if (_gpu.textureId.value == null || _gpu.frameSize.value.width != w.toDouble()) {
      await _gpu.ensureTextureForSize(w, h);
    }
    if (_gpu.textureId.value == null) {
      if (kDebugMode) {
        debugPrint('[MediaPresenter] pixel buffer: texture not ready ${w}x$h');
      }
      return;
    }

    await GpuTextureRegistry.presentPixelBuffer(
      handle: _gpu.textureHandle,
      pixelBufferPtr: ptr,
    );
    _logGpuPts(pts, w, h, path: 'vt');
  }

  void _logGpuPts(int pts, int w, int h, {required String path}) {
    if (!kDebugMode) return;
    final now = DateTime.now();
    if (pts != _lastGpuLogPtsMs ||
        _lastGpuLogAt == null ||
        now.difference(_lastGpuLogAt!) > const Duration(seconds: 2)) {
      _lastGpuLogPtsMs = pts;
      _lastGpuLogAt = now;
      debugPrint('[MediaPresenter] $path pts=${pts}ms ${w}x$h');
    }
  }

  Future<void> _presentCpu(MediaVideoFrame frame) async {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      frame.pixels,
      frame.width,
      frame.height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    final img = await completer.future;
    final old = cpuImage.value;
    cpuImage.value = img;
    old?.dispose();
  }

  Future<void> reset() async {
    await _gpu.disposeTexture();
    _lastGpuLogPtsMs = -1;
    _lastGpuLogAt = null;
    final old = cpuImage.value;
    cpuImage.value = null;
    old?.dispose();
  }

  /// Call after timeline seek — keeps texture, clears PTS dedupe only.
  void onSeek() {
    _gpu.resetPtsTracking();
    _lastGpuLogPtsMs = -1;
  }

  void dispose() {
    _gpu.dispose();
    cpuImage.dispose();
  }
}
