import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:pixel_surface/pixel_surface.dart';
import '../video_processor.dart';
import 'frame_queue.dart';
import 'media_runtime_metrics.dart';
import 'playback_clock.dart';
import 'preview_decode_policy.dart';
import 'preview_frame.dart';
import 'video_texture_pool.dart';

/// Owns one open video asset: probe, trim metadata, preview decode, and texture upload.
///
/// V1.3+: [PlaybackClock] wall-clock during [play]; async per-frame decode (UI stays real-time).
class MediaRuntime extends ChangeNotifier with WidgetsBindingObserver {
  MediaRuntime({
    this.previewMaxEdge = 720,
    this.playbackPreviewMaxEdge = 360,
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

  /// Longest edge cap during playback for CPU-bound HEVC / Dolby Vision (scrub may use [previewMaxEdge]).
  final int playbackPreviewMaxEdge;
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

  int _playbackMediaOriginMs = 0;
  DateTime? _playbackWallStart;
  int? _scrubQueueMaxDepth;

  /// Adaptive preview tiers for CPU-bound iPhone HEVC / Dolby Vision.
  static const _adaptivePreviewEdges = [360, 270, 240];
  int _adaptiveEdgeTier = 0;
  int _slowDecodeStreak = 0;
  int _fastDecodeStreak = 0;
  int? _sessionPreviewEdge;

  Timer? _playbackPresentTimer;
  bool _playbackPresentInFlight = false;
  int? _lastPlaybackFrameArrivalMs;

  /// Sprint 1: Persistent native preview session (playback only for DV/HEVC).
  VideoPreviewSession? _session;
  StreamSubscription<PlaybackFrame>? _playbackSubscription;

  /// Per-asset decode path (probe + sticky lock after HW failure).
  PreviewDecodePolicy? _decodePolicy;

  static const _scrubDecodeTimeout = Duration(seconds: 10);

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

  void _releasePreviewFrameResources(PreviewFrame frame) {
    if (frame.pixelBufferPtr != null && frame.pixelBufferPtr! > 0) {
      VideoProcessor.releasePreviewPixelBuffer(frame.pixelBufferPtr!);
    }
    if (frame.rgba != null) {
      VideoProcessor.releaseBuffer(frame.rgba!);
    }
  }

  void _flushQueueAndRelease() {
    while (!_frameQueue.isEmpty) {
      final frame = _frameQueue.takeOldest();
      if (frame != null) {
        _releasePreviewFrameResources(frame);
      }
    }
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
    _clock.state = PlaybackState.opening;
    _notifyIfActive();

    try {
      await VideoProcessor.initialize();
      _mediaInfo = await VideoProcessor.getMediaInfo(path);
      final info = _mediaInfo!;
      final frameSize = info.width * info.height * 4;
      const maxMemoryBytes = 25 * 1024 * 1024;
      var calculatedDepth =
          (maxMemoryBytes / frameSize).floor().clamp(1, frameQueueMaxDepth);
      _decodePolicy = PreviewDecodePolicy.fromProbe(
        mediaInfo: info,
        hwPreviewDisabled: _hwPreviewDisabled,
      );
      if (_decodePolicy!.useSoftwareRgba) {
        calculatedDepth = calculatedDepth.clamp(4, 6);
      }
      final droppedDepth = _frameQueue.updateMaxDepth(calculatedDepth);
      for (final frame in droppedDepth) {
        _releasePreviewFrameResources(frame);
      }
      _scrubQueueMaxDepth = calculatedDepth;
      _adaptiveEdgeTier = 0;
      _slowDecodeStreak = 0;
      _fastDecodeStreak = 0;

      WidgetsBinding.instance.addObserver(this);

      _trimStartMs = 0;
      _trimEndMs = info.durationMs.toInt();
      _clock.reset();

      // Create persistent sequential decoder session
      _sessionPreviewEdge = _effectivePreviewMaxEdge;
      _session = VideoPreviewSession.create(
        inputPath: path,
        maxEdge: _sessionPreviewEdge,
        preferHw: !_hwPreviewDisabled && !_decodePolicy!.useSoftwareRgba,
      );

      await seekTo(Duration.zero);
    } catch (e) {
      _error = e.toString();
      _scrubLoading = false;
      _clock.state = PlaybackState.idle;
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
    // Cancel any in-flight scrub so its `finally` cannot pause us mid-playback.
    _seekGeneration++;
    _scrubLoading = false;
    _stopPlaybackLoop();

    _playbackMediaOriginMs = _clampPositionMs(_ptsMs);
    _playbackWallStart = DateTime.now();
    _clock.mediaTimeMs = _playbackMediaOriginMs;
    _clock.lastPresentedPtsMs = _playbackMediaOriginMs;
    _clock.startPlaying();
    _lastPlaybackFrameArrivalMs = null;

    _syncSessionPreviewEdge(playback: true);
    if (_needsReliableSwPreview) {
      for (final frame in _frameQueue.updateMaxDepth(2)) {
        _releasePreviewFrameResources(frame);
      }
    }

    final gen = ++_playGeneration;

    _startPlaybackPresenter(gen);

    try {
      final stream = _session!.startPlayback(rate: _clock.rate);
      _playbackSubscription = stream.listen(
        (frame) {
          if (gen != _playGeneration || _disposed || !_clock.isPlaying) {
            _releaseNativePlaybackFrame(frame);
            return;
          }
          final preview = _mapPlaybackFrame(frame);
          final now = DateTime.now().millisecondsSinceEpoch;
          if (_lastPlaybackFrameArrivalMs != null) {
            final interArrivalMs = now - _lastPlaybackFrameArrivalMs!;
            _onDecodeDuration(interArrivalMs);
            _metrics.recordPerformance(decodeMs: interArrivalMs);
          }
          _lastPlaybackFrameArrivalMs = now;
          final wallMs = _wallPlayheadMs;
          final enqueue = _frameQueue.enqueuePlayback(
            preview,
            minPtsMs: _clock.lastPresentedPtsMs,
            wallPlayheadMs: wallMs,
          );
          _releasePlaybackEnqueueDrops(enqueue, incoming: preview);
          _metrics.recordDroppedFrames(enqueue.totalDropped);
          _metrics.recordPerformance(
            queueDepth: _frameQueue.length,
            playbackDriftMs: wallMs - preview.ptsMs,
          );
        },
        onError: (e) {
          if (gen != _playGeneration || _disposed) return;
          _stopPlaybackLoop();
          _scrubLoading = false;
          _clock.state = PlaybackState.stalled;
          _error = e.toString();
          _notifyIfActive();
        },
        onDone: () async {
          if (gen != _playGeneration || _disposed) return;
          _scrubLoading = false;
          if (loopPlayback) {
            _flushQueueAndRelease();
            _clock.pause();
            try {
              await seekTo(Duration(milliseconds: _trimStartMs));
              if (!_disposed && _clock.state != PlaybackState.disposed) {
                await play();
              }
            } catch (_) {
              _scrubLoading = false;
              _notifyIfActive();
            }
          } else {
            _ptsMs = _trimEndMs;
            _clock.mediaTimeMs = _trimEndMs;
            _clock.state = PlaybackState.ended;
            _notifyIfActive();
          }
        },
        cancelOnError: true,
      );
    } catch (e) {
      _clock.state = PlaybackState.stalled;
      _notifyIfActive();
    }
    _notifyIfActive();
  }

  /// Pauses playback; position is retained at the wall-clock playhead.
  void pause() {
    if (_clock.isPlaying) {
      _ptsMs = _clock.mediaTimeMs;
    }
    _stopPlaybackLoop();
    _clock.pause();
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
    _clock.lastPresentedPtsMs = ms;
    _clock.state = PlaybackState.seeking;
    _notifyIfActive();
    await _decodeAndPresentScrub(ms);
  }

  /// Debounced scrub for UI playhead drags — stops playback first.
  void scheduleScrub(Duration position) {
    if (_inputPath == null || _disposed) return;
    _stopPlaybackLoop();
    _pendingScrubMs = _clampPositionMs(position.inMilliseconds);
    _scrubDebounceTimer?.cancel();

    // Coalesce rapid seek requests into the latest one
    _scrubDebounceTimer = Timer(_effectiveScrubDebounce, () {
      final ms = _pendingScrubMs;
      if (ms == null || _disposed) return;
      _scrubStartedAtMs = DateTime.now().millisecondsSinceEpoch;
      _clock.mediaTimeMs = ms;
      _clock.lastPresentedPtsMs = ms;
      _clock.state = PlaybackState.seeking;
      _notifyIfActive();
      unawaited(_decodeAndPresentScrub(ms));
    });
  }

  int _clampPositionMs(int positionMs) =>
      positionMs.clamp(_trimStartMs, _trimEndMs);

  void _stopPlaybackLoop() {
    _playGeneration++;
    _playbackPresentTimer?.cancel();
    _playbackPresentTimer = null;
    _playbackPresentInFlight = false;
    _playbackWallStart = null;
    // Stop Rust worker before closing the Dart stream (avoids FRB "Fail to post message to Dart").
    _session?.pausePlayback();
    final sub = _playbackSubscription;
    _playbackSubscription = null;
    if (sub != null) {
      Future.microtask(sub.cancel);
    }
    _flushQueueAndRelease();
    final restoreDepth = _scrubQueueMaxDepth;
    if (restoreDepth != null && _frameQueue.maxDepth != restoreDepth) {
      for (final frame in _frameQueue.updateMaxDepth(restoreDepth)) {
        _releasePreviewFrameResources(frame);
      }
    }
  }

  /// Wall-clock media position during [play] (UI playhead); clamped to trim range.
  int get _wallPlayheadMs {
    if (!_clock.isPlaying || _playbackWallStart == null) {
      return _clock.mediaTimeMs;
    }
    final elapsedMs =
        DateTime.now().difference(_playbackWallStart!).inMilliseconds;
    final pos =
        (_playbackMediaOriginMs + elapsedMs * _clock.rate).round();
    return _clampPositionMs(pos);
  }

  void _tickWallClockPlayhead() {
    if (!_clock.isPlaying || _disposed) return;
    _clock.mediaTimeMs = _wallPlayheadMs;
    _ptsMs = _wallPlayheadMs;
    _metrics.recordPerformance(
      playbackDriftMs: _wallPlayheadMs - _clock.lastPresentedPtsMs,
    );
    _notifyIfActive();
  }

  void _startPlaybackPresenter(int gen) {
    _playbackPresentTimer?.cancel();
    final ms = (1000 / targetPreviewFps).round().clamp(16, 50);
    _playbackPresentTimer = Timer.periodic(Duration(milliseconds: ms), (_) {
      if (gen != _playGeneration || _disposed || !_clock.isPlaying) return;
      _tickWallClockPlayhead();
      unawaited(_drainPlaybackPresenter(gen));
    });
  }

  void _releasePlaybackEnqueueDrops(
    PlaybackEnqueueResult result, {
    required PreviewFrame incoming,
  }) {
    for (final frame in result.dropped) {
      _releasePreviewFrameResources(frame);
    }
    if (result.rejectedIncoming) {
      _releasePreviewFrameResources(incoming);
    }
  }

  Future<void> _drainPlaybackPresenter(int gen) async {
    if (_playbackPresentInFlight || gen != _playGeneration || _disposed) {
      return;
    }
    final snap = _frameQueue.takeLatestForPlayback();
    for (final dropped in snap.dropped) {
      _releasePreviewFrameResources(dropped);
      _metrics.recordDroppedFrames(1);
    }
    final preview = snap.frame;
    if (preview == null) return;

    _playbackPresentInFlight = true;
    try {
      final ok = await _presentFrame(preview, wasScrub: false);
      if (ok && gen == _playGeneration && !_disposed) {
        _clock.advanceToFramePts(preview.ptsMs);
        final drift = _wallPlayheadMs - preview.ptsMs;
        _metrics.recordPerformance(
          frameAgeMs: drift,
          playbackDriftMs: drift,
          queueDepth: _frameQueue.length,
        );
        _notifyIfActive();
      } else if (!ok) {
        _releasePreviewFrameResources(preview);
      }
    } finally {
      _playbackPresentInFlight = false;
    }
  }

  void _onDecodeDuration(int decodeMs) {
    if (!_needsReliableSwPreview || decodeMs <= 0) return;
    final prevTier = _adaptiveEdgeTier;
    if (decodeMs > 150) {
      _slowDecodeStreak++;
      _fastDecodeStreak = 0;
      if (_slowDecodeStreak >= 1 &&
          _adaptiveEdgeTier < _adaptivePreviewEdges.length - 1) {
        _adaptiveEdgeTier++;
        _slowDecodeStreak = 0;
      }
    } else if (decodeMs < 70) {
      _slowDecodeStreak = 0;
      _fastDecodeStreak++;
      if (_fastDecodeStreak >= 5 && _adaptiveEdgeTier > 0) {
        _adaptiveEdgeTier--;
        _fastDecodeStreak = 0;
      }
    } else {
      _fastDecodeStreak = 0;
    }
    if (_adaptiveEdgeTier != prevTier) {
      _syncSessionPreviewEdge(playback: _clock.isPlaying);
    }
  }

  PreviewFrame _mapPlaybackFrame(PlaybackFrame frame) {
    return switch (frame) {
      PlaybackFrame_Rgba(:final field0) => PreviewFrame(
          ptsMs: field0.ptsMs.toInt(),
          width: field0.width,
          height: field0.height,
          rgba: field0.rgba,
        ),
      PlaybackFrame_PixelBuffer(:final field0) => PreviewFrame(
          ptsMs: field0.ptsMs.toInt(),
          width: field0.width,
          height: field0.height,
          pixelBufferPtr: field0.pixelBufferPtr.toInt(),
        ),
    };
  }

  void _releaseNativePlaybackFrame(PlaybackFrame frame) {
    switch (frame) {
      case PlaybackFrame_Rgba(:final field0):
        VideoProcessor.releaseBuffer(field0.rgba);
        break;
      case PlaybackFrame_PixelBuffer(:final field0):
        VideoProcessor.releasePreviewPixelBuffer(field0.pixelBufferPtr.toInt());
        break;
    }
  }

  Future<void> _decodeAndPresentScrub(int positionMs) async {
    final gen = ++_seekGeneration;
    _scrubStartedAtMs ??= DateTime.now().millisecondsSinceEpoch;
    _flushQueueAndRelease();
    _scrubLoading = true;
    _error = null;
    _notifyIfActive();

    try {
      final frame = await _decodeFrame(positionMs).timeout(
        _scrubDecodeTimeout,
        onTimeout: () {
          throw TimeoutException(
            'Preview decode timed out after ${_scrubDecodeTimeout.inSeconds}s',
            _scrubDecodeTimeout,
          );
        },
      );
      if (_disposed || gen != _seekGeneration) {
        if (frame != null) {
          _releasePreviewFrameResources(frame);
        }
        return;
      }
      if (frame != null) {
        final dropped = _frameQueue.enqueue(frame);
        if (dropped != null) {
          _releasePreviewFrameResources(dropped);
        }
        await _presentLatest(gen, advanceClock: true);
      } else {
        _error = 'Could not decode preview frame';
      }
    } catch (e) {
      if (_disposed || gen != _seekGeneration) return;
      _error = e.toString();
    } finally {
      if (!_disposed && gen == _seekGeneration) {
        _scrubLoading = false;
        // Only leave seek state when we were actually seeking (not superseded by play()).
        if (_clock.state == PlaybackState.seeking) {
          _clock.state = PlaybackState.paused;
        }
        _notifyIfActive();
      }
    }
  }

  bool get _hwPreviewDisabled {
    final v = Platform.environment['VFP_DISABLE_HW_PREVIEW'];
    return v == '1' || v == 'true' || v == 'yes';
  }

  /// CPU-bound / VT-unreliable assets (HEVC, Dolby Vision).
  bool get _needsReliableSwPreview => _decodePolicy?.useSoftwareRgba ?? false;

  bool get _preferApplePixelBufferPreview =>
      isTexturePreviewAvailable && (_decodePolicy?.useHwPixelBuffer ?? false);

  /// Shorter debounce + lower resolution for CPU-bound iPhone HEVC scrub.
  Duration get _effectiveScrubDebounce =>
      _needsReliableSwPreview ? const Duration(milliseconds: 100) : scrubDebounce;

  int get _effectivePreviewMaxEdge {
    if (!_needsReliableSwPreview) return previewMaxEdge;
    final cap = _adaptivePreviewEdges[_adaptiveEdgeTier];
    return previewMaxEdge < cap ? previewMaxEdge : cap;
  }

  int get _effectivePlaybackMaxEdge {
    if (!_needsReliableSwPreview) return previewMaxEdge;
    final tier = _adaptivePreviewEdges[_adaptiveEdgeTier];
    final playCap = playbackPreviewMaxEdge < tier
        ? playbackPreviewMaxEdge
        : tier;
    return previewMaxEdge < playCap ? previewMaxEdge : playCap;
  }

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
    if (_session == null) return null;
    final frame = await _session!.seekAndDecodeRgba(
      positionMs: BigInt.from(positionMs),
    );
    return frame.rgba;
  }

  Future<PreviewFrame?> _decodeFrame(int positionMs) async {
    final path = _inputPath;
    if (path == null) return null;

    _syncSessionPreviewEdge();

    final decodeStopwatch = Stopwatch()..start();
    try {
      return await _decodeFrameInner(path, positionMs);
    } finally {
      final decodeMs = decodeStopwatch.elapsedMilliseconds;
      _metrics.recordPerformance(decodeMs: decodeMs);
      _onDecodeDuration(decodeMs);
    }
  }

  void _syncSessionPreviewEdge({bool playback = false}) {
    if (_session == null || !_needsReliableSwPreview) return;
    final edge =
        playback ? _effectivePlaybackMaxEdge : _effectivePreviewMaxEdge;
    if (_sessionPreviewEdge == edge) return;
    _sessionPreviewEdge = edge;
    try {
      _session!.setPreviewMaxEdge(maxEdge: edge);
    } catch (e, st) {
      debugPrint('MediaRuntime: setPreviewMaxEdge failed: $e\n$st');
    }
  }

  Future<PreviewFrame?> _decodeFrameInner(String path, int positionMs) async {
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
          maxEdge: _effectivePreviewMaxEdge,
        );
        if (surface != null) {
          return PreviewFrame(
            ptsMs: surface.ptsMs,
            width: surface.width,
            height: surface.height,
            presentedToSurface: true,
          );
        }
      } catch (e, st) {
        debugPrint('MediaRuntime: Android surface preview failed: $e\n$st');
      }
    }

    if (_session == null) return null;

    if (_preferApplePixelBufferPreview) {
      try {
        final hw = await _session!.seekAndDecodePixelBuffer(
          positionMs: BigInt.from(positionMs),
        );
        final ptr = hw.pixelBufferPtr.toInt();
        if (ptr > 0) {
          _decodePolicy?.decodePath = PreviewDecodePath.hwPixelBuffer;
          return PreviewFrame(
            ptsMs: hw.ptsMs.toInt(),
            width: hw.width,
            height: hw.height,
            pixelBufferPtr: ptr,
          );
        }
      } catch (e) {
        _decodePolicy?.lockSoftwareRgba();
        if (kDebugMode && !PreviewDecodePolicy.isRgbaRedirectError(e)) {
          debugPrint('MediaRuntime: HW preview unavailable, using RGBA: $e');
        }
      }
    }

    final frame = await _session!.seekAndDecodeRgba(
      positionMs: BigInt.from(positionMs),
    );

    return PreviewFrame(
      ptsMs: frame.ptsMs.toInt(),
      width: frame.width,
      height: frame.height,
      rgba: frame.rgba,
    );
  }

  Future<bool> _presentFrame(
    PreviewFrame preview, {
    bool wasScrub = true,
  }) async {
    if (_disposed) return false;

    final uploadStopwatch = Stopwatch()..start();
    final texId = await _texturePool.ensureTexture(
      width: preview.width,
      height: preview.height,
    );
    if (_disposed) return false;

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
              VideoProcessor.releaseBuffer(preview.rgba!);
            } else {
              final fallback = await _decodeFrameRgbaAt(preview.ptsMs);
              if (fallback != null) {
                await _texturePool.presentRgba(fallback);
                VideoProcessor.releaseBuffer(fallback);
              }
            }
          }
        } else if (preview.rgba != null) {
          await _texturePool.presentRgba(preview.rgba!);
          VideoProcessor.releaseBuffer(preview.rgba!);
        }
      }
    } else {
      _fallbackRgba = preview.rgba;
    }

    _metrics.recordPerformance(uploadMs: uploadStopwatch.elapsedMilliseconds);
    _metrics.recordPerformance(queueDepth: _frameQueue.length);

    if (wasScrub) {
      _scrubLoading = false;
    }
    _recordPresentedFrame(
      wasScrub: wasScrub && _clock.state == PlaybackState.seeking,
      preview: preview,
    );
    return true;
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
      _clock.mediaTimeMs = preview.ptsMs;
    }
    _ptsMs = preview.ptsMs;

    final ok = await _presentFrame(preview, wasScrub: true);
    _notifyIfActive();
    return ok;
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
      try {
        WidgetsBinding.instance.removeObserver(this);
      } catch (_) {}
      _stopPlaybackLoop();
      _scrubDebounceTimer?.cancel();
      _scrubDebounceTimer = null;
      _pendingScrubMs = null;
      _seekGeneration++;
      _flushQueueAndRelease();
      _inputPath = null;
      _mediaInfo = null;
      _fallbackRgba = null;
      _ptsMs = 0;
      _scrubLoading = false;
      _error = null;
      _clock.reset();
      _decodePolicy = null;

      if (_session != null) {
        _session!.close();
        _session = null;
      }

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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) return;
    if (state == AppLifecycleState.paused) {
      if (isPlaying) {
        pause();
      }
      _stopPlaybackLoop();
      _flushQueueAndRelease();
      if (_session != null) {
        _session!.close();
        _session = null;
      }
      _texturePool.release();
    } else if (state == AppLifecycleState.resumed) {
      final path = _inputPath;
      if (path != null) {
        _clock.state = PlaybackState.opening;
        _notifyIfActive();
        try {
          final info = _mediaInfo;
          if (info != null) {
            _decodePolicy = PreviewDecodePolicy.fromProbe(
              mediaInfo: info,
              hwPreviewDisabled: _hwPreviewDisabled,
            );
          }
          _session = VideoPreviewSession.create(
            inputPath: path,
            maxEdge: _effectivePreviewMaxEdge,
            preferHw: !_hwPreviewDisabled &&
                !(_decodePolicy?.useSoftwareRgba ?? true),
          );
          seekTo(Duration(milliseconds: _ptsMs));
        } catch (e) {
          _error = e.toString();
          _notifyIfActive();
        }
      }
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    try {
      WidgetsBinding.instance.removeObserver(this);
    } catch (_) {}
    _scrubDebounceTimer?.cancel();
    _scrubDebounceTimer = null;
    _stopPlaybackLoop();
    unawaited(close());
    super.dispose();
  }
}
