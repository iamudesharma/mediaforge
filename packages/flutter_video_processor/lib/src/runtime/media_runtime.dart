import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:rust_gpu_texture/rust_gpu_texture.dart';

import '../video_processor.dart';
import 'video_texture_pool.dart';

/// Owns one open video asset: probe, trim metadata, preview decode, and texture upload.
///
/// Sprint V1.1 — scrub via [seekTo]; decoder-clock playback lands in V1.3.
class MediaRuntime extends ChangeNotifier {
  MediaRuntime({
    this.previewMaxEdge = 720,
    VideoTexturePool? texturePool,
  }) : _texturePool = texturePool ?? VideoTexturePool();

  final int previewMaxEdge;
  final VideoTexturePool _texturePool;

  String? _inputPath;
  MediaInfo? _mediaInfo;
  int _trimStartMs = 0;
  int _trimEndMs = 0;
  int _ptsMs = 0;
  bool _loading = false;
  String? _error;
  Uint8List? _fallbackRgba;
  int _seekGeneration = 0;
  bool _disposed = false;

  /// Whether [GpuTextureRegistry] can display preview on this platform.
  static bool get isTexturePreviewAvailable => gpuTextureSupported();

  String? get inputPath => _inputPath;
  MediaInfo? get mediaInfo => _mediaInfo;
  int get trimStartMs => _trimStartMs;
  int get trimEndMs => _trimEndMs;
  int get ptsMs => _ptsMs;
  bool get isLoading => _loading;
  String? get error => _error;
  Uint8List? get fallbackRgba => _fallbackRgba;

  int? get textureId => _texturePool.textureId;
  int get previewWidth => _texturePool.width;
  int get previewHeight => _texturePool.height;

  bool get isOpen => _inputPath != null && _mediaInfo != null;

  double get aspectRatio {
    final info = _mediaInfo;
    if (info == null || info.height == 0) return 16 / 9;
    return info.width / info.height;
  }

  /// Opens [path], probes metadata, and decodes the first preview frame.
  Future<void> open(String path) async {
    if (_disposed) return;
    await close();
    _inputPath = path;
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      await VideoProcessor.initialize();
      _mediaInfo = await VideoProcessor.getMediaInfo(path);
      _trimStartMs = 0;
      _trimEndMs = _mediaInfo!.durationMs.toInt();
      await seekTo(Duration.zero, coalesce: false);
    } catch (e) {
      _error = e.toString();
      _loading = false;
      notifyListeners();
      rethrow;
    }
  }

  void setTrimRange({int? startMs, int? endMs}) {
    if (_mediaInfo == null) return;
    final dur = _mediaInfo!.durationMs.toInt();
    _trimStartMs = (startMs ?? _trimStartMs).clamp(0, dur);
    _trimEndMs = (endMs ?? _trimEndMs).clamp(_trimStartMs, dur);
    notifyListeners();
  }

  /// Decodes and presents the frame at [position]. When [coalesce] is true, stale results are dropped.
  Future<void> seekTo(Duration position, {bool coalesce = true}) async {
    final path = _inputPath;
    if (path == null || _disposed) return;

    final gen = ++_seekGeneration;
    _loading = true;
    _error = null;
    notifyListeners();

    final positionMs = position.inMilliseconds.clamp(0, _trimEndMs);

    try {
      final frame = await VideoProcessor.decodePreviewFrameRgba(
        inputPath: path,
        positionMs: positionMs,
        maxEdge: previewMaxEdge,
      );

      if (_disposed || (coalesce && gen != _seekGeneration)) return;

      _ptsMs = frame.ptsMs.toInt();
      _fallbackRgba = frame.rgba;

      final w = frame.width.toInt();
      final h = frame.height.toInt();
      final texId = await _texturePool.ensureTexture(width: w, height: h);
      if (_disposed || (coalesce && gen != _seekGeneration)) return;

      if (texId != null) {
        await _texturePool.presentRgba(frame.rgba);
      }

      _loading = false;
      notifyListeners();
    } catch (e) {
      if (_disposed || (coalesce && gen != _seekGeneration)) return;
      _error = e.toString();
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> close() async {
    _seekGeneration++;
    _inputPath = null;
    _mediaInfo = null;
    _fallbackRgba = null;
    _ptsMs = 0;
    _loading = false;
    _error = null;
    await _texturePool.release();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(close());
    super.dispose();
  }
}
