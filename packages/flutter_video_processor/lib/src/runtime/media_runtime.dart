import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:rust_gpu_texture/rust_gpu_texture.dart';
import '../video_processor.dart';
import 'frame_queue.dart';
import 'media_runtime_metrics.dart';
import 'playback_clock.dart';
import 'preview_frame.dart';
import 'video_texture_pool.dart';

/// Owns one open video asset: probe, trim metadata, preview decode, and texture upload.
///
/// V1.3+: [PlaybackClock] wall-clock during [play]; async per-frame decode (UI stays real-time).
class MediaRuntime extends ChangeNotifier {
  MediaRuntime({
    this.previewMaxEdge = 720,
    this.targetPreviewFps = 30,
    this.scrubDebounce = const Duration(milliseconds: 280),
    this.frameQueueMaxDepth = FrameQueue.defaultMaxDepth,
    this.loopPlayback = true,
    VideoTexturePool? texturePool,
    FrameQueue? frameQueue,
    PlaybackClock? clock,
  })  : _texturePool = texturePool ?? VideoTexturePool(),
        _frameQueue = frameQueue ?? FrameQueue(maxDepth: frameQueueMaxDepth),
        _clock = clock ?? PlaybackClock();

  final int previewMaxEdge;
  final int targetPreviewFps;
  final Duration scrubDebounce;
  final int frameQueueMaxDepth;
  final bool loopPlayback;
  final VideoTexturePool _texturePool;
  final FrameQueue _frameQueue;
  final PlaybackClock _clock;

  String? _inputPath;
  MediaInfo? _mediaInfo;
  int _trimStartMs = 0;
  int _trimEndMs = 0;
  int _ptsMs = 0;
  bool _scrubLoading = false;
  String? _error;
  Uint8List? _fallbackRgba;
  int _seekGeneration = 0;
  int _playGeneration = 0;
  bool _disposed = false;
  bool _closeInProgress = false;
  Timer? _scrubDebounceTimer;
  int? _pendingScrubMs;
  final MediaRuntimeMetrics _metrics = MediaRuntimeMetrics();
  int? _scrubStartedAtMs;
  int _playbackFramesInWindow = 0;
  int _playbackWindowStartMs = 0;

  /// Wall-clock anchor for real-time preview (decode may lag; UI clock must not).
  DateTime? _playbackWallOrigin;
  int _playbackMediaOriginMs = 0;
  bool _playbackDecodeBusy = false;
  int _playbackDecodeToken = 0;

  /// V1.7 — rolling scrub/playback/texture stats (reset on [open]).
  MediaRuntimeMetrics get metrics => _metrics;

  MediaRuntimeMetricsSnapshot get metricsSnapshot => _metrics.snapshot();

  /// Whether [GpuTextureRegistry] can display preview on this platform.
  static bool get isTexturePreviewAvailable => gpuTextureSupported();

  String? get inputPath => _inputPath;
  MediaInfo? get mediaInfo => _mediaInfo;
  int get trimStartMs => _trimStartMs;
  int get trimEndMs => _trimEndMs;

  /// Display / decoder-clock position (ms).
  int get ptsMs => _ptsMs;
  int get mediaTimeMs => _clock.mediaTimeMs;

  PlaybackState get playbackState => _clock.state;
  bool get isPlaying => _clock.isPlaying;
  bool get isPaused => _clock.isPaused;

  /// True while a scrub/seek decode is in flight (not used during playback).
  bool get isLoading => _scrubLoading;
  String? get error => _error;
  Uint8List? get fallbackRgba => _fallbackRgba;
  int get queuedFrameCount => _frameQueue.length;

  int? get textureId => _texturePool.textureId;
  int get previewWidth => _texturePool.width;
  int get previewHeight => _texturePool.height;

  bool get isOpen => _inputPath != null && _mediaInfo != null;

  void _notifyIfActive() {
    if (_disposed) return;
    notifyListeners();
  }

  double get aspectRatio {
    final info = _mediaInfo;
    if (info == null || info.height == 0) return 16 / 9;
    return info.width / info.height;
  }

  /// Opens [path], probes metadata, and decodes the first preview frame.
  Future<void> open(String path) async {
    if (_disposed) return;
    await close();
    _metrics.reset();
    _scrubStartedAtMs = null;
    _playbackFramesInWindow = 0;
    _playbackWindowStartMs = DateTime.now().millisecondsSinceEpoch;
    _inputPath = path;
    _scrubLoading = true;
    _error = null;
    _notifyIfActive();

    try {
      await VideoProcessor.initialize();
      _mediaInfo = await VideoProcessor.getMediaInfo(path);
      _trimStartMs = 0;
      _trimEndMs = _mediaInfo!.durationMs.toInt();
      _clock.reset();
      await seekTo(Duration.zero);
    } catch (e) {
      _error = e.toString();
      _scrubLoading = false;
      _notifyIfActive();
      rethrow;
    }
  }

  void setTrimRange({int? startMs, int? endMs}) {
    if (_mediaInfo == null) return;
    final dur = _mediaInfo!.durationMs.toInt();
    _trimStartMs = (startMs ?? _trimStartMs).clamp(0, dur);
    _trimEndMs = (endMs ?? _trimEndMs).clamp(_trimStartMs, dur);
    if (_ptsMs > _trimEndMs) {
      _ptsMs = _trimEndMs;
      _clock.mediaTimeMs = _trimEndMs;
    }
    _notifyIfActive();
  }

  /// Starts playback within the trim range (wall-clock master, async decode).
  Future<void> play() async {
    if (!isOpen || _disposed) return;
    _scrubDebounceTimer?.cancel();
    _pendingScrubMs = null;
    _stopPlaybackLoop();
    _playbackMediaOriginMs = _clampPositionMs(_ptsMs);
    _playbackWallOrigin = DateTime.now();
    _clock.mediaTimeMs = _playbackMediaOriginMs;
    _clock.startPlaying();
    final gen = ++_playGeneration;
    unawaited(_playbackLoop(gen));
    _notifyIfActive();
  }

  /// Pauses playback; position is retained at the wall-clock playhead.
  void pause() {
    if (_clock.isPlaying) {
      _ptsMs = _clock.mediaTimeMs;
    }
    _stopPlaybackLoop();
    _notifyIfActive();
  }

  /// Immediate seek — stops playback, flushes queue, decodes one frame.
  Future<void> seekTo(Duration position) async {
    _stopPlaybackLoop();
    _scrubDebounceTimer?.cancel();
    _pendingScrubMs = null;
    _scrubStartedAtMs = DateTime.now().millisecondsSinceEpoch;
    final ms = _clampPositionMs(position.inMilliseconds);
    _clock.mediaTimeMs = ms;
    await _decodeAndPresentScrub(ms);
  }

  /// Debounced scrub for UI playhead drags — stops playback first.
  void scheduleScrub(Duration position) {
    if (_inputPath == null || _disposed) return;
    _stopPlaybackLoop();
    _pendingScrubMs = _clampPositionMs(position.inMilliseconds);
    _scrubDebounceTimer?.cancel();
    _scrubDebounceTimer = Timer(scrubDebounce, () {
      final ms = _pendingScrubMs;
      if (ms == null || _disposed) return;
      _scrubStartedAtMs = DateTime.now().millisecondsSinceEpoch;
      _clock.mediaTimeMs = ms;
      unawaited(_decodeAndPresentScrub(ms));
    });
  }

  int _clampPositionMs(int positionMs) =>
      positionMs.clamp(_trimStartMs, _trimEndMs);

  void _stopPlaybackLoop() {
    if (_clock.isPlaying) {
      _clock.pause();
    }
    _playbackWallOrigin = null;
    _playbackDecodeBusy = false;
    _playbackDecodeToken++;
    _playGeneration++;
  }

  int _wallClockTargetMs() {
    final origin = _playbackWallOrigin;
    if (origin == null) return _clampPositionMs(_clock.mediaTimeMs);
    final wallMs = DateTime.now().difference(origin).inMilliseconds;
    final scaled = (wallMs * _clock.rate).round();
    return _clampPositionMs(_playbackMediaOriginMs + scaled);
  }

  Future<void> _playbackLoop(int playGen) async {
    while (!_disposed &&
        playGen == _playGeneration &&
        _clock.state == PlaybackState.playing) {
      var targetMs = _wallClockTargetMs();

      if (targetMs >= _trimEndMs) {
        if (loopPlayback) {
          _playbackWallOrigin = DateTime.now();
          _playbackMediaOriginMs = _trimStartMs;
          targetMs = _trimStartMs;
          _frameQueue.flush();
        } else {
          targetMs = _trimEndMs;
          _clock.mediaTimeMs = targetMs;
          _ptsMs = targetMs;
          _clock.pause();
          _playbackWallOrigin = null;
          _notifyIfActive();
          break;
        }
      }

      _clock.mediaTimeMs = targetMs;
      _notifyIfActive();

      if (!_playbackDecodeBusy) {
        _playbackDecodeBusy = true;
        final token = ++_playbackDecodeToken;
        final captureTarget = targetMs;
        unawaited(() async {
          try {
            final frame = await _decodeFrame(captureTarget);
            if (_disposed ||
                playGen != _playGeneration ||
                token != _playbackDecodeToken ||
                _clock.state != PlaybackState.playing) {
              return;
            }
            if (frame == null) return;

            _frameQueue.enqueue(frame);
            final ok = await _presentLatest(
              _seekGeneration,
              advanceClock: false,
            );
            if (ok && playGen == _playGeneration) {
              _ptsMs = frame.ptsMs;
              _notifyIfActive();
            }
          } finally {
            if (token == _playbackDecodeToken) {
              _playbackDecodeBusy = false;
            }
          }
        }());
      }

      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
  }

  Future<void> _decodeAndPresentScrub(int positionMs) async {
    final gen = ++_seekGeneration;
    _scrubStartedAtMs ??= DateTime.now().millisecondsSinceEpoch;
    _frameQueue.flush();
    _scrubLoading = true;
    _error = null;
    _notifyIfActive();

    try {
      final frame = await _decodeFrame(positionMs);
      if (_disposed || gen != _seekGeneration) return;
      if (frame != null) {
        _frameQueue.enqueue(frame);
        await _presentLatest(gen, advanceClock: true);
      }
    } catch (e) {
      if (_disposed || gen != _seekGeneration) return;
      _error = e.toString();
      _scrubLoading = false;
      _notifyIfActive();
    }
  }

  bool get _hwPreviewDisabled {
    final v = Platform.environment['VFP_DISABLE_HW_PREVIEW'];
    return v == '1' || v == 'true' || v == 'yes';
  }

  bool get _preferApplePixelBufferPreview =>
      !kIsWeb &&
      (Platform.isMacOS || Platform.isIOS) &&
      isTexturePreviewAvailable &&
      !_hwPreviewDisabled;

  bool get _preferAndroidSurfacePreview =>
      !kIsWeb &&
      Platform.isAndroid &&
      isTexturePreviewAvailable &&
      !_hwPreviewDisabled &&
      _nativeVideoFitsPreviewMaxEdge;

  bool get _nativeVideoFitsPreviewMaxEdge {
    final info = _mediaInfo;
    if (info == null) return false;
    final maxDim = info.width > info.height ? info.width : info.height;
    return maxDim <= previewMaxEdge;
  }

  Future<Uint8List?> _decodeFrameRgbaAt(int positionMs) async {
    final path = _inputPath;
    if (path == null) return null;
    final frame = await VideoProcessor.decodePreviewFrameRgba(
      inputPath: path,
      positionMs: positionMs,
      maxEdge: previewMaxEdge,
    );
    return frame.rgba;
  }

  Future<PreviewFrame?> _decodeFrame(int positionMs) async {
    final path = _inputPath;
    if (path == null) return null;

    if (_preferAndroidSurfacePreview) {
      try {
        final info = _mediaInfo!;
        await _texturePool.ensureTexture(
          width: info.width,
          height: info.height,
        );
        final surface = await _texturePool.decodePreviewToSurface(
          path: path,
          positionMs: positionMs,
          maxEdge: previewMaxEdge,
        );
        if (surface != null) {
          return PreviewFrame(
            ptsMs: surface.ptsMs,
            width: surface.width,
            height: surface.height,
            presentedToSurface: true,
          );
        }
      } catch (_) {
        // RGBA fallback (4K, codec error, etc.).
      }
    }

    if (_preferApplePixelBufferPreview) {
      try {
        final hw = await VideoProcessor.decodePreviewFramePixelBuffer(
          inputPath: path,
          positionMs: positionMs,
          maxEdge: previewMaxEdge,
        );
        final ptr = hw.pixelBufferPtr.toInt();
        if (ptr > 0) {
          return PreviewFrame(
            ptsMs: hw.ptsMs.toInt(),
            width: hw.width,
            height: hw.height,
            pixelBufferPtr: ptr,
          );
        }
      } catch (_) {
        // Fall back to RGBA upload (e.g. HW decode unavailable).
      }
    }

    final frame = await VideoProcessor.decodePreviewFrameRgba(
      inputPath: path,
      positionMs: positionMs,
      maxEdge: previewMaxEdge,
    );

    return PreviewFrame(
      ptsMs: frame.ptsMs.toInt(),
      width: frame.width,
      height: frame.height,
      rgba: frame.rgba,
    );
  }

  Future<bool> _presentLatest(int generation, {bool advanceClock = false}) async {
    if (_disposed || generation != _seekGeneration) return false;

    final preview = _frameQueue.takeLatest();
    if (preview == null) {
      _scrubLoading = false;
      _notifyIfActive();
      return false;
    }

    if (advanceClock) {
      _clock.advanceToFramePts(preview.ptsMs);
    }
    _ptsMs = preview.ptsMs;
    _fallbackRgba = preview.rgba;

    final texId = await _texturePool.ensureTexture(
      width: preview.width,
      height: preview.height,
    );
    if (_disposed || generation != _seekGeneration) return false;

    if (texId != null) {
      if (!preview.presentedToSurface) {
      final ptr = preview.pixelBufferPtr;
      if (ptr != null && ptr > 0) {
        try {
          await _texturePool.presentPixelBuffer(ptr);
        } catch (_) {
          VideoProcessor.releasePreviewPixelBuffer(ptr);
          if (preview.rgba != null) {
            await _texturePool.presentRgba(preview.rgba!);
          } else {
            final fallback = await _decodeFrameRgbaAt(preview.ptsMs);
            if (fallback != null) {
              _fallbackRgba = fallback;
              await _texturePool.presentRgba(fallback);
            }
          }
        }
      } else if (preview.rgba != null) {
        await _texturePool.presentRgba(preview.rgba!);
      }
      }
    } else if (preview.isHwPixelBuffer) {
      VideoProcessor.releasePreviewPixelBuffer(preview.pixelBufferPtr!);
    }

    _scrubLoading = false;
    _recordPresentedFrame(wasScrub: _scrubStartedAtMs != null, preview: preview);
    _notifyIfActive();
    return true;
  }

  void _recordPresentedFrame({
    required bool wasScrub,
    required PreviewFrame preview,
  }) {
    final path = _previewPathFor(preview);
    final texId = _texturePool.textureId;
    _metrics.recordPreviewPath(path, textureId: texId);

    if (wasScrub && _scrubStartedAtMs != null) {
      final latency =
          DateTime.now().millisecondsSinceEpoch - _scrubStartedAtMs!;
      _metrics.recordScrubComplete(latency);
      _scrubStartedAtMs = null;
    }

    if (_clock.isPlaying) {
      _metrics.recordPlaybackFrame();
      _playbackFramesInWindow++;
      final now = DateTime.now().millisecondsSinceEpoch;
      final windowMs = now - _playbackWindowStartMs;
      if (windowMs >= 1000) {
        _metrics.recordPlaybackFpsSample(
          _playbackFramesInWindow * 1000.0 / windowMs,
        );
        _playbackFramesInWindow = 0;
        _playbackWindowStartMs = now;
      }
    }
  }

  PreviewDeliveryPath _previewPathFor(PreviewFrame preview) {
    if (preview.presentedToSurface) {
      return PreviewDeliveryPath.textureSurface;
    }
    if (preview.isHwPixelBuffer) {
      return PreviewDeliveryPath.texturePixelBuffer;
    }
    final texId = _texturePool.textureId;
    if (texId != null && texId > 0) {
      return PreviewDeliveryPath.textureRgba;
    }
    if (preview.rgba != null) {
      return PreviewDeliveryPath.rgbaOnly;
    }
    return PreviewDeliveryPath.none;
  }

  Future<void> close() async {
    if (_closeInProgress) return;
    _closeInProgress = true;
    try {
      _stopPlaybackLoop();
      _scrubDebounceTimer?.cancel();
      _scrubDebounceTimer = null;
      _pendingScrubMs = null;
      _seekGeneration++;
      _frameQueue.flush();
      _inputPath = null;
      _mediaInfo = null;
      _fallbackRgba = null;
      _ptsMs = 0;
      _scrubLoading = false;
      _error = null;
      _clock.reset();
      final hadTexture = _texturePool.textureId != null;
      await _texturePool.release();
      final released = _texturePool.textureId == null;
      _metrics.recordOpenCloseCycle(textureReleased: !hadTexture || released);
      _scrubStartedAtMs = null;
      _notifyIfActive();
    } finally {
      _closeInProgress = false;
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _scrubDebounceTimer?.cancel();
    _scrubDebounceTimer = null;
    _stopPlaybackLoop();
    unawaited(close());
    super.dispose();
  }
}
