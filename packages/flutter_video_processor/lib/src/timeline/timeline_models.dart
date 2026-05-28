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
    this.sourceStartMs = 0,
    required this.durationMs,
    this.volume = 1.0,
    this.muted = false,
  })  : assert(timelineStartMs >= 0),
        assert(sourceStartMs >= 0),
        assert(durationMs > 0),
        assert(volume >= 0 && volume <= 1);

  final String id;
  final String sourcePath;
  final int timelineStartMs;
  final int sourceStartMs;
  final int durationMs;
  final double volume;
  final bool muted;

  int get timelineEndMs => timelineStartMs + durationMs;

  bool containsTimelineMs(int ms) =>
      ms >= timelineStartMs && ms < timelineEndMs;

  AudioTimelineClip copyWith({
    String? id,
    String? sourcePath,
    int? timelineStartMs,
    int? sourceStartMs,
    int? durationMs,
    double? volume,
    bool? muted,
  }) {
    return AudioTimelineClip(
      id: id ?? this.id,
      sourcePath: sourcePath ?? this.sourcePath,
      timelineStartMs: timelineStartMs ?? this.timelineStartMs,
      sourceStartMs: sourceStartMs ?? this.sourceStartMs,
      durationMs: durationMs ?? this.durationMs,
      volume: volume ?? this.volume,
      muted: muted ?? this.muted,
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
