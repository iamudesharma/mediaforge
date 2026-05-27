import 'package:flutter_test/flutter_test.dart';
import 'package:rust_image/src/editor/models/layer_transform.dart';
import 'package:rust_image/src/editor/models/overlay_layer.dart';
import 'package:rust_image/src/editor/services/layer_bounds.dart';

void main() {
  group('LayerBounds', () {
    test('boundsInImagePixels returns rect for emoji', () {
      final layer = EmojiLayer(
        id: 'e',
        transform: const LayerTransform(centerX: 100, centerY: 100, scale: 1),
        glyph: '🙂',
        fontSize: 64,
      );
      final rect = LayerBounds.boundsInImagePixels(layer);
      expect(rect, isNotNull);
      expect(rect!.contains(const Offset(100, 100)), isTrue);
    });

    test('unionBounds includes both layers', () {
      final a = EmojiLayer(
        id: 'a',
        transform: const LayerTransform(centerX: 50, centerY: 50),
        glyph: 'a',
      );
      final b = EmojiLayer(
        id: 'b',
        transform: const LayerTransform(centerX: 200, centerY: 200),
        glyph: 'b',
      );
      final union = LayerBounds.unionBounds([a, b]);
      expect(union, isNotNull);
      expect(union!.left, lessThan(50));
      expect(union.right, greaterThan(200));
    });
  });
}
