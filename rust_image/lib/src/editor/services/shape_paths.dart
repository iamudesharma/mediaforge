import 'dart:math' as math;
import 'dart:ui';

import '../models/overlay_layer.dart';

/// Builds clip paths for sticker shape masks in normalized [0,1]×[0,1] space.
abstract final class ShapePaths {
  static Path build(
    StickerShapeMask mask, {
    required double width,
    required double height,
    double cornerRadius = 16,
  }) {
    final rect = Rect.fromLTWH(0, 0, width, height);
    return switch (mask) {
      StickerShapeMask.none => Path()..addRect(rect),
      StickerShapeMask.roundedRect => Path()
        ..addRRect(
          RRect.fromRectAndRadius(
            rect,
            Radius.circular(cornerRadius.clamp(0, math.min(width, height) / 2)),
          ),
        ),
      StickerShapeMask.circle => Path()..addOval(_inscribedCircle(rect)),
      StickerShapeMask.ellipse => Path()..addOval(rect),
      StickerShapeMask.heart => _heart(rect),
      StickerShapeMask.star => _star(rect, points: 5),
      StickerShapeMask.hexagon => _regularPolygon(rect, sides: 6),
      StickerShapeMask.squircle => Path()
        ..addRRect(
          RRect.fromRectAndRadius(
            rect,
            Radius.circular(math.min(width, height) * 0.22),
          ),
        ),
    };
  }

  static Rect _inscribedCircle(Rect rect) {
    final side = math.min(rect.width, rect.height);
    return Rect.fromCenter(
      center: rect.center,
      width: side,
      height: side,
    );
  }

  static Path _heart(Rect rect) {
    final w = rect.width;
    final h = rect.height;
    final path = Path();
    path.moveTo(rect.center.dx, rect.top + h * 0.28);
    path.cubicTo(
      rect.left + w * 0.1,
      rect.top,
      rect.left,
      rect.top + h * 0.45,
      rect.left + w * 0.25,
      rect.top + h * 0.62,
    );
    path.lineTo(rect.center.dx, rect.bottom - h * 0.05);
    path.lineTo(rect.right - w * 0.25, rect.top + h * 0.62);
    path.cubicTo(
      rect.right,
      rect.top + h * 0.45,
      rect.right - w * 0.1,
      rect.top,
      rect.center.dx,
      rect.top + h * 0.28,
    );
    path.close();
    return path;
  }

  static Path _star(Rect rect, {required int points}) {
    final cx = rect.center.dx;
    final cy = rect.center.dy;
    final outer = math.min(rect.width, rect.height) * 0.48;
    final inner = outer * 0.42;
    final path = Path();
    final total = points * 2;
    for (var i = 0; i < total; i++) {
      final angle = -math.pi / 2 + i * math.pi / points;
      final r = i.isEven ? outer : inner;
      final x = cx + math.cos(angle) * r;
      final y = cy + math.sin(angle) * r;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    return path;
  }

  static Path _regularPolygon(Rect rect, {required int sides}) {
    final cx = rect.center.dx;
    final cy = rect.center.dy;
    final radius = math.min(rect.width, rect.height) * 0.48;
    final path = Path();
    for (var i = 0; i < sides; i++) {
      final angle = -math.pi / 2 + i * 2 * math.pi / sides;
      final x = cx + math.cos(angle) * radius;
      final y = cy + math.sin(angle) * radius;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    return path;
  }
}
