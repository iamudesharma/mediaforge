import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/layer_stack.dart';
import '../models/overlay_layer.dart';

/// Builds a stack-space [Path] for a paint stroke (cached on [PaintStrokeLayer]).
Path buildPaintStrokePath({
  required List<Offset> points,
  required int imageWidth,
  required int imageHeight,
  required Size childSize,
}) {
  final path = Path();
  if (points.length < 2 || imageWidth <= 0 || imageHeight <= 0) return path;

  final iw = imageWidth.toDouble();
  final ih = imageHeight.toDouble();
  final scale = math.min(childSize.width / iw, childSize.height / ih);
  final w = iw * scale;
  final h = ih * scale;
  final left = (childSize.width - w) / 2;
  final top = (childSize.height - h) / 2;
  final s = w / imageWidth;

  Offset toChild(Offset pixel) =>
      Offset(left + pixel.dx * s, top + pixel.dy * s);

  final first = toChild(points.first);
  path.moveTo(first.dx, first.dy);
  for (var i = 1; i < points.length; i++) {
    final p = toChild(points[i]);
    path.lineTo(p.dx, p.dy);
  }
  return path;
}

double paintStrokeWidthInStack({
  required double imagePixelWidth,
  required int imageWidth,
  required int imageHeight,
  required Size childSize,
}) {
  final iw = imageWidth.toDouble();
  final ih = imageHeight.toDouble();
  final scale = math.min(childSize.width / iw, childSize.height / ih);
  final rectW = iw * scale;
  return imagePixelWidth * (rectW / imageWidth);
}

/// Committed paint strokes only (RepaintBoundary-friendly).
class CommittedPaintStrokePainter extends CustomPainter {
  CommittedPaintStrokePainter({
    required this.stack,
    required this.imageWidth,
    required this.imageHeight,
    required this.childSize,
  });

  final LayerStack stack;
  final int imageWidth;
  final int imageHeight;
  final Size childSize;

  @override
  void paint(Canvas canvas, Size size) {
    for (final layer in stack.layers) {
      if (layer is! PaintStrokeLayer || layer.points.length < 2) continue;
      final path = layer.displayPath ??
          buildPaintStrokePath(
            points: layer.points,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            childSize: childSize,
          );
      final strokeW = paintStrokeWidthInStack(
        imagePixelWidth: layer.width,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        childSize: childSize,
      );
      final paint = Paint()
        ..color = layer.color.withValues(alpha: layer.opacity)
        ..strokeWidth = strokeW
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CommittedPaintStrokePainter old) {
    return old.stack.revision != stack.revision ||
        old.imageWidth != imageWidth ||
        old.imageHeight != imageHeight ||
        old.childSize != childSize;
  }
}

/// In-progress stroke only (high-frequency updates).
class ActivePaintStrokePainter extends CustomPainter {
  ActivePaintStrokePainter({
    required this.imageWidth,
    required this.imageHeight,
    required this.childSize,
    required this.points,
    required this.color,
    required this.width,
    required this.opacity,
  });

  final int imageWidth;
  final int imageHeight;
  final Size childSize;
  final List<Offset> points;
  final Color color;
  final double width;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final path = buildPaintStrokePath(
      points: points,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      childSize: childSize,
    );
    final strokeW = paintStrokeWidthInStack(
      imagePixelWidth: width,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      childSize: childSize,
    );
    final paint = Paint()
      ..color = color.withValues(alpha: opacity)
      ..strokeWidth = strokeW
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant ActivePaintStrokePainter old) {
    return old.points.length != points.length ||
        (points.isNotEmpty &&
            old.points.isNotEmpty &&
            old.points.last != points.last) ||
        old.color != color ||
        old.width != width ||
        old.opacity != opacity ||
        old.imageWidth != imageWidth ||
        old.imageHeight != imageHeight ||
        old.childSize != childSize;
  }
}

/// @deprecated Use [CommittedPaintStrokePainter] + [ActivePaintStrokePainter].
class PaintStrokePainter extends CustomPainter {
  PaintStrokePainter({
    required this.stack,
    required this.imageWidth,
    required this.imageHeight,
    required this.childSize,
    this.activeStroke,
    this.activeColor,
    this.activeWidth,
    this.activeOpacity,
  });

  final LayerStack stack;
  final int imageWidth;
  final int imageHeight;
  final Size childSize;
  final List<Offset>? activeStroke;
  final Color? activeColor;
  final double? activeWidth;
  final double? activeOpacity;

  @override
  void paint(Canvas canvas, Size size) {
    CommittedPaintStrokePainter(
      stack: stack,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      childSize: childSize,
    ).paint(canvas, size);
    if (activeStroke != null && activeStroke!.length >= 2) {
      ActivePaintStrokePainter(
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        childSize: childSize,
        points: activeStroke!,
        color: activeColor ?? const Color(0xFF4EDEA3),
        width: activeWidth ?? 8,
        opacity: activeOpacity ?? 0.9,
      ).paint(canvas, size);
    }
  }

  @override
  bool shouldRepaint(covariant PaintStrokePainter old) => true;
}
