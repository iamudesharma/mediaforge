import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:video_forge_kit/video_forge_kit.dart';

/// Common interface for video playback backends.
///
/// The video editor uses [RustPlaybackBackend] backed by
/// `media_forge` (FFmpeg demux + HW decode + cpal real-time audio mixing).
/// The interface is kept abstract so the same call sites can be exercised
/// from tests with a fake backend if needed.
abstract class PlaybackBackend extends ChangeNotifier {
  /// Open a video file for playback.
  Future<void> open(String path);

  /// Close the current video and release resources.
  Future<void> close();

  /// Start or resume playback.
  Future<void> play();

  /// Pause playback.
  void pause();

  /// Seek to [position].
  Future<void> seekTo(Duration position);

  /// Set the trim range (start/end in milliseconds from file start).
  void setTrimRange({int? startMs, int? endMs});

  /// Mute or restore embedded video audio.
  Future<void> setEmbeddedAudioMuted(bool muted);

  /// Set playback rate (speed).
  Future<void> setPlaybackRate(double rate);

  // ── Read-only state ──

  bool get isOpen;

  bool get isPlaying;

  /// Current playback position in milliseconds.
  int get positionMs;

  /// Total duration in milliseconds.
  int get durationMs;

  /// Media metadata (codec, resolution, etc.).
  MediaInfo? get mediaInfo;

  /// Video aspect ratio (width / height).
  double get aspectRatio;

  int get previewWidth;

  int get previewHeight;
}
