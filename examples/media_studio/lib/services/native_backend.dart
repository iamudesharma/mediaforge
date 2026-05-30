import 'dart:async';

import 'package:flutter_video_processor/flutter_video_processor.dart';

import 'playback_backend.dart';

/// Wraps the existing [NativePlaybackController] (video_player plugin)
/// behind the [PlaybackBackend] interface.
///
/// This preserves the current behavior exactly — no logic changes.
class NativeBackend extends PlaybackBackend {
  NativeBackend({this.loopPlayback = true});

  final bool loopPlayback;

  NativePlaybackController? _controller;

  NativePlaybackController? get controller => _controller;

  void _onControllerUpdate() {
    if (!_disposed) notifyListeners();
  }

  // ── PlaybackBackend ──

  @override
  Future<void> open(String path) async {
    await close();
    _controller = NativePlaybackController(loopPlayback: loopPlayback);
    _controller!.addListener(_onControllerUpdate);
    await _controller!.open(path);
    notifyListeners();
  }

  @override
  Future<void> close() async {
    final c = _controller;
    _controller = null;
    if (c != null) {
      c.removeListener(_onControllerUpdate);
      await c.close();
      c.dispose();
    }
    notifyListeners();
  }

  @override
  Future<void> play() async {
    await _controller?.play();
  }

  @override
  void pause() {
    _controller?.pause();
  }

  @override
  Future<void> seekTo(Duration position) async {
    await _controller?.seekTo(position);
  }

  @override
  void setTrimRange({int? startMs, int? endMs}) {
    _controller?.setTrimRange(startMs: startMs, endMs: endMs);
  }

  @override
  Future<void> setEmbeddedAudioMuted(bool muted) async {
    await _controller?.setEmbeddedAudioMuted(muted);
  }

  @override
  Future<void> setPlaybackRate(double rate) async {
    await _controller?.setPlaybackRate(rate);
  }

  @override
  bool get isOpen => _controller?.isOpen ?? false;

  @override
  bool get isPlaying => _controller?.isPlaying ?? false;

  @override
  int get positionMs => _controller?.positionMs ?? 0;

  @override
  int get durationMs => _controller?.durationMs ?? 0;

  @override
  MediaInfo? get mediaInfo => _controller?.mediaInfo;

  @override
  double get aspectRatio => _controller?.aspectRatio ?? (16 / 9);

  @override
  int get previewWidth => _controller?.previewWidth ?? 0;

  @override
  int get previewHeight => _controller?.previewHeight ?? 0;

  // ── Lifecycle ──

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    close();
    super.dispose();
  }
}
