/// Trim-range helpers for [NativePlaybackController] (unit-testable).
library;

/// Clamps [positionMs] to inclusive trim range `[startMs, endMs]`.
int clampPositionToTrim(int positionMs, int startMs, int endMs) {
  if (endMs < startMs) return startMs;
  return positionMs.clamp(startMs, endMs);
}

/// Seek target after clamping to trim (and optional full duration cap).
int clampSeekMs({
  required int requestedMs,
  required int startMs,
  required int endMs,
  int? durationMs,
}) {
  var ms = clampPositionToTrim(requestedMs, startMs, endMs);
  if (durationMs != null && durationMs > 0) {
    ms = ms.clamp(0, durationMs);
  }
  return ms;
}

/// True when playback reached trim end and should pause (not loop).
bool shouldPauseAtTrimEnd({
  required int positionMs,
  required int endMs,
  required bool isPlaying,
  required bool loopPlayback,
  int toleranceMs = 80,
}) {
  if (!isPlaying || loopPlayback) return false;
  return positionMs >= endMs - toleranceMs;
}

/// Maps source-file PTS to master timeline seconds (single-source clips).
double timelineSecFromSourcePts({
  required int sourcePtsMs,
  required String sourcePath,
  required List<TimelineClipMapping> clips,
}) {
  for (final clip in clips) {
    if (clip.sourcePath != sourcePath) continue;
    if (sourcePtsMs >= clip.sourceStartMs && sourcePtsMs < clip.sourceEndMs) {
      return (clip.timelineStartMs + (sourcePtsMs - clip.sourceStartMs)) /
          1000.0;
    }
  }
  return sourcePtsMs / 1000.0;
}

/// Minimal clip mapping for timeline ↔ source position (editor sync).
class TimelineClipMapping {
  const TimelineClipMapping({
    required this.sourcePath,
    required this.sourceStartMs,
    required this.sourceEndMs,
    required this.timelineStartMs,
  });

  final String sourcePath;
  final int sourceStartMs;
  final int sourceEndMs;
  final int timelineStartMs;
}
