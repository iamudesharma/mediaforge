import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_image/src/editor/models/overlay_layer.dart';
import 'package:rust_image/src/editor/widgets/paint_stroke_painter.dart';

void main() {
  group('paintConfigForBrush', () {
    test('eraser uses clear blend mode', () {
      final cfg = paintConfigForBrush(
        brush: PaintBrushKind.eraser,
        color: Colors.red,
        opacity: 1,
        strokeWidth: 8,
      );
      expect(cfg.paint.blendMode, BlendMode.clear);
    });

    test('highlighter uses plus blend and low effective opacity', () {
      final cfg = paintConfigForBrush(
        brush: PaintBrushKind.highlighter,
        color: const Color(0xFFFF0000),
        opacity: 1,
        strokeWidth: 8,
      );
      expect(cfg.paint.blendMode, BlendMode.plus);
      expect(cfg.paint.color.a, lessThan(140));
      expect(cfg.useLayer, isTrue);
    });

    test('marker widens stroke', () {
      final pen = paintConfigForBrush(
        brush: PaintBrushKind.pen,
        color: Colors.white,
        opacity: 1,
        strokeWidth: 10,
      );
      final marker = paintConfigForBrush(
        brush: PaintBrushKind.marker,
        color: Colors.white,
        opacity: 1,
        strokeWidth: 10,
      );
      expect(marker.paint.strokeWidth, greaterThan(pen.paint.strokeWidth));
    });

    test('neon applies blur mask', () {
      final cfg = paintConfigForBrush(
        brush: PaintBrushKind.neon,
        color: Colors.cyan,
        opacity: 1,
        strokeWidth: 8,
      );
      expect(cfg.paint.maskFilter, isNotNull);
    });
  });
}
