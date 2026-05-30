import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_video_processor/flutter_video_processor.dart'
    show MediaInfo, VideoProcessor;
import 'package:rust_media_runtime/rust_media_runtime.dart'
    hide PlaybackState;
import 'package:rust_media_runtime/rust_media_runtime.dart' as rust
    show PlaybackState;

import 'playback_backend.dart';

/// Wraps [MediaPlaybackEngine] (rust_media_runtime) behind [PlaybackBackend].
///
/// Uses FFmpeg demuxing + HW decode + cpal audio output in Rust.
/// Presents video frames via GPU texture (zero-copy on Apple).
class RustBackend extends PlaybackBackend {
  RustBackend({
    required this.textureHandle,
    this.previewMaxEdge = 720,
  });

  final int textureHandle;
  final int previewMaxEdge;

  MediaPlaybackEngine? _engine;
  MediaPlaybackPresenter? _presenter;
  MediaPlaybackDrive? _drive;
  DiagnosticsSnapshot? _lastDiagnostics;

  MediaPlaybackEngine? get engine => _engine;
  MediaPlaybackPresenter? get presenter => _presenter;
  MediaPlaybackDrive? get drive => _drive;
  DiagnosticsSnapshot? get lastDiagnostics => _lastDiagnostics;

  MediaInfo? _mediaInfo;
  bool _isPlaying = false;
  bool _disposed = false;
  int _trimEndMs = 0;

  Timer? _diagnosticsTimer;
  Timer? _presentationTimer;

  void _startTimers() {
    _diagnosticsTimer?.cancel();
    _diagnosticsTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _pollDiagnostics(),
    );
    _presentationTimer?.cancel();
    _presentationTimer = Timer.periodic(
      const Duration(milliseconds: 16),
      (_) => _presentationTick(),
    );
  }

  void _stopTimers() {
    _diagnosticsTimer?.cancel();
    _diagnosticsTimer = null;
    _presentationTimer?.cancel();
    _presentationTimer = null;
  }

  Future<void> _pollDiagnostics() async {
    final drive = _drive;
    if (drive == null || _disposed) return;
    try {
      final snap = await drive.diagnosticsTick();
      _lastDiagnostics = snap;
      if (!_disposed) notifyListeners();
    } catch (_) {}
  }

  Future<void> _presentationTick() async {
    final drive = _drive;
    if (drive == null || _disposed) return;
    try {
      await drive.presentationTick();
    } catch (_) {}
  }

  // ── PlaybackBackend ──

  @override
  Future<void> open(String path) async {
    await close();

    // Probe media info for resolution/codec display
    try {
      _mediaInfo = await VideoProcessor.getMediaInfo(path);
    } catch (_) {
      _mediaInfo = null;
    }

    // Create engine (textureId 0 is fine — GpuPresenter is a no-op;
    // actual presentation goes through MediaPlaybackPresenter → GpuTextureRegistry)
    final engine = await MediaPlaybackEngine.newInstance(
      textureId: 0,
      maxQueueSize: BigInt.from(2000),
      previewMaxEdge: previewMaxEdge,
    );
    _engine = engine;

    // Create presenter with the real texture handle for GPU upload
    _presenter = MediaPlaybackPresenter(textureHandle: textureHandle);
    _drive = MediaPlaybackDrive(
      engine: engine,
      presenter: _presenter!,
    );

    // Open file → starts demuxer thread
    await engine.openFile(path: path);

    // Set trim range to full duration
    final dur = await engine.getDurationMs();
    _trimEndMs = dur.toInt();

    _isPlaying = false;
    _startTimers();
    notifyListeners();
  }

  /// Switch to a different file (e.g. muxed preview) without recreating the engine.
  Future<void> reopenFile(String path) async {
    final engine = _engine;
    if (engine == null) return;

    try {
      await engine.stop();
      _isPlaying = false;

      // Probe new file info
      try {
        _mediaInfo = await VideoProcessor.getMediaInfo(path);
      } catch (_) {}

      // Open new file → starts demuxer thread
      await engine.openFile(path: path);

      // Update trim range to new duration
      final dur = await engine.getDurationMs();
      _trimEndMs = dur.toInt();

      notifyListeners();
    } catch (e) {
      debugPrint('[RustBackend] reopenFile failed: $e');
    }
  }

  @override
  Future<void> close() async {
    _stopTimers();
    final engine = _engine;
    final presenter = _presenter;
    _engine = null;
    _presenter = null;
    _drive = null;
    _mediaInfo = null;
    _isPlaying = false;
    _lastDiagnostics = null;

    if (engine != null) {
      try {
        await engine.stop();
      } catch (_) {}
    }
    try {
      presenter?.dispose();
    } catch (_) {}
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  Future<void> play() async {
    final engine = _engine;
    if (engine == null) return;
    try {
      await engine.start();
      _isPlaying = true;
      notifyListeners();
    } catch (e) {
      debugPrint('[RustBackend] play failed: $e');
    }
  }

  @override
  void pause() {
    final engine = _engine;
    if (engine == null) return;
    try {
      engine.pause();
      _isPlaying = false;
      notifyListeners();
    } catch (e) {
      debugPrint('[RustBackend] pause failed: $e');
    }
  }

  @override
  Future<void> seekTo(Duration position) async {
    final engine = _engine;
    if (engine == null) return;
    try {
      await engine.seek(timeMs: BigInt.from(position.inMilliseconds));
      _presenter?.onSeek();
    } catch (e) {
      debugPrint('[RustBackend] seek failed: $e');
    }
  }

  @override
  void setTrimRange({int? startMs, int? endMs}) {
    if (endMs != null) _trimEndMs = endMs;
    notifyListeners();
  }

  @override
  Future<void> setEmbeddedAudioMuted(bool muted) async {}

  @override
  bool get isOpen => _engine != null;

  @override
  bool get isPlaying => _isPlaying;

  @override
  int get positionMs => _lastDiagnostics?.mediaTimeMs ?? 0;

  @override
  int get durationMs {
    final d = _lastDiagnostics;
    if (d != null && d.state == rust.PlaybackState.idle) return 0;
    return _trimEndMs;
  }

  @override
  MediaInfo? get mediaInfo => _mediaInfo;

  @override
  double get aspectRatio {
    final info = _mediaInfo;
    if (info == null || info.width <= 0 || info.height <= 0) return 16 / 9;
    return info.width.toDouble() / info.height.toDouble();
  }

  @override
  int get previewWidth => _mediaInfo?.width ?? 0;

  @override
  int get previewHeight => _mediaInfo?.height ?? 0;

  // ── Lifecycle ──

  @override
  void dispose() {
    _disposed = true;
    _stopTimers();
    final engine = _engine;
    final presenter = _presenter;
    _engine = null;
    _presenter = null;
    _drive = null;
    if (engine != null) {
      engine.stop();
    }
    presenter?.dispose();
    super.dispose();
  }
}
