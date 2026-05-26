import 'dart:async';
import 'dart:io' show Platform;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

/// Front-camera stream for Nexus A live beauty preview.
abstract final class LiveCameraService {
  static bool get isSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static CameraController? _controller;
  static void Function(CameraImage image)? _onFrame;
  static bool _streaming = false;
  static bool _busy = false;
  static Future<void> _queue = Future<void>.value();
  static List<CameraDescription>? _cachedCameras;

  static bool get isActive => _streaming && _controller != null;

  /// True while [start] / [stop] is in flight — disable UI toggles.
  static bool get isBusy => _busy;

  /// Initialized while live mode is active; use with [CameraPreview].
  static CameraController? get controller => _controller;

  static Future<void> start({
    required void Function(CameraImage image) onFrame,
    int maxWidth = 1280,
  }) {
    return _enqueue(() async {
      if (!isSupported) {
        throw UnsupportedError('Live camera is mobile-only');
      }
      await _stopInternal();
      _onFrame = onFrame;

      final front = await _frontCamera();
      final preset = maxWidth >= 1280
          ? ResolutionPreset.high
          : ResolutionPreset.medium;

      final controller = CameraController(
        front,
        preset,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      _controller = controller;
      try {
        await controller.initialize();
        await controller.startImageStream(_handleFrame);
        _streaming = true;
      } catch (e) {
        _controller = null;
        _onFrame = null;
        try {
          await controller.dispose();
        } catch (_) {}
        rethrow;
      }
    });
  }

  static void _handleFrame(CameraImage image) {
    if (!_streaming) return;
    _onFrame?.call(image);
  }

  static Future<void> stop() => _enqueue(_stopInternal);

  static Future<void> _stopInternal() async {
    _streaming = false;
    _onFrame = null;

    final controller = _controller;
    _controller = null;
    if (controller == null) return;

    try {
      if (controller.value.isInitialized &&
          controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } catch (_) {}

    // Xiaomi / CameraX: brief pause before dispose avoids drain timeouts.
    if (Platform.isAndroid) {
      await Future<void>.delayed(const Duration(milliseconds: 350));
    }

    try {
      await controller.dispose();
    } catch (_) {}

    if (Platform.isAndroid) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }

  static Future<CameraDescription> _frontCamera() async {
    final cameras = _cachedCameras ??= await availableCameras();
    if (cameras.isEmpty) {
      throw StateError('No camera found');
    }
    for (final camera in cameras) {
      if (camera.lensDirection == CameraLensDirection.front) {
        return camera;
      }
    }
    // Some OEMs mislabel lens direction — front is usually the second id.
    if (Platform.isAndroid && cameras.length > 1) {
      return cameras[1];
    }
    return cameras.first;
  }

  static Future<T> _enqueue<T>(Future<T> Function() action) {
    final run = _queue.then((_) async {
      _busy = true;
      try {
        return await action();
      } finally {
        _busy = false;
      }
    });
    _queue = run.then((_) {}, onError: (_) {});
    return run;
  }
}
