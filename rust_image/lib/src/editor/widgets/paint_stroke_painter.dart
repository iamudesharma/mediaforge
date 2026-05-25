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
    case PaintBrushKind.highlighter:
      width = strokeWidth * 2.2;
      effectiveColor = color.withValues(alpha: opacity * 0.35);
      blend = BlendMode.plus;
    case PaintBrushKind.neon:
      width = strokeWidth * 1.25;
      effectiveColor = Color.fromARGB(
        (opacity * 255).round().clamp(0, 255),
        color.red.clamp(0, 255),
        color.green.clamp(0, 255),
        (color.blue + 80).clamp(0, 255),
      );
      mask = const MaskFilter.blur(BlurStyle.normal, 6);
    case PaintBrushKind.pen:
    case PaintBrushKind.eraser:
      break;
  }

  final paint = Paint()
    ..color = effectiveColor
    ..strokeWidth = width
    ..style = PaintingStyle.stroke
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
        brush: layer.brush,
      );
      final cfg = paintConfigForBrush(
        brush: layer.brush,
        color: layer.color,
        opacity: layer.opacity,
        strokeWidth: strokeW,
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
  });

  final int imageWidth;
  final int imageHeight;
  final Size childSize;
  final List<Offset> points;
  final Color color;
  final double width;
  final double opacity;
  final PaintBrushKind brush;

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
      brush: brush,
    );
    final cfg = paintConfigForBrush(
      brush: brush,
      color: color,
      opacity: opacity,
      strokeWidth: strokeW,
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
