import 'package:flutter_test/flutter_test.dart';
import 'package:image_forge_editor/src/editor/models/layer_transform.dart';

void main() {
  group('LayerTransform.compose', () {
    test('multiply composes translation and scale', () {
      const outer = LayerTransform(centerX: 100, centerY: 50, scale: 2);
      const inner = LayerTransform(centerX: 10, centerY: 0, scale: 0.5);
      final world = LayerTransform.multiply(outer, inner);
      expect(world.centerX, closeTo(120, 0.01));
      expect(world.centerY, closeTo(50, 0.01));
      expect(world.scale, closeTo(1, 0.01));
    });

    test('applyDeltaAboutPivot translates all corners consistently', () {
      const t = LayerTransform(centerX: 50, centerY: 50);
      final moved = LayerTransform.applyDeltaAboutPivot(
        t: t,
        pivot: const Offset(0, 0),
        translation: const Offset(10, 0),
        scaleFactor: 1,
        rotationDelta: 0,
      );
      expect(moved.centerX, closeTo(60, 0.01));
      expect(moved.centerY, closeTo(50, 0.01));
    });
  });
}
