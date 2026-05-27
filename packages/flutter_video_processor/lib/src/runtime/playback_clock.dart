/// Playback state for [MediaRuntime] decoder-clock preview (V1.3).
enum PlaybackState {
  idle,
  playing,
  paused,
}

/// Media timeline driven by decoded frame PTS, not a UI [Timer].
final class PlaybackClock {
  PlaybackState state = PlaybackState.idle;

  /// Current position on the media timeline (milliseconds).
  int mediaTimeMs = 0;

  /// Playback speed multiplier (1.0 = normal).
  double rate = 1.0;

  bool get isPlaying => state == PlaybackState.playing;
  bool get isPaused => state == PlaybackState.paused;

  void reset({int mediaTimeMs = 0}) {
    state = PlaybackState.idle;
    this.mediaTimeMs = mediaTimeMs;
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

  /// After a frame is displayed, snap the clock to its decode PTS.
  void advanceToFramePts(int ptsMs) {
    mediaTimeMs = ptsMs;
  }

  /// Schedule the next decode target along the timeline.
  void advanceByStep(int stepMs) {
    mediaTimeMs += stepMs;
  }
}
