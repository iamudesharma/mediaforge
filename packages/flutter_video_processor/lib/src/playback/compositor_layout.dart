import 'package:flutter/material.dart';

/// Letterboxed frame size inside [max] for [aspectRatio].
Size containedVideoFrameSize(Size max, double aspectRatio) {
  if (max.width <= 0 || max.height <= 0 || aspectRatio <= 0) {
    return Size.zero;
  }
  final containerAspect = max.width / max.height;
  if (containerAspect > aspectRatio) {
    final h = max.height;
    return Size(h * aspectRatio, h);
  }
  final w = max.width;
  return Size(w, w / aspectRatio);
}

/// Positions overlay children using normalized [anchor] (0–1) in the frame.
class VideoOverlayPositioned extends StatelessWidget {
  const VideoOverlayPositioned({
    super.key,
    required this.anchor,
    required this.opacity,
    required this.child,
  });

  final Offset anchor;
  final double opacity;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ax = anchor.dx.clamp(0.0, 1.0);
    final ay = anchor.dy.clamp(0.0, 1.0);
    return Positioned.fill(
      child: Align(
        alignment: Alignment(ax * 2 - 1, ay * 2 - 1),
        child: Opacity(opacity: opacity, child: child),
      ),
    );
  }
}
