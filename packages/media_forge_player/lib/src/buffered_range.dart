import 'package:flutter/foundation.dart';

/// A genuinely available (buffered/preloaded/cached) media interval.
///
/// Generic, torrent-agnostic: the player never knows *how* bytes arrived
/// (FFmpeg demux read-ahead, OS file cache, host-provided download cache).
/// It only knows *which* time ranges can be played immediately without
/// waiting for more network data.
///
/// Invariant: [start] <= [end], both >= [Duration.zero].
@immutable
class MediaForgeBufferedRange {
  const MediaForgeBufferedRange({
    required this.start,
    required this.end,
  });

  /// Convenience for a single contiguous window from zero.
  const MediaForgeBufferedRange.upTo(Duration end)
      : start = Duration.zero,
        end = end;

  final Duration start;
  final Duration end;

  Duration get duration => end - start;

  bool get isEmpty => end <= start;

  bool contains(Duration position) =>
      position >= start && position <= end;

  bool overlaps(MediaForgeBufferedRange other) =>
      start <= other.end && other.start <= end;

  /// Adjacent (touching or overlapping within [tolerance]).
  bool isAdjacentTo(
    MediaForgeBufferedRange other, [
    Duration tolerance = Duration.zero,
  ]) {
    if (overlaps(other)) return true;
    if (end <= other.start) {
      return (other.start - end) <= tolerance;
    }
    return (start - other.end) <= tolerance;
  }

  MediaForgeBufferedRange merge(MediaForgeBufferedRange other) {
    return MediaForgeBufferedRange(
      start: start < other.start ? start : other.start,
      end: end > other.end ? end : other.end,
    );
  }

  MediaForgeBufferedRange clampTo(Duration lower, Duration upper) {
    final s = start < lower ? lower : start;
    final e = end > upper ? upper : end;
    if (e <= s) return MediaForgeBufferedRange(start: s, end: s);
    return MediaForgeBufferedRange(start: s, end: e);
  }

  @override
  bool operator ==(Object other) =>
      other is MediaForgeBufferedRange &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() =>
      'MediaForgeBufferedRange(${start.inMilliseconds}ms→${end.inMilliseconds}ms)';
}

/// Sort + merge overlapping/adjacent ranges. Empty ranges are dropped
/// unless [keepEmpty] is true. Invalid (start > end) ranges are dropped.
List<MediaForgeBufferedRange> normalizeBufferedRanges(
  List<MediaForgeBufferedRange> ranges, {
  Duration adjacencyTolerance = Duration.zero,
  bool keepEmpty = false,
}) {
  final valid = <MediaForgeBufferedRange>[];
  for (final r in ranges) {
    if (r.start > r.end) {
      continue;
    }
    if (r.isEmpty && !keepEmpty) continue;
    final s = r.start < Duration.zero ? Duration.zero : r.start;
    final e = r.end < Duration.zero ? Duration.zero : r.end;
    if (e <= s && !keepEmpty) continue;
    valid.add(MediaForgeBufferedRange(start: s, end: e));
  }
  if (valid.isEmpty) return const [];
  valid.sort((a, b) {
    final c = a.start.compareTo(b.start);
    if (c != 0) return c;
    return a.end.compareTo(b.end);
  });
  final merged = <MediaForgeBufferedRange>[valid.first];
  for (var i = 1; i < valid.length; i++) {
    final last = merged.last;
    final next = valid[i];
    if (last.overlaps(next) || last.isAdjacentTo(next, adjacencyTolerance)) {
      merged[merged.length - 1] = last.merge(next);
    } else {
      merged.add(next);
    }
  }
  return List.unmodifiable(merged);
}

/// Union of two range sets (no double-counting: overlapping time is
/// represented once). Used to combine engine-internal read-ahead with
/// host-provided cached/downloaded ranges for timeline display.
List<MediaForgeBufferedRange> mergeBufferedRanges(
  List<MediaForgeBufferedRange> a,
  List<MediaForgeBufferedRange> b, {
  Duration adjacencyTolerance = Duration.zero,
}) {
  if (a.isEmpty) return normalizeBufferedRanges(b);
  if (b.isEmpty) return normalizeBufferedRanges(a);
  return normalizeBufferedRanges([...a, ...b],
      adjacencyTolerance: adjacencyTolerance);
}

/// Contiguous buffered point ahead of [position]: the end of the range
/// containing [position], or [position] itself when in a gap.
///
/// This is the honest "how far can playback continue without stalling"
/// figure — never faked from playback position alone.
Duration contiguousBufferedPosition(
  List<MediaForgeBufferedRange> ranges,
  Duration position,
) {
  for (final r in ranges) {
    if (r.contains(position)) return r.end;
    // Ranges are expected normalized (sorted); early-out once past.
    if (r.start > position) break;
  }
  return position;
}

/// [contiguousBufferedPosition] minus [position] (never negative).
Duration bufferedAhead(
  List<MediaForgeBufferedRange> ranges,
  Duration position,
) {
  final end = contiguousBufferedPosition(ranges, position);
  final ahead = end - position;
  return ahead.isNegative ? Duration.zero : ahead;
}

/// Immutable buffer-availability snapshot for the dedicated timeline
/// notifier ([MediaForgePlayerController.bufferState]).
///
/// Updating this notifier never touches the video texture: widgets showing
/// the video surface listen to the presenter, while [PlayerTimeline]
/// listens here (or to the merged [MediaForgePlayerValue.bufferedRanges]).
@immutable
class MediaForgeBufferState {
  const MediaForgeBufferState({
    this.ranges = const [],
    this.bufferedPosition = Duration.zero,
    this.bufferedAhead = Duration.zero,
    this.isRebuffering = false,
    this.isPreloading = false,
    this.packetBufferedDuration = Duration.zero,
    this.packetBufferedBytes = 0,
    this.decodedVideoFrames = 0,
    this.decodedFrameMemoryBytes = 0,
  });

  static const empty = MediaForgeBufferState();

  /// Merged internal + external ranges available for immediate playback.
  final List<MediaForgeBufferedRange> ranges;

  /// Contiguous buffered point ahead of the playhead.
  final Duration bufferedPosition;

  /// [bufferedPosition] − position (never negative).
  final Duration bufferedAhead;

  /// Playback cannot continue (stall): show a loading indicator.
  final bool isRebuffering;

  /// Background read-ahead while playback is healthy or paused: never
  /// show a large spinner for this.
  final bool isPreloading;

  /// Compressed packet read-ahead (demux/network layer).
  final Duration packetBufferedDuration;

  /// Compressed packet bytes currently held.
  final int packetBufferedBytes;

  /// Decoded frames waiting for presentation (small: ~2–3).
  final int decodedVideoFrames;

  /// Estimated retained decoded-frame memory (bytes).
  final int decodedFrameMemoryBytes;

  MediaForgeBufferState copyWith({
    List<MediaForgeBufferedRange>? ranges,
    Duration? bufferedPosition,
    Duration? bufferedAhead,
    bool? isRebuffering,
    bool? isPreloading,
    Duration? packetBufferedDuration,
    int? packetBufferedBytes,
    int? decodedVideoFrames,
    int? decodedFrameMemoryBytes,
  }) {
    return MediaForgeBufferState(
      ranges: ranges ?? this.ranges,
      bufferedPosition: bufferedPosition ?? this.bufferedPosition,
      bufferedAhead: bufferedAhead ?? this.bufferedAhead,
      isRebuffering: isRebuffering ?? this.isRebuffering,
      isPreloading: isPreloading ?? this.isPreloading,
      packetBufferedDuration:
          packetBufferedDuration ?? this.packetBufferedDuration,
      packetBufferedBytes: packetBufferedBytes ?? this.packetBufferedBytes,
      decodedVideoFrames: decodedVideoFrames ?? this.decodedVideoFrames,
      decodedFrameMemoryBytes:
          decodedFrameMemoryBytes ?? this.decodedFrameMemoryBytes,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MediaForgeBufferState &&
      listEquals(other.ranges, ranges) &&
      other.bufferedPosition == bufferedPosition &&
      other.bufferedAhead == bufferedAhead &&
      other.isRebuffering == isRebuffering &&
      other.isPreloading == isPreloading &&
      other.packetBufferedDuration == packetBufferedDuration &&
      other.packetBufferedBytes == packetBufferedBytes &&
      other.decodedVideoFrames == decodedVideoFrames &&
      other.decodedFrameMemoryBytes == decodedFrameMemoryBytes;

  @override
  int get hashCode => Object.hash(
        Object.hashAll(ranges),
        bufferedPosition,
        bufferedAhead,
        isRebuffering,
        isPreloading,
        packetBufferedDuration,
        packetBufferedBytes,
        decodedVideoFrames,
        decodedFrameMemoryBytes,
      );

  @override
  String toString() =>
      'MediaForgeBufferState(ranges=$ranges bufferedPosition=${bufferedPosition.inMilliseconds}ms '
      'ahead=${bufferedAhead.inMilliseconds}ms rebuffering=$isRebuffering preloading=$isPreloading '
      'packet=${packetBufferedDuration.inMilliseconds}ms/${packetBufferedBytes}B decodedFrames=$decodedVideoFrames)';
}
