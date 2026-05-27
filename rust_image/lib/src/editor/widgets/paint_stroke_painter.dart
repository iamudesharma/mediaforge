import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../models/layer_stack.dart';
import '../models/overlay_layer.dart';

/// Builds a stack-space [Path] for a paint stroke/shape (cached on [PaintStrokeLayer]).
Path buildPaintStrokePath({
  required List<Offset> points,
  required int imageWidth,
  required int imageHeight,
  required Size childSize,
  PaintBrushKind brush = PaintBrushKind.pen,
}) {
  final path = Path();
  if (points.isEmpty || imageWidth <= 0 || imageHeight <= 0) return path;

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

  final childPoints = points.map(toChild).toList();
  if (childPoints.isEmpty) return path;
  final start = childPoints.first;
  final end = childPoints.length > 1 ? childPoints[1] : start;

  switch (brush) {
    case PaintBrushKind.pen:
    case PaintBrushKind.marker:
    case PaintBrushKind.highlighter:
    case PaintBrushKind.neon:
    case PaintBrushKind.eraser:
      path.moveTo(start.dx, start.dy);
      for (var i = 1; i < childPoints.length; i++) {
        path.lineTo(childPoints[i].dx, childPoints[i].dy);
      }
      break;

    case PaintBrushKind.line:
      path.moveTo(start.dx, start.dy);
      path.lineTo(end.dx, end.dy);
      break;

    case PaintBrushKind.rect:
    case PaintBrushKind.blur:
    case PaintBrushKind.pixelate:
      path.addRect(Rect.fromPoints(start, end));
      break;

    case PaintBrushKind.circle:
      final r = (end - start).distance;
      path.addOval(Rect.fromCircle(center: start, radius: r));
      break;

    case PaintBrushKind.hexagon:
      final r = (end - start).distance;
      path.moveTo(start.dx + r, start.dy);
      for (int i = 1; i <= 6; i++) {
        final double angle = i * math.pi / 3;
        path.lineTo(start.dx + r * math.cos(angle), start.dy + r * math.sin(angle));
      }
      path.close();
      break;

    case PaintBrushKind.polygon:
      path.moveTo(start.dx, start.dy);
      for (var i = 1; i < childPoints.length; i++) {
        path.lineTo(childPoints[i].dx, childPoints[i].dy);
      }
      break;

    case PaintBrushKind.arrow:
      _addArrowToPath(path, start, end, doubleArrow: false);
      break;

    case PaintBrushKind.doubleArrow:
      _addArrowToPath(path, start, end, doubleArrow: true);
      break;

    case PaintBrushKind.dashLine:
      _addDashedLineToPath(path, start, end, dashLength: 8, gapLength: 6);
      break;

    case PaintBrushKind.dashDotLine:
      _addDashDotLineToPath(path, start, end);
      break;
  }
  return path;
}

void _addArrowToPath(Path path, Offset start, Offset end, {required bool doubleArrow}) {
  path.moveTo(start.dx, start.dy);
  path.lineTo(end.dx, end.dy);

  final double theta = math.atan2(end.dy - start.dy, end.dx - start.dx);
  const double arrowAngle = math.pi / 6; // 30 degrees
  const double arrowLength = 16.0;

  // Forward arrow head
  final x1 = end.dx - arrowLength * math.cos(theta - arrowAngle);
  final y1 = end.dy - arrowLength * math.sin(theta - arrowAngle);
  final x2 = end.dx - arrowLength * math.cos(theta + arrowAngle);
  final y2 = end.dy - arrowLength * math.sin(theta + arrowAngle);

  path.moveTo(end.dx, end.dy);
  path.lineTo(x1, y1);
  path.moveTo(end.dx, end.dy);
  path.lineTo(x2, y2);

  if (doubleArrow) {
    // Backward arrow head
    final bx1 = start.dx + arrowLength * math.cos(theta - arrowAngle);
    final by1 = start.dy + arrowLength * math.sin(theta - arrowAngle);
    final bx2 = start.dx + arrowLength * math.cos(theta + arrowAngle);
    final by2 = start.dy + arrowLength * math.sin(theta + arrowAngle);

    path.moveTo(start.dx, start.dy);
    path.lineTo(bx1, by1);
    path.moveTo(start.dx, start.dy);
    path.lineTo(bx2, by2);
  }
}

void _addDashedLineToPath(Path path, Offset start, Offset end, {required double dashLength, required double gapLength}) {
  final distance = (end - start).distance;
  if (distance == 0) return;
  final direction = Offset(
    (end.dx - start.dx) / distance,
    (end.dy - start.dy) / distance,
  );

  double currentDistance = 0;
  while (currentDistance < distance) {
    final nextDash = math.min(currentDistance + dashLength, distance);
    final p1 = start + direction * currentDistance;
    final p2 = start + direction * nextDash;
    path.moveTo(p1.dx, p1.dy);
    path.lineTo(p2.dx, p2.dy);
    currentDistance += dashLength + gapLength;
  }
}

void _addDashDotLineToPath(Path path, Offset start, Offset end) {
  final distance = (end - start).distance;
  if (distance == 0) return;
  final direction = Offset(
    (end.dx - start.dx) / distance,
    (end.dy - start.dy) / distance,
  );

  const double dashLen = 10.0;
  const double gapLen = 5.0;
  const double dotLen = 2.0;

  double currentDistance = 0;
  bool isDash = true;
  while (currentDistance < distance) {
    if (isDash) {
      final nextDash = math.min(currentDistance + dashLen, distance);
      final p1 = start + direction * currentDistance;
      final p2 = start + direction * nextDash;
      path.moveTo(p1.dx, p1.dy);
      path.lineTo(p2.dx, p2.dy);
      currentDistance += dashLen + gapLen;
    } else {
      final nextDot = math.min(currentDistance + dotLen, distance);
      final p1 = start + direction * currentDistance;
      final p2 = start + direction * nextDot;
      path.moveTo(p1.dx, p1.dy);
      path.lineTo(p2.dx, p2.dy);
      currentDistance += dotLen + gapLen;
    }
    isDash = !isDash;
  }
}

double paintStrokeWidthInStack({
  required double imagePixelWidth,
  required int imageWidth,
  required int imageHeight,
  required Size childSize,
  PaintBrushKind brush = PaintBrushKind.pen,
}) {
  final iw = imageWidth.toDouble();
  final ih = imageHeight.toDouble();
  final scale = math.min(childSize.width / iw, childSize.height / ih);
  final rectW = iw * scale;
  final base = imagePixelWidth * (rectW / imageWidth);
  return switch (brush) {
    PaintBrushKind.marker => base * 1.4,
    PaintBrushKind.highlighter => base * 2.2,
    PaintBrushKind.neon => base * 1.25,
    _ => base,
  };
}

({Paint paint, bool useLayer}) paintConfigForBrush({
  required PaintBrushKind brush,
  required Color color,
  required double opacity,
  required double strokeWidth,
  bool filled = false,
}) {
  final isEraser = brush == PaintBrushKind.eraser;
  if (isEraser) {
    return (
      paint: Paint()
        ..color = Colors.transparent
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..blendMode = BlendMode.clear,
      useLayer: true,
    );
  }

  var effectiveColor = color.withValues(alpha: opacity);
  var blend = BlendMode.srcOver;
  var width = strokeWidth;
  MaskFilter? mask;

  switch (brush) {
    case PaintBrushKind.marker:
      width = strokeWidth * 1.4;
      break;
    case PaintBrushKind.highlighter:
      width = strokeWidth * 2.2;
      effectiveColor = color.withValues(alpha: opacity * 0.35);
      blend = BlendMode.plus;
      break;
    case PaintBrushKind.neon:
      width = strokeWidth * 1.25;
      effectiveColor = Color.fromARGB(
        (opacity * 255).round().clamp(0, 255),
        color.red.clamp(0, 255),
        color.green.clamp(0, 255),
        (color.blue + 80).clamp(0, 255),
      );
      mask = const MaskFilter.blur(BlurStyle.normal, 6);
      break;
    default:
      break;
  }

  final style = filled ? PaintingStyle.fill : PaintingStyle.stroke;

  final paint = Paint()
    ..color = effectiveColor
    ..strokeWidth = width
    ..style = style
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..blendMode = blend;
  if (mask != null) {
    paint.maskFilter = mask;
  }

  return (paint: paint, useLayer: brush == PaintBrushKind.highlighter || brush == PaintBrushKind.neon);
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
      if (!layer.visible) continue;
      if (layer is! PaintStrokeLayer || layer.points.isEmpty) continue;
      // Skip censor layers as they are drawn as positioned BackdropFilter widgets in Stack
      if (layer.brush == PaintBrushKind.blur || layer.brush == PaintBrushKind.pixelate) continue;

      final path = layer.displayPath ??
          buildPaintStrokePath(
            points: layer.points,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            childSize: childSize,
            brush: layer.brush,
          );
      final strokeW = paintStrokeWidthInStack(
        imagePixelWidth: layer.width,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        childSize: childSize,
        brush: layer.brush,
      );
      final cfg = paintConfigForBrush(
        brush: layer.brush,
        color: layer.color,
        opacity: layer.opacity,
        strokeWidth: strokeW,
        filled: layer.filled,
      );
      if (cfg.useLayer) {
        canvas.saveLayer(Offset.zero & size, Paint());
      }
      if (layer.brush == PaintBrushKind.neon) {
        final glow = paintConfigForBrush(
          brush: PaintBrushKind.neon,
          color: layer.color,
          opacity: layer.opacity * 0.25,
          strokeWidth: strokeW * 2.2,
          filled: layer.filled,
        );
        canvas.drawPath(path, glow.paint);
      }
      canvas.drawPath(path, cfg.paint);
      if (cfg.useLayer) {
        canvas.restore();
      }
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
    this.brush = PaintBrushKind.pen,
    this.filled = false,
  });

  final int imageWidth;
  final int imageHeight;
  final Size childSize;
  final List<Offset> points;
  final Color color;
  final double width;
  final double opacity;
  final PaintBrushKind brush;
  final bool filled;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    // Draw active censor boundary outline as a dash-dotted rect
    if (brush == PaintBrushKind.blur || brush == PaintBrushKind.pixelate) {
      if (points.length < 2) return;
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

      final start = toChild(points.first);
      final end = toChild(points.last);

      final topLeft = Offset(math.min(start.dx, end.dx), math.min(start.dy, end.dy));
      final topRight = Offset(math.max(start.dx, end.dx), math.min(start.dy, end.dy));
      final bottomRight = Offset(math.max(start.dx, end.dx), math.max(start.dy, end.dy));
      final bottomLeft = Offset(math.min(start.dx, end.dx), math.max(start.dy, end.dy));

      final path = Path();
      _addDashDotLineToPath(path, topLeft, topRight);
      _addDashDotLineToPath(path, topRight, bottomRight);
      _addDashDotLineToPath(path, bottomRight, bottomLeft);
      _addDashDotLineToPath(path, bottomLeft, topLeft);

      final borderPaint = Paint()
        ..color = color.withValues(alpha: 0.8)
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;
      canvas.drawPath(path, borderPaint);
      return;
    }

    final path = buildPaintStrokePath(
      points: points,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      childSize: childSize,
      brush: brush,
    );
    final strokeW = paintStrokeWidthInStack(
      imagePixelWidth: width,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      childSize: childSize,
      brush: brush,
    );
    final cfg = paintConfigForBrush(
      brush: brush,
      color: color,
      opacity: opacity,
      strokeWidth: strokeW,
      filled: filled,
    );
    if (cfg.useLayer) {
      canvas.saveLayer(Offset.zero & size, Paint());
    }
    if (brush == PaintBrushKind.neon) {
      final glow = paintConfigForBrush(
        brush: PaintBrushKind.neon,
        color: color,
        opacity: opacity * 0.25,
        strokeWidth: strokeW * 2.2,
        filled: filled,
      );
      canvas.drawPath(path, glow.paint);
    }
    canvas.drawPath(path, cfg.paint);
    if (cfg.useLayer) {
      canvas.restore();
    }
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
        old.brush != brush ||
        old.filled != filled ||
        old.imageWidth != imageWidth ||
        old.imageHeight != imageHeight ||
        old.childSize != childSize;
  }
}
