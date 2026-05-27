import 'package:flutter/material.dart';

/// Timeline-aligned overlay metadata (V1.5 — Flutter compositor only, no Rust graph).
final class VideoOverlayItem {
  const VideoOverlayItem({
    required this.id,
    required this.startMs,
    required this.endMs,
    required this.anchor,
    required this.child,
  }) : assert(startMs >= 0),
       assert(endMs >= startMs);

  final String id;

  /// Inclusive start on the media timeline (ms).
  final int startMs;

  /// Exclusive end on the media timeline (ms).
  final int endMs;

  /// Normalized position within the video frame (0–1), origin top-left.
  final Offset anchor;

  final Widget child;

  /// Whether [playheadMs] falls inside this overlay's visible range.
  bool isVisibleAt(int playheadMs) =>
      playheadMs >= startMs && playheadMs < endMs;

  factory VideoOverlayItem.text({
    required String id,
    required int startMs,
    required int endMs,
    required Offset anchor,
    required String label,
    TextStyle? style,
    EdgeInsets padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
  }) {
    return VideoOverlayItem(
      id: id,
      startMs: startMs,
      endMs: endMs,
      anchor: anchor,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: padding,
          child: Text(
            label,
            style: style ??
                const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  shadows: [Shadow(blurRadius: 4, color: Colors.black)],
                ),
          ),
        ),
      ),
    );
  }

  factory VideoOverlayItem.emoji({
    required String id,
    required int startMs,
    required int endMs,
    required Offset anchor,
    required String emoji,
    double fontSize = 48,
  }) {
    return VideoOverlayItem(
      id: id,
      startMs: startMs,
      endMs: endMs,
      anchor: anchor,
      child: Text(
        emoji,
        style: TextStyle(fontSize: fontSize, shadows: const [
          Shadow(blurRadius: 6, color: Colors.black),
        ]),
      ),
    );
  }
}
