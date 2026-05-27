import 'preview_frame.dart';

/// Bounded FIFO of [PreviewFrame]s between decode producer and texture presenter.
///
/// When full, the oldest frame is dropped. [flush] clears pending frames on scrub.
final class FrameQueue {
  FrameQueue({this.maxDepth = defaultMaxDepth})
      : assert(maxDepth >= 1, 'maxDepth must be >= 1');

  static const defaultMaxDepth = 3;

  final int maxDepth;
  final List<PreviewFrame> _frames = [];

  int get length => _frames.length;
  bool get isEmpty => _frames.isEmpty;
  bool get isFull => _frames.length >= maxDepth;

  /// Clears all queued frames (call at scrub start).
  void flush() => _frames.clear();

  /// Adds [frame]; drops the oldest entry when at [maxDepth].
  ///
  /// If [minPtsMs] is set, ignores frames older than that (playback catch-up in V1.3+).
  void enqueue(PreviewFrame frame, {int? minPtsMs}) {
    if (minPtsMs != null && frame.ptsMs < minPtsMs) {
      return;
    }
    while (_frames.length >= maxDepth) {
      _frames.removeAt(0);
    }
    _frames.add(frame);
  }

  /// Newest queued frame without removing it.
  PreviewFrame? peekLatest() => _frames.isEmpty ? null : _frames.last;

  /// Removes and returns the newest frame.
  PreviewFrame? takeLatest() => _frames.isEmpty ? null : _frames.removeLast();

  /// Removes and returns the oldest frame.
  PreviewFrame? takeOldest() => _frames.isEmpty ? null : _frames.removeAt(0);
}
