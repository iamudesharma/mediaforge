import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/overlay_layer.dart';

/// Analytical hit-testing math for PaintStrokeLayers (Sprint 16).
class PaintHitTest {
  /// Calculated distance from [p] to the line segment between [p1] and [p2].
  static double distanceToSegment(Offset p, Offset p1, Offset p2) {
    final double l2 = (p1 - p2).distanceSquared;
    if (l2 == 0) return (p - p1).distance;
    // Projection factor bounded to [0, 1]
    final double t = (((p.dx - p1.dx) * (p2.dx - p1.dx) +
                (p.dy - p1.dy) * (p2.dy - p1.dy)) /
            l2)
        .clamp(0.0, 1.0);
    final Offset projection = p1 + (p2 - p1) * t;
    return (p - projection).distance;
  }

  /// True if [tap] lies within the hit boundary of a freestyle stroke.
  static bool hitTestFreestyle(List<Offset> points, Offset tap, double width) {
    if (points.isEmpty) return false;
    if (points.length == 1) return (tap - points.first).distance <= width / 2;
    for (int i = 0; i < points.length - 1; i++) {
      if (distanceToSegment(tap, points[i], points[i + 1]) <= width / 2) {
        return true;
      }
    }
    return false;
  }

  /// True if [tap] lies near a straight line or arrow.
  static bool hitTestLine(Offset p1, Offset p2, Offset tap, double width) {
    return distanceToSegment(tap, p1, p2) <= width / 2;
  }

  /// True if [tap] lies inside a rectangle (if filled) or on its border outline.
  static bool hitTestRect(
      Offset p1, Offset p2, Offset tap, double width, bool filled) {
    final double left = math.min(p1.dx, p2.dx);
    final double right = math.max(p1.dx, p2.dx);
    final double top = math.min(p1.dy, p2.dy);
    final double bottom = math.max(p1.dy, p2.dy);

    if (filled) {
      return tap.dx >= left && tap.dx <= right && tap.dy >= top && tap.dy <= bottom;
    } else {
      // Check proximity to all 4 borders
      final dLeft = (tap.dx - left).abs();
      final dRight = (tap.dx - right).abs();
      final dTop = (tap.dy - top).abs();
      final dBottom = (tap.dy - bottom).abs();

      final insideX = tap.dx >= left - width / 2 && tap.dx <= right + width / 2;
      final insideY = tap.dy >= top - width / 2 && tap.dy <= bottom + width / 2;

      if (insideX && (dTop <= width / 2 || dBottom <= width / 2)) return true;
      if (insideY && (dLeft <= width / 2 || dRight <= width / 2)) return true;
      return false;
    }
  }

  /// True if [tap] lies inside a circle (if filled) or on its boundary outline.
  static bool hitTestCircle(
      Offset center, double radius, Offset tap, double width, bool filled) {
    final double dist = (tap - center).distance;
    if (filled) {
      return dist <= radius + width / 2;
    } else {
      return (dist - radius).abs() <= width / 2;
    }
  }

  /// True if [tap] lies inside a hexagon (if filled) or on its outline boundary.
  static bool hitTestHexagon(
      Offset center, double radius, Offset tap, double width, bool filled) {
    final vertices = _getHexagonVertices(center, radius);
    return hitTestPolygon(vertices, tap, width, filled);
  }

  /// True if [tap] lies inside a polygon (using ray-casting) or on its boundary outline.
  static bool hitTestPolygon(
      List<Offset> vertices, Offset tap, double width, bool filled) {
    if (vertices.isEmpty) return false;

    // 1. Boundary outline check
    for (int i = 0; i < vertices.length; i++) {
      final p1 = vertices[i];
      final p2 = vertices[(i + 1) % vertices.length];
      if (distanceToSegment(tap, p1, p2) <= width / 2) {
        return true;
      }
    }

    if (!filled) return false;

    // 2. Ray-casting point-in-polygon check
    int intersectCount = 0;
    for (int i = 0; i < vertices.length; i++) {
      final p1 = vertices[i];
      final p2 = vertices[(i + 1) % vertices.length];

      if (((p1.dy > tap.dy) != (p2.dy > tap.dy)) &&
          (tap.dx < (p2.dx - p1.dx) * (tap.dy - p1.dy) / (p2.dy - p1.dy) + p1.dx)) {
        intersectCount++;
      }
    }
    return intersectCount % 2 != 0;
  }

  static List<Offset> _getHexagonVertices(Offset center, double radius) {
    final vertices = <Offset>[];
    for (int i = 0; i < 6; i++) {
      final double angle = i * math.pi / 3;
      vertices.add(Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      ));
    }
    return vertices;
  }

  /// Dispatches the hit-test based on the layer's brush kind.
  static bool hitTestLayer(PaintStrokeLayer layer, Offset tap) {
    final List<Offset> points = layer.points;
    if (points.isEmpty) return false;
    final double width = layer.width;
    final bool filled = layer.filled;

    switch (layer.brush) {
      case PaintBrushKind.pen:
      case PaintBrushKind.marker:
      case PaintBrushKind.highlighter:
      case PaintBrushKind.neon:
        return hitTestFreestyle(points, tap, width);

      case PaintBrushKind.line:
      case PaintBrushKind.arrow:
      case PaintBrushKind.doubleArrow:
      case PaintBrushKind.dashLine:
      case PaintBrushKind.dashDotLine:
        if (points.length < 2) return false;
        return hitTestLine(points.first, points.last, tap, width);

      case PaintBrushKind.rect:
      case PaintBrushKind.blur:
      case PaintBrushKind.pixelate:
        if (points.length < 2) return false;
        // Rects and censors are defined by corner bounds
        return hitTestRect(points.first, points.last, tap, width, filled || layer.brush == PaintBrushKind.blur || layer.brush == PaintBrushKind.pixelate);

      case PaintBrushKind.circle:
        if (points.length < 2) return false;
        final center = points.first;
        final radius = (points.last - points.first).distance;
        return hitTestCircle(center, radius, tap, width, filled);

      case PaintBrushKind.hexagon:
        if (points.length < 2) return false;
        final center = points.first;
        final radius = (points.last - points.first).distance;
        return hitTestHexagon(center, radius, tap, width, filled);

      case PaintBrushKind.polygon:
        return hitTestPolygon(points, tap, width, filled);

      case PaintBrushKind.eraser:
        // Eraser strokes are freestyle paths
        return hitTestFreestyle(points, tap, width);
    }
  }
}
