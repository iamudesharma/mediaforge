/// Playback state for [MediaRuntime] decoder-clock preview (V1.3).
enum PlaybackState {
  idle,
  opening,
  buffering,
  playing,
  paused,
  seeking,
  stalled,
  ended,
  disposed,
}

/// Media timeline driven by decoded frame PTS, not a UI [Timer].
final class PlaybackClock {
  PlaybackState state = PlaybackState.idle;

  /// Current position on the media timeline (milliseconds).
  ///
  /// During playback this follows the wall-clock playhead; [lastPresentedPtsMs]
  /// tracks the PTS of the last texture presented.
  int mediaTimeMs = 0;

  /// PTS of the last frame uploaded to the preview texture.
  int lastPresentedPtsMs = 0;

  /// Playback speed multiplier (1.0 = normal).
  double rate = 1.0;

  bool get isPlaying => state == PlaybackState.playing;
  bool get isPaused => state == PlaybackState.paused;

  void reset({int mediaTimeMs = 0}) {
    state = PlaybackState.idle;
    this.mediaTimeMs = mediaTimeMs;
    lastPresentedPtsMs = mediaTimeMs;
    rate = 1.0;
  }

  void pause() {
    if (state == PlaybackState.playing) {
      state = PlaybackState.paused;
    }
  }

  void startPlaying() {
    state = PlaybackState.playing;
  }

  /// After a frame is displayed, record its PTS (wall playhead stays independent).
  void advanceToFramePts(int ptsMs) {
    lastPresentedPtsMs = ptsMs;
  }

  /// Schedule the next decode target along the timeline.
  void advanceByStep(int stepMs) {
    mediaTimeMs += stepMs;
  }
}
