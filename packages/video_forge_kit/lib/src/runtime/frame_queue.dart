import 'preview_frame.dart';

/// Result of enqueueing during playback — frames removed from the queue for release.
class PlaybackEnqueueResult {
  const PlaybackEnqueueResult({
    required this.accepted,
    this.dropped = const [],
    this.rejectedIncoming = false,
  });

  final bool accepted;
  final List<PreviewFrame> dropped;
  final bool rejectedIncoming;

  int get totalDropped => dropped.length + (rejectedIncoming ? 1 : 0);
}

/// Bounded FIFO of [PreviewFrame]s between decode producer and texture presenter.
///
/// When full, the oldest frame is dropped. [flush] clears pending frames on scrub.
final class FrameQueue {
  FrameQueue({this.maxDepth = defaultMaxDepth})
      : assert(maxDepth >= 1, 'maxDepth must be >= 1');

  static const defaultMaxDepth = 4;

  int maxDepth;
  final List<PreviewFrame> _frames = [];

  int get length => _frames.length;
  bool get isEmpty => _frames.isEmpty;
  bool get isFull => _frames.length >= maxDepth;

  /// Dynamically updates the maximum queue depth, returning any dropped frames if the size decreases.
  List<PreviewFrame> updateMaxDepth(int newDepth) {
    assert(newDepth >= 1, 'maxDepth must be >= 1');
    maxDepth = newDepth;
    final List<PreviewFrame> dropped = [];
    while (_frames.length > maxDepth) {
      dropped.add(_frames.removeAt(0));
    }
    return dropped;
  }

  /// Clears all queued frames (call at scrub start).
  void flush() => _frames.clear();

  /// Adds [frame]; drops the oldest entry when at [maxDepth].
  /// Returns the dropped or rejected frame if any.
  PreviewFrame? enqueue(PreviewFrame frame, {int? minPtsMs}) {
    if (minPtsMs != null && frame.ptsMs < minPtsMs) {
      return frame;
    }
    PreviewFrame? dropped;
    if (_frames.length >= maxDepth) {
      dropped = _frames.removeAt(0);
    }
    _frames.add(frame);
    return dropped;
  }

  /// Playback producer: drop frames older than [minPtsMs] / [wallPlayheadMs], then enqueue.
  ///
  /// When the queue is full, drops the oldest entries. If [latestOnlyWhenFull] and
  /// already at capacity, replaces the entire queue with [frame] (decode fell behind).
  ///
  /// When [wallPlayheadMs] is set and the frame is behind by more than
  /// [driftCatchUpThresholdMs], flushes the queue and keeps only [frame].
  PlaybackEnqueueResult enqueuePlayback(
    PreviewFrame frame, {
    required int minPtsMs,
    int? wallPlayheadMs,
    int driftCatchUpThresholdMs = 100,
    int staleMarginMs = 80,
    bool latestOnlyWhenFull = true,
    bool latestOnlyWhenBehind = true,
  }) {
    final dropped = <PreviewFrame>[];
    final cutoff = _playbackCutoffMs(
      minPtsMs: minPtsMs,
      wallPlayheadMs: wallPlayheadMs,
      staleMarginMs: staleMarginMs,
    );

    while (_frames.isNotEmpty && _frames.first.ptsMs < cutoff) {
      dropped.add(_frames.removeAt(0));
    }

    if (wallPlayheadMs != null &&
        latestOnlyWhenBehind &&
        wallPlayheadMs - frame.ptsMs > driftCatchUpThresholdMs) {
      dropped.addAll(_frames);
      _frames.clear();
      _frames.add(frame);
      return PlaybackEnqueueResult(accepted: true, dropped: dropped);
    }

    if (frame.ptsMs < cutoff) {
      return PlaybackEnqueueResult(
        accepted: false,
        dropped: dropped,
        rejectedIncoming: true,
      );
    }

    if (latestOnlyWhenFull && _frames.length >= maxDepth) {
      dropped.addAll(_frames);
      _frames.clear();
      _frames.add(frame);
      return PlaybackEnqueueResult(accepted: true, dropped: dropped);
    }

    while (_frames.length >= maxDepth) {
      dropped.add(_frames.removeAt(0));
    }
    _frames.add(frame);

    return PlaybackEnqueueResult(accepted: true, dropped: dropped);
  }

  /// Presenter: newest frame to display; [dropped] are older queued frames to release.
  ({PreviewFrame? frame, List<PreviewFrame> dropped}) takeLatestForPlayback() {
    if (_frames.isEmpty) {
      return (frame: null, dropped: const []);
    }
    final dropped = <PreviewFrame>[];
    while (_frames.length > 1) {
      dropped.add(_frames.removeAt(0));
    }
    return (frame: _frames.removeLast(), dropped: dropped);
  }

  /// Newest queued frame without removing it.
  PreviewFrame? peekLatest() => _frames.isEmpty ? null : _frames.last;

  /// Removes and returns the newest frame.
  PreviewFrame? takeLatest() => _frames.isEmpty ? null : _frames.removeLast();

  PreviewFrame? peekOldest() => _frames.isEmpty ? null : _frames.first;

  /// Removes and returns the oldest frame.
  PreviewFrame? takeOldest() => _frames.isEmpty ? null : _frames.removeAt(0);

  static int _playbackCutoffMs({
    required int minPtsMs,
    int? wallPlayheadMs,
    required int staleMarginMs,
  }) {
    var cutoff = minPtsMs - staleMarginMs;
    if (wallPlayheadMs != null) {
      final wallCutoff = wallPlayheadMs - staleMarginMs;
      if (wallCutoff > cutoff) {
        cutoff = wallCutoff;
      }
    }
    return cutoff;
  }
}
