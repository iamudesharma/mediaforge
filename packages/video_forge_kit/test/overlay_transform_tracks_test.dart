import 'package:flutter_test/flutter_test.dart';
import 'package:video_forge/video_forge.dart' as vf;
import 'package:video_forge_kit/src/compositor/video_text_overlay_style.dart';
import 'package:video_forge_kit/src/compositor/video_text_presets.dart';
import 'package:video_forge_kit/src/export/overlay_transform_tracks.dart';

void main() {
  test('bounce produces scale track', () {
    final tracks = OverlayTransformTracks.forOverlay(
      style: VideoTextOverlayStyle.defaults.copyWith(
        animation: VideoTextAnimation.bounce,
      ),
      fadeInMs: 0,
      fadeOutMs: 0,
      visibleDurationMs: 5000,
    );
    expect(
      tracks.tracks.any((t) => t.property == vf.TransformProperty.scale),
      isTrue,
    );
  });

  test('typewriter is not transform-animated', () {
    expect(
      OverlayTransformTracks.isExportAnimated(VideoTextAnimation.typewriter),
      isFalse,
    );
    final tracks = OverlayTransformTracks.forOverlay(
      style: VideoTextOverlayStyle.defaults.copyWith(
        animation: VideoTextAnimation.typewriter,
      ),
      fadeInMs: 0,
      fadeOutMs: 0,
      visibleDurationMs: 3000,
    );
    expect(tracks.tracks, isEmpty);
  });

  test('fade in adds opacity track', () {
    final tracks = OverlayTransformTracks.forOverlay(
      style: VideoTextOverlayStyle.defaults.copyWith(
        animation: VideoTextAnimation.none,
      ),
      fadeInMs: 300,
      fadeOutMs: 0,
      visibleDurationMs: 5000,
    );
    final opacity = tracks.tracks
        .where((t) => t.property == vf.TransformProperty.opacity)
        .toList();
    expect(opacity, hasLength(1));
    expect(opacity.first.from, 0);
    expect(opacity.first.to, 1);
  });
}
