import 'dart:math' as math;

import 'package:flutter/material.dart' hide Easing, TransformProperty;
import 'package:video_forge_kit/video_forge_kit.dart';

/// Preview-time evaluation of [ClipEffects] at a timeline-local offset.
class ClipTransformPreview {
  ClipTransformPreview._();

  static ClipTransformBase atMs(ClipEffects effects, int localMs) {
    var scale = effects.base.scale;
    var translateX = effects.base.translateX;
    var translateY = effects.base.translateY;
    var rotation = effects.base.rotation;

    for (final track in effects.motion.tracks) {
      if (localMs < track.startMs.toInt()) continue;
      final value = _evalTrack(track, localMs);
      switch (track.property) {
        case TransformProperty.translateX:
          translateX += value;
        case TransformProperty.translateY:
          translateY += value;
        case TransformProperty.scale:
          scale *= value;
        case TransformProperty.rotation:
          rotation += value;
        case TransformProperty.opacity:
          break;
      }
    }

    return ClipTransformBase(
      translateX: translateX,
      translateY: translateY,
      scale: scale,
      rotation: rotation,
    );
  }

  static double _evalTrack(AnimationTrack track, int localMs) {
    final start = track.startMs.toInt();
    final duration = track.durationMs.toInt();
    if (duration <= 0) return track.to;
    final end = start + duration;
    if (localMs >= end) return track.to;
    final t = (localMs - start) / duration;
    final eased = _ease(track.easing, t);
    return track.from + (track.to - track.from) * eased;
  }

  static double _ease(Easing easing, double t) {
    return switch (easing) {
      Easing.linear => t,
      Easing.easeIn => t * t,
      Easing.easeOut => t * (2 - t),
      Easing.easeInOut => t < 0.5 ? 2 * t * t : -1 + (4 - 2 * t) * t,
      Easing.overshoot => t,
      Easing.bounce => t,
    };
  }

  static Matrix4 matrixFor(ClipTransformBase base, Size frameSize) {
    final cx = frameSize.width / 2;
    final cy = frameSize.height / 2;
    final m = Matrix4.identity()
      ..translate(cx + base.translateX * frameSize.width, cy + base.translateY * frameSize.height)
      ..rotateZ(base.rotation * math.pi / 180)
      ..scale(base.scale);
    m.translate(-cx, -cy);
    return m;
  }
}
