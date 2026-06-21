import 'package:video_forge/video_forge.dart';

import '../timeline/timeline_models.dart';

/// Helpers for [ClipEffects] (zoom / pan / rotate / speed on source clip).
class ClipEffectsKit {
  ClipEffectsKit._();

  /// Effects stored on [clip], or identity when unset.
  static ClipEffects forClip(VideoTimelineClip? clip) =>
      clip?.effects ?? identity();

  /// Timeline playhead offset inside [clip] (0…durationMs).
  static int localTimelineMs(VideoTimelineClip clip, int timelineMs) {
    final local = timelineMs - clip.timelineStartMs;
    if (local < 0) return 0;
    if (local > clip.durationMs) return clip.durationMs;
    return local;
  }

  static ClipEffects identity() => const ClipEffects(
        base: ClipTransformBase(
          translateX: 0,
          translateY: 0,
          scale: 1,
          rotation: 0,
        ),
        motion: TransformTracks(tracks: []),
        speed: 1,
        speedSegments: [],
      );

  static bool isIdentity(ClipEffects effects) {
    return (effects.speed - 1).abs() < 0.001 &&
        effects.speedSegments.isEmpty &&
        effects.motion.tracks.isEmpty &&
        (effects.base.scale - 1).abs() < 0.001 &&
        effects.base.translateX.abs() < 0.001 &&
        effects.base.translateY.abs() < 0.001 &&
        effects.base.rotation.abs() < 0.001;
  }

  static ClipEffects copyWithBase(
    ClipEffects effects, {
    double? translateX,
    double? translateY,
    double? scale,
    double? rotation,
  }) {
    return ClipEffects(
      base: ClipTransformBase(
        translateX: translateX ?? effects.base.translateX,
        translateY: translateY ?? effects.base.translateY,
        scale: scale ?? effects.base.scale,
        rotation: rotation ?? effects.base.rotation,
      ),
      motion: effects.motion,
      speed: effects.speed,
      speedSegments: effects.speedSegments,
    );
  }

  static ClipEffects withSpeed(ClipEffects effects, double speed) {
    return ClipEffects(
      base: effects.base,
      motion: effects.motion,
      speed: speed.clamp(0.25, 4.0),
      speedSegments: effects.speedSegments,
    );
  }

  /// Playback/export speed at clip-local [localMs] (honours [speedSegments]).
  static double effectiveSpeedAt(ClipEffects effects, int localMs) {
    for (final seg in effects.speedSegments) {
      final start = seg.startMs.toInt();
      final end = seg.endMs.toInt();
      if (localMs >= start && localMs < end) {
        return seg.rate.clamp(0.25, 4.0);
      }
    }
    return effects.speed.clamp(0.25, 4.0);
  }

  /// Apply a motion preset while keeping base transform + clip speed.
  static ClipEffects mergeMotionPreset(ClipEffects current, ClipEffects preset) {
    return ClipEffects(
      base: current.base,
      motion: preset.motion,
      speed: current.speed,
      speedSegments: current.speedSegments,
    );
  }

  /// Full-clip speed ramp (e.g. 2× for entire selected segment).
  static ClipEffects withFullClipSpeedRamp(
    ClipEffects effects,
    int durationMs, {
    required double rate,
  }) {
    if ((rate - 1.0).abs() < 0.001 || durationMs <= 0) {
      return ClipEffects(
        base: effects.base,
        motion: effects.motion,
        speed: 1.0,
        speedSegments: const [],
      );
    }
    return ClipEffects(
      base: effects.base,
      motion: effects.motion,
      speed: 1.0,
      speedSegments: [
        SpeedSegment(
          startMs: BigInt.zero,
          endMs: BigInt.from(durationMs),
          rate: rate.clamp(0.25, 4.0),
        ),
      ],
    );
  }

  static bool needsSegmentedExport(List<VideoTimelineClip> clips) =>
      clips.length > 1;

  /// Ken Burns zoom-in over [durationMs].
  static ClipEffects kenBurnsZoomIn({
    required int durationMs,
    double fromScale = 1.0,
    double toScale = 1.35,
  }) {
    return ClipEffects(
      base: const ClipTransformBase(
        translateX: 0,
        translateY: 0,
        scale: 1,
        rotation: 0,
      ),
      motion: TransformTracks(
        tracks: [
          AnimationTrack(
            property: TransformProperty.scale,
            from: fromScale,
            to: toScale,
            startMs: BigInt.zero,
            durationMs: BigInt.from(durationMs),
            easing: Easing.easeInOut,
          ),
        ],
      ),
      speed: 1,
      speedSegments: const [],
    );
  }

  /// Pan left → right across the frame.
  static ClipEffects panLeftToRight({required int durationMs}) {
    return ClipEffects(
      base: const ClipTransformBase(
        translateX: 0,
        translateY: 0,
        scale: 1.15,
        rotation: 0,
      ),
      motion: TransformTracks(
        tracks: [
          AnimationTrack(
            property: TransformProperty.translateX,
            from: -0.12,
            to: 0.12,
            startMs: BigInt.zero,
            durationMs: BigInt.from(durationMs),
            easing: Easing.easeInOut,
          ),
        ],
      ),
      speed: 1,
      speedSegments: const [],
    );
  }
}
