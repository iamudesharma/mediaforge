import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_image/src/editor/models/layer_transform.dart';
import 'package:rust_image/src/editor/models/overlay_layer.dart';
import 'package:rust_image/src/editor/services/paint_hit_test.dart';

void main() {
  group('PaintHitTest.distanceToSegment', () {
    test('returns distance to nearest point on segment', () {
      expect(
        PaintHitTest.distanceToSegment(const Offset(5, 5), const Offset(0, 0), const Offset(10, 0)),
        closeTo(5, 0.01),
      );
      expect(
        PaintHitTest.distanceToSegment(const Offset(0, 0), const Offset(0, 0), const Offset(10, 0)),
        0,
      );
    });
  });

  group('PaintHitTest.hitTestLine', () {
    test('hits near line segment within half width', () {
      expect(
        PaintHitTest.hitTestLine(
          const Offset(0, 0),
          const Offset(100, 0),
          const Offset(50, 3),
          10,
        ),
        isTrue,
      );
      expect(
        PaintHitTest.hitTestLine(
          const Offset(0, 0),
          const Offset(100, 0),
          const Offset(50, 20),
          10,
        ),
        isFalse,
      );
    });
  });

  group('PaintHitTest.hitTestRect', () {
    test('filled rect hits interior', () {
      expect(
        PaintHitTest.hitTestRect(
          const Offset(10, 10),
          const Offset(50, 50),
          const Offset(30, 30),
          4,
          true,
        ),
        isTrue,
      );
    });

    test('hollow rect hits border only', () {
      expect(
        PaintHitTest.hitTestRect(
          const Offset(10, 10),
          const Offset(50, 50),
          const Offset(30, 30),
          4,
          false,
        ),
        isFalse,
      );
      expect(
        PaintHitTest.hitTestRect(
          const Offset(10, 10),
          const Offset(50, 50),
          const Offset(10, 30),
          4,
          false,
        ),
        isTrue,
      );
    });
  });

  group('PaintHitTest.hitTestCircle', () {
    test('filled circle hits interior', () {
      expect(
        PaintHitTest.hitTestCircle(
          const Offset(50, 50),
          20,
          const Offset(55, 55),
          4,
          true,
        ),
        isTrue,
      );
    });

    test('outline circle hits near boundary', () {
      expect(
        PaintHitTest.hitTestCircle(
          const Offset(50, 50),
          20,
          const Offset(70, 50),
          6,
          false,
        ),
        isTrue,
      );
    });
  });

  group('PaintHitTest.hitTestLayer', () {
    test('freestyle pen stroke', () {
      final layer = PaintStrokeLayer(
        id: '1',
        transform: const LayerTransform(),
        points: [const Offset(0, 0), const Offset(100, 0)],
        width: 8,
        brush: PaintBrushKind.pen,
      );
      expect(PaintHitTest.hitTestLayer(layer, const Offset(50, 2)), isTrue);
    });

    test('censor blur treats region as filled', () {
      final layer = PaintStrokeLayer(
        id: '1',
        transform: const LayerTransform(),
        points: [const Offset(10, 10), const Offset(40, 40)],
        width: 4,
        brush: PaintBrushKind.blur,
      );
      expect(PaintHitTest.hitTestLayer(layer, const Offset(25, 25)), isTrue);
    });

    test('object eraser stroke uses freestyle path', () {
      final layer = PaintStrokeLayer(
        id: '1',
        transform: const LayerTransform(),
        points: [const Offset(0, 0), const Offset(50, 50)],
        width: 12,
        brush: PaintBrushKind.eraser,
      );
      expect(PaintHitTest.hitTestLayer(layer, const Offset(25, 25)), isTrue);
    });
  });
}
