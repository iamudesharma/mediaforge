import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import '../video_processor.dart';
import 'native_playback_trim.dart';

/// Native-first playback (AVPlayer / ExoPlayer via [video_player]).
///
/// Use for smooth preview watching and timeline play. Pair with
/// [VideoProcessor] for thumbnails, frame extraction, and export.
class NativePlaybackController extends ChangeNotifier {
  NativePlaybackController({
    this.loopPlayback = false,
    this.muteVideoAudio = false,
  });

  /// When true, reaching trim end seeks to [trimStartMs] and resumes play.
  final bool loopPlayback;

  /// Mute embedded video audio (e.g. when syncing separate audio tracks).
  final bool muteVideoAudio;

  VideoPlayerController? _controller;
  String? _path;
  MediaInfo? _mediaInfo;
  bool _disposed = false;

  int _trimStartMs = 0;
  int _trimEndMs = 0;

  void Function()? _positionListener;

  VideoPlayerController? get controller => _controller;

  String? get path => _path;

  MediaInfo? get mediaInfo => _mediaInfo;

  bool get isOpen => _controller != null && _controller!.value.isInitialized;

  bool get isPlaying => _controller?.value.isPlaying ?? false;

  bool get isInitialized => _controller?.value.isInitialized ?? false;

  int get positionMs => _controller?.value.position.inMilliseconds ?? 0;

  int get durationMs =>
      _mediaInfo?.durationMs.toInt() ??
      _controller?.value.duration.inMilliseconds ??
      0;

  int get trimStartMs => _trimStartMs;

  int get trimEndMs => _trimEndMs;

  double get aspectRatio {
    if (!isInitialized) return 16 / 9;
    final size = _controller!.value.size;
    if (size.width <= 0 || size.height <= 0) {
      return 16 / 9;
    }
    return size.width / size.height;
  }

  int get previewWidth => _mediaInfo?.width ?? _controller?.value.size.width.toInt() ?? 0;

  int get previewHeight =>
      _mediaInfo?.height ?? _controller?.value.size.height.toInt() ?? 0;

  VideoPlayerValue? get value => _controller?.value;

  /// Opens [path], probes via [VideoProcessor], and shows the first frame at trim start.
  Future<void> open(String path) async {
    await close();
    _path = path;
    await VideoProcessor.initialize();
    _mediaInfo = await VideoProcessor.getMediaInfo(path);

    final controller = VideoPlayerController.file(
      File(path),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    _controller = controller;
    _attachPositionListener();

    await controller.initialize();
    final dur = _mediaInfo!.durationMs.toInt();
    _trimStartMs = 0;
    _trimEndMs = dur > 0 ? dur : 1;
    await controller.setVolume(muteVideoAudio ? 0 : 1);
    await controller.seekTo(Duration(milliseconds: _trimStartMs));
    await controller.pause();
    debugPrint(
      '[NativePlayback] open path=$path duration=${durationMs}ms '
      'audio=${_mediaInfo?.audioCodec ?? "none"} muted=$muteVideoAudio',
    );
    _notify();
  }

  void setTrimRange({int? startMs, int? endMs}) {
    if (_mediaInfo == null) return;
    final dur = _mediaInfo!.durationMs.toInt();
    _trimStartMs = (startMs ?? _trimStartMs).clamp(0, dur);
    _trimEndMs = (endMs ?? _trimEndMs).clamp(_trimStartMs, dur);
    final pos = positionMs;
    if (pos > _trimEndMs) {
      unawaited(seekTo(Duration(milliseconds: _trimEndMs)));
    }
    _notify();
  }

  Future<void> play() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _disposed) return;

    var pos = positionMs;
    if (pos >= _trimEndMs - 50) {
      await seekTo(Duration(milliseconds: _trimStartMs));
      pos = _trimStartMs;
    } else if (pos < _trimStartMs) {
      await seekTo(Duration(milliseconds: _trimStartMs));
    }
    await c.play();
    debugPrint(
      '[NativePlayback] play path=$_path pos=${positionMs}ms '
      'trim=$_trimStartMs-$_trimEndMs playing=${c.value.isPlaying}',
    );
    _notify();
  }

  void pause() {
    _controller?.pause();
    _notify();
  }

  Future<void> seekTo(Duration position) async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;

    final dur = durationMs;
    final ms = clampSeekMs(
      requestedMs: position.inMilliseconds,
      startMs: _trimStartMs,
      endMs: _trimEndMs,
      durationMs: dur > 0 ? dur : null,
    );
    await c.seekTo(Duration(milliseconds: ms));
    _notify();
  }

  /// Seek to [sourceMs] in the opened file (editor timeline mapping).
  Future<void> seekToSourceMs(int sourceMs) async {
    await seekTo(Duration(milliseconds: sourceMs));
  }

  /// Mute or restore embedded video audio (e.g. when syncing separate tracks).
  Future<void> setEmbeddedAudioMuted(bool muted) async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    await c.setVolume(muted ? 0 : 1);
    debugPrint('[NativePlayback] volume path=$_path muted=$muted');
  }

  Future<void> close() async {
    _detachPositionListener();
    final c = _controller;
    _controller = null;
    _path = null;
    _mediaInfo = null;
    if (c != null) {
      await c.dispose();
    }
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(close());
    super.dispose();
  }

  void _attachPositionListener() {
    _detachPositionListener();
    final c = _controller;
    if (c == null) return;
    void onTick() {
      if (_disposed || !c.value.isInitialized) return;
      final pos = c.value.position.inMilliseconds;
      if (shouldPauseAtTrimEnd(
        positionMs: pos,
        endMs: _trimEndMs,
        isPlaying: c.value.isPlaying,
        loopPlayback: loopPlayback,
      )) {
        unawaited(_handleTrimEnd());
        return;
      }
      _notify();
    }

    _positionListener = onTick;
    c.addListener(onTick);
  }

  void _detachPositionListener() {
    final c = _controller;
    final listener = _positionListener;
    if (c != null && listener != null) {
      c.removeListener(listener);
    }
    _positionListener = null;
  }

  Future<void> _handleTrimEnd() async {
    final c = _controller;
    if (c == null || _disposed) return;
    if (loopPlayback) {
      await seekTo(Duration(milliseconds: _trimStartMs));
      if (!_disposed && isOpen) {
        await c.play();
      }
    } else {
      await c.pause();
      await seekTo(Duration(milliseconds: _trimEndMs));
    }
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}
