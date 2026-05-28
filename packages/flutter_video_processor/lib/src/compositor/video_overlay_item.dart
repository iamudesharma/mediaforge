import 'package:flutter/material.dart';

/// Timeline-aligned overlay metadata (V1.5 / Sprint 20 — Flutter compositor).
final class VideoOverlayItem {
  const VideoOverlayItem({
    required this.id,
    required this.startMs,
    required this.endMs,
    required this.anchor,
    required this.child,
    this.fadeInMs = 0,
    this.fadeOutMs = 0,
  })  : assert(startMs >= 0),
        assert(endMs >= startMs),
        assert(fadeInMs >= 0),
        assert(fadeOutMs >= 0);

  final String id;

  /// Inclusive start on the media timeline (ms).
  final int startMs;

  /// Exclusive end on the media timeline (ms).
  final int endMs;

  /// Normalized position within the video frame (0–1), origin top-left.
  final Offset anchor;

  final Widget child;

  /// Fade-in duration from [startMs] (Sprint 20).
  final int fadeInMs;

  /// Fade-out duration before [endMs] (Sprint 20).
  final int fadeOutMs;

  int get durationMs => endMs - startMs;

  /// Whether [playheadMs] falls inside this overlay's visible range.
  bool isVisibleAt(int playheadMs) =>
      playheadMs >= startMs && playheadMs < endMs;

  /// Opacity at [playheadMs] including fade in/out (0–1).
  double opacityAt(int playheadMs) {
    if (!isVisibleAt(playheadMs)) return 0;
    var opacity = 1.0;
    if (fadeInMs > 0) {
      final sinceStart = playheadMs - startMs;
      if (sinceStart < fadeInMs) {
        opacity = sinceStart / fadeInMs;
      }
    }
    if (fadeOutMs > 0) {
      final untilEnd = endMs - playheadMs;
      if (untilEnd < fadeOutMs) {
        final fadeOut = untilEnd / fadeOutMs;
        if (fadeOut < opacity) opacity = fadeOut;
      }
    }
    return opacity.clamp(0.0, 1.0);
  }

  VideoOverlayItem copyWith({
    String? id,
    int? startMs,
    int? endMs,
    Offset? anchor,
    Widget? child,
    int? fadeInMs,
    int? fadeOutMs,
  }) {
    return VideoOverlayItem(
      id: id ?? this.id,
      startMs: startMs ?? this.startMs,
      endMs: endMs ?? this.endMs,
      anchor: anchor ?? this.anchor,
      child: child ?? this.child,
      fadeInMs: fadeInMs ?? this.fadeInMs,
      fadeOutMs: fadeOutMs ?? this.fadeOutMs,
    );
  }

  factory VideoOverlayItem.text({
    required String id,
    required int startMs,
    required int endMs,
    required Offset anchor,
    required String label,
    TextStyle? style,
    EdgeInsets padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    int fadeInMs = 0,
    int fadeOutMs = 0,
  }) {
    return VideoOverlayItem(
      id: id,
      startMs: startMs,
      endMs: endMs,
      anchor: anchor,
      fadeInMs: fadeInMs,
      fadeOutMs: fadeOutMs,
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
    int fadeInMs = 0,
    int fadeOutMs = 0,
  }) {
    return VideoOverlayItem(
      id: id,
      startMs: startMs,
      endMs: endMs,
      anchor: anchor,
      fadeInMs: fadeInMs,
      fadeOutMs: fadeOutMs,
      child: Text(
        emoji,
        style: TextStyle(fontSize: fontSize, shadows: const [
          Shadow(blurRadius: 6, color: Colors.black),
        ]),
      ),
    );
  }
}
