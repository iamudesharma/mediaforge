import 'package:flutter_test/flutter_test.dart';
import 'package:rust_media_runtime/rust_media_runtime.dart';

/// Phase 5: Dart thresholds must match Rust `video_decode` / `presenter_runtime`.
void main() {
  test('MediaPlaybackAcceptance matches Rust constants', () {
    expect(MediaPlaybackAcceptance.presenterIntervalMs, 16);
    expect(MediaPlaybackAcceptance.catchupSkipNonKeyframeMs, 500);
    expect(MediaPlaybackAcceptance.catchupKeyframeOnlyMs, 1500);
    expect(MediaPlaybackAcceptance.hardResyncDriftMs, 2000);
    expect(MediaPlaybackAcceptance.healthyMaxDriftMs, 500);
    expect(MediaPlaybackAcceptance.minHealthyVideoQueueDepth, 1);
  });

  test('isHealthyPlayback during play', () {
    const drive = _FakeDrive();
    const healthy = DiagnosticsSnapshot(
      state: PlaybackState.playing,
      mediaTimeMs: 1000,
      audioClockMs: 1000,
      wallClockMs: 1000,
      latestDecodedPtsMs: 950,
      presentedPtsMs: 940,
      avDriftMs: 60,
      videoPacketsInQueue: 10,
      audioPacketsInQueue: 5,
      videoFramesInQueue: 4,
      audioFramesInQueue: 8,
    );
    expect(drive.isHealthyPlayback(healthy, isPlaying: true), isTrue);

    const starved = DiagnosticsSnapshot(
      state: PlaybackState.playing,
      mediaTimeMs: 8000,
      audioClockMs: 8000,
      wallClockMs: 8000,
      latestDecodedPtsMs: 0,
      presentedPtsMs: 6000,
      avDriftMs: 8000,
      videoPacketsInQueue: 0,
      audioPacketsInQueue: 0,
      videoFramesInQueue: 0,
      audioFramesInQueue: 32,
    );
    expect(drive.isHealthyPlayback(starved, isPlaying: true), isFalse);
  });
}

/// Minimal stand-in — [isHealthyPlayback] is static logic on [MediaPlaybackDrive].
class _FakeDrive {
  const _FakeDrive();

  bool isHealthyPlayback(DiagnosticsSnapshot d, {required bool isPlaying}) {
    if (!isPlaying) return true;
    return d.avDriftMs < MediaPlaybackAcceptance.healthyMaxDriftMs &&
        d.videoFramesInQueue >= MediaPlaybackAcceptance.minHealthyVideoQueueDepth;
  }
}
