import 'package:flutter/material.dart';

import 'video_text_overlay_content.dart';
import 'video_text_overlay_style.dart';

/// Timeline-aligned overlay metadata (V1.5 / Sprint 20 — Flutter compositor).
final class VideoOverlayItem {
  const VideoOverlayItem({
    required this.id,
    required this.startMs,
    required this.endMs,
    required this.anchor,
    required this.child,
    this.textSpec,
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

  /// When set, this overlay is a styled text caption ([child] should match [textSpec]).
  final VideoTextOverlaySpec? textSpec;

  /// Fade-in duration from [startMs] (Sprint 20).
  final int fadeInMs;

  /// Fade-out duration before [endMs] (Sprint 20).
  final int fadeOutMs;

  int get durationMs => endMs - startMs;

  bool get isTextOverlay => textSpec != null || id.startsWith('text:');

  /// Resolves [textSpec] for legacy overlays created before styling metadata existed.
  VideoTextOverlaySpec? get resolvedTextSpec {
    if (textSpec != null) return textSpec;
    if (!id.startsWith('text:')) return null;
    final parts = id.split(':');
    final label = parts.length > 1 ? parts[1] : 'Text';
    return VideoTextOverlaySpec(label: label);
  }

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
    VideoTextOverlaySpec? textSpec,
    int? fadeInMs,
    int? fadeOutMs,
  }) {
    final nextSpec = textSpec ?? this.textSpec;
    return VideoOverlayItem(
      id: id ?? this.id,
      startMs: startMs ?? this.startMs,
      endMs: endMs ?? this.endMs,
      anchor: anchor ?? this.anchor,
      child: child ??
          (nextSpec != null
              ? VideoTextOverlayContent(spec: nextSpec)
              : this.child),
      textSpec: nextSpec,
      fadeInMs: fadeInMs ?? this.fadeInMs,
      fadeOutMs: fadeOutMs ?? this.fadeOutMs,
    );
  }

  /// Updates text label/style and rebuilds [child].
  VideoOverlayItem withTextSpec(VideoTextOverlaySpec spec) {
    return copyWith(
      textSpec: spec,
      child: VideoTextOverlayContent(spec: spec),
    );
  }

  factory VideoOverlayItem.text({
    required String id,
    required int startMs,
    required int endMs,
    required Offset anchor,
    required String label,
    VideoTextOverlayStyle style = VideoTextOverlayStyle.defaults,
    int fadeInMs = 0,
    int fadeOutMs = 0,
  }) {
    final spec = VideoTextOverlaySpec(label: label, style: style);
    return VideoOverlayItem(
      id: id,
      startMs: startMs,
      endMs: endMs,
      anchor: anchor,
      fadeInMs: fadeInMs,
      fadeOutMs: fadeOutMs,
      textSpec: spec,
      child: VideoTextOverlayContent(spec: spec),
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
