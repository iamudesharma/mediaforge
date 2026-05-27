import 'dart:async';
import 'dart:io' show Platform;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'camera_permission.dart';

/// Called after [CameraController] is created but before [CameraController.initialize].
/// Mount [CameraPreview] in this hook so CameraX can bind a preview surface (Android).
typedef LiveCameraMountHook = Future<void> Function(CameraController controller);

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
    LiveCameraMountHook? beforeInitialize,
  }) {
    return _enqueue(() async {
      if (!isSupported) {
        throw UnsupportedError('Live camera is mobile-only');
      }
      if (!await CameraPermission.ensureGranted()) {
        final blocked = await CameraPermission.isPermanentlyDenied;
        throw StateError(
          blocked
              ? 'Camera permission denied. Enable Camera in system Settings.'
              : 'Camera permission denied.',
        );
      }

      await _stopInternal();
      if (Platform.isAndroid) {
        _cachedCameras = null;
        await Future<void>.delayed(const Duration(milliseconds: 350));
      }

      _onFrame = onFrame;
      final front = await _frontCamera();
      final preset = _resolutionPreset(maxWidth);

      Object? lastError;
      for (var attempt = 0; attempt < 3; attempt++) {
        if (attempt > 0) {
          _cachedCameras = null;
          if (Platform.isAndroid) {
            await Future<void>.delayed(Duration(milliseconds: 500 * attempt));
          }
        }

        final controller = CameraController(
          front,
          preset,
          enableAudio: false,
          imageFormatGroup: ImageFormatGroup.yuv420,
        );
        _controller = controller;

        try {
          if (beforeInitialize != null) {
            await beforeInitialize(controller);
          } else if (Platform.isAndroid) {
            await _waitForUiFrame();
            await _waitForUiFrame();
          }
          await controller.initialize();
          await controller.startImageStream(_handleFrame);
          _streaming = true;
          return;
        } catch (e) {
          lastError = e;
          _streaming = false;
          _controller = null;
          try {
            await controller.dispose();
          } catch (_) {}
        }
      }

      throw StateError('Camera failed to open: $lastError');
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
      _cachedCameras = null;
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

  static ResolutionPreset _resolutionPreset(int maxWidth) {
    if (Platform.isAndroid) {
      return maxWidth >= 960 ? ResolutionPreset.medium : ResolutionPreset.low;
    }
    return maxWidth >= 1280 ? ResolutionPreset.high : ResolutionPreset.medium;
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
