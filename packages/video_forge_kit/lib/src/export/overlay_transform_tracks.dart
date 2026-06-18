import 'package:video_forge/video_forge.dart' as vf;
import 'package:video_forge_kit/src/compositor/video_text_overlay_style.dart';
import 'package:video_forge_kit/src/compositor/video_text_presets.dart';

/// Builds [vf.TransformTracks] for Category 1 export animations (transform-only).
///
/// Category 2 content animations use [vf.TextContentAnimation] on [vf.TextOverlayData].
/// Glitch / glow use [vf.OverlayEffects] (v3).
class OverlayTransformTracks {
  OverlayTransformTracks._();

  static const _category1Animations = {
    VideoTextAnimation.none,
    VideoTextAnimation.popIn,
    VideoTextAnimation.bounce,
    VideoTextAnimation.fadeScale,
    VideoTextAnimation.slideIn,
  };

  static bool isExportAnimated(VideoTextAnimation animation) =>
      _category1Animations.contains(animation);

  static vf.TransformTracks forOverlay({
    required VideoTextOverlayStyle style,
    required int fadeInMs,
    required int fadeOutMs,
    required int visibleDurationMs,
  }) {
    final tracks = <vf.AnimationTrack>[];

    if (fadeInMs > 0) {
      tracks.add(_opacity(0, 1, 0, fadeInMs, vf.Easing.linear));
    }
    if (fadeOutMs > 0 && visibleDurationMs > fadeOutMs) {
      final start = visibleDurationMs - fadeOutMs;
      tracks.add(_opacity(1, 0, start, fadeOutMs, vf.Easing.linear));
    }

    if (isExportAnimated(style.animation)) {
      tracks.addAll(_entranceTracks(style));
    }

    return vf.TransformTracks(tracks: tracks);
  }

  static List<vf.AnimationTrack> _entranceTracks(VideoTextOverlayStyle style) {
    final scale = style.animationDurationScale.clamp(0.35, 2.5);
    return switch (style.animation) {
      VideoTextAnimation.fadeScale => [
          _opacity(0, 1, 0, _ms(380, scale), vf.Easing.easeOut),
          _scale(0.85, 1, 0, _ms(380, scale), vf.Easing.easeOut),
        ],
      VideoTextAnimation.popIn => [
          _opacity(0, 1, 0, _ms(420, scale), vf.Easing.easeOut),
          _scale(0, 1, 0, _ms(420, scale), vf.Easing.easeOut),
        ],
      VideoTextAnimation.bounce => [
          _scale(0, 1, 0, _ms(450, scale), vf.Easing.bounce),
        ],
      VideoTextAnimation.slideIn => [
          _opacity(0, 1, 0, _ms(450, scale), vf.Easing.easeOut),
          _translateX(-0.15, 0, 0, _ms(450, scale), vf.Easing.easeOut),
        ],
      VideoTextAnimation.typewriter ||
      VideoTextAnimation.glitch ||
      VideoTextAnimation.none =>
        const [],
    };
  }

  static int _ms(int base, double scale) =>
      (base / scale).round().clamp(80, 4000);

  static vf.AnimationTrack _opacity(
    double from,
    double to,
    int startMs,
    int durationMs,
    vf.Easing easing,
  ) =>
      vf.AnimationTrack(
        property: vf.TransformProperty.opacity,
        from: from,
        to: to,
        startMs: BigInt.from(startMs),
        durationMs: BigInt.from(durationMs),
        easing: easing,
      );

  static vf.AnimationTrack _scale(
    double from,
    double to,
    int startMs,
    int durationMs,
    vf.Easing easing,
  ) =>
      vf.AnimationTrack(
        property: vf.TransformProperty.scale,
        from: from,
        to: to,
        startMs: BigInt.from(startMs),
        durationMs: BigInt.from(durationMs),
        easing: easing,
      );

  static vf.AnimationTrack _translateX(
    double from,
    double to,
    int startMs,
    int durationMs,
    vf.Easing easing,
  ) =>
      vf.AnimationTrack(
        property: vf.TransformProperty.translateX,
        from: from,
        to: to,
        startMs: BigInt.from(startMs),
        durationMs: BigInt.from(durationMs),
        easing: easing,
      );
}
