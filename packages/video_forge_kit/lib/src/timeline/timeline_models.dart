import 'package:flutter/foundation.dart';

/// One contiguous segment from a source file placed on the master timeline.
@immutable
class VideoTimelineClip {
  const VideoTimelineClip({
    required this.id,
    required this.sourcePath,
    required this.sourceStartMs,
    required this.sourceEndMs,
    required this.timelineStartMs,
  })  : assert(sourceStartMs >= 0),
        assert(sourceEndMs > sourceStartMs),
        assert(timelineStartMs >= 0);

  final String id;
  final String sourcePath;
  final int sourceStartMs;
  final int sourceEndMs;
  final int timelineStartMs;

  int get durationMs => sourceEndMs - sourceStartMs;
  int get timelineEndMs => timelineStartMs + durationMs;

  bool containsTimelineMs(int ms) =>
      ms >= timelineStartMs && ms < timelineEndMs;

  bool containsSourceMs(int ms) => ms >= sourceStartMs && ms < sourceEndMs;

  VideoTimelineClip copyWith({
    String? id,
    String? sourcePath,
    int? sourceStartMs,
    int? sourceEndMs,
    int? timelineStartMs,
  }) {
    return VideoTimelineClip(
      id: id ?? this.id,
      sourcePath: sourcePath ?? this.sourcePath,
      sourceStartMs: sourceStartMs ?? this.sourceStartMs,
      sourceEndMs: sourceEndMs ?? this.sourceEndMs,
      timelineStartMs: timelineStartMs ?? this.timelineStartMs,
    );
  }
}

/// Background audio placed on the master timeline (preview/export wiring in host app).
@immutable
class AudioTimelineClip {
  const AudioTimelineClip({
    required this.id,
    required this.sourcePath,
    required this.timelineStartMs,
    required this.sourceDurationMs,
    this.sourceStartMs = 0,
    required this.durationMs,
    this.volume = 1.0,
    this.muted = false,
  })  : assert(timelineStartMs >= 0),
        assert(sourceStartMs >= 0),
        assert(sourceDurationMs > 0),
        assert(durationMs > 0),
        assert(sourceStartMs + durationMs <= sourceDurationMs),
        assert(volume >= 0 && volume <= 1);

  final String id;
  final String sourcePath;
  final int timelineStartMs;
  /// Full length of the audio file on disk.
  final int sourceDurationMs;
  /// In-point within the source file (which slice plays).
  final int sourceStartMs;
  /// Length of the window on the master timeline (locked to video length when added).
  final int durationMs;
  final double volume;
  final bool muted;

  int get timelineEndMs => timelineStartMs + durationMs;
  int get sourceEndMs => sourceStartMs + durationMs;

  bool containsTimelineMs(int ms) =>
      ms >= timelineStartMs && ms < timelineEndMs;

  AudioTimelineClip copyWith({
    String? id,
    String? sourcePath,
    int? timelineStartMs,
    int? sourceDurationMs,
    int? sourceStartMs,
    int? durationMs,
    double? volume,
    bool? muted,
  }) {
    return AudioTimelineClip(
      id: id ?? this.id,
      sourcePath: sourcePath ?? this.sourcePath,
      timelineStartMs: timelineStartMs ?? this.timelineStartMs,
      sourceDurationMs: sourceDurationMs ?? this.sourceDurationMs,
      sourceStartMs: sourceStartMs ?? this.sourceStartMs,
      durationMs: durationMs ?? this.durationMs,
      volume: volume ?? this.volume,
      muted: muted ?? this.muted,
    );
  }

  /// Clamps clip fields so `timelineStartMs + durationMs <= videoDurationMs` and
  /// `sourceStartMs + durationMs <= sourceDurationMs`.
  static AudioTimelineClip clamped(
    AudioTimelineClip clip, {
    required int videoDurationMs,
  }) {
    var duration = clip.durationMs.clamp(1, videoDurationMs);
    var timelineStart = clip.timelineStartMs.clamp(0, videoDurationMs - 1);
    if (timelineStart + duration > videoDurationMs) {
      duration = videoDurationMs - timelineStart;
    }
    final maxSourceStart = (clip.sourceDurationMs - duration).clamp(0, clip.sourceDurationMs);
    final sourceStart = clip.sourceStartMs.clamp(0, maxSourceStart);
    if (sourceStart + duration > clip.sourceDurationMs) {
      duration = clip.sourceDurationMs - sourceStart;
    }
    return clip.copyWith(
      timelineStartMs: timelineStart,
      durationMs: duration.clamp(1, videoDurationMs),
      sourceStartMs: sourceStart,
    );
  }
}

/// Maps a master-timeline position to a source file offset (Sprint 20).
@immutable
class TimelineSeekTarget {
  const TimelineSeekTarget({
    required this.sourcePath,
    required this.sourceMs,
    required this.clipId,
  });

  final String sourcePath;
  final int sourceMs;
  final String clipId;
}

/// Export trim derived from the video clip lane (single-source contiguous).
@immutable
class TimelineExportRange {
  const TimelineExportRange({
    required this.sourcePath,
    required this.startMs,
    required this.endMs,
  });

  final String sourcePath;
  final int startMs;
  final int endMs;

  int get durationMs => endMs - startMs;
}
