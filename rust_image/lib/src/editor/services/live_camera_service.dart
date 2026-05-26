import 'dart:async';
import 'dart:io' show Platform;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

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

  /// Resolve camera list on the UI isolate before first open (avoids CameraX
  /// refresh races during [stop] on some Android builds).
  static Future<void> warmup() async {
    if (!isSupported) return;
    _cachedCameras ??= await availableCameras();
  }

  static Future<void> start({
    required void Function(CameraImage image) onFrame,
    int maxWidth = 1280,
  }) {
    return _enqueue(() async {
      if (!isSupported) {
        throw UnsupportedError('Live camera is mobile-only');
      }
      await warmup();
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
    if (controller == null) return;

    // Let Flutter detach [CameraPreview] before CameraX surfaces close.
    await _waitForUiFrame();

    try {
      if (controller.value.isInitialized &&
          controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } catch (_) {}

    // CameraX on Xiaomi / Redmi: pipeline needs time before dispose.
    if (Platform.isAndroid) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }

    _controller = null;

    try {
      await controller.dispose();
    } catch (_) {}

    if (Platform.isAndroid) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
  }

  static Future<void> _waitForUiFrame() async {
    final completer = Completer<void>();
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      if (!completer.isCompleted) completer.complete();
    });
    await completer.future;
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
