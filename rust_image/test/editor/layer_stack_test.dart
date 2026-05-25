import 'package:flutter_test/flutter_test.dart';
import 'package:rust_image/src/editor/models/layer_stack.dart';
import 'package:rust_image/src/editor/models/layer_transform.dart';
import 'package:rust_image/src/editor/models/overlay_layer.dart';

EmojiLayer _emoji(String id) => EmojiLayer(
      id: id,
      transform: const LayerTransform(),
      glyph: ':)',
    );

PaintStrokeLayer _stroke(String id) => PaintStrokeLayer(
      id: id,
      transform: const LayerTransform(),
      points: const <Offset>[Offset(0, 0), Offset(1, 1)],
    );

ShapeLayer _shape(String id) => ShapeLayer(
      id: id,
      transform: const LayerTransform(),
      shapeKind: ShapeKind.rect,
    );

TextLayer _text(String id) => TextLayer(
      id: id,
      transform: const LayerTransform(),
      text: 'hi',
    );

void main() {
  group('LayerStack', () {
    test('add() selects the new layer by default and bumps the revision', () {
      final stack = LayerStack();
      expect(stack.isEmpty, isTrue);
      expect(stack.revision, 0);

      final layer = _emoji('a');
      stack.add(layer);

      expect(stack.length, 1);
      expect(stack.selectedId, 'a');
      expect(stack.selected, layer);
      expect(stack.revision, 1);
    });

    test('add(select: false) leaves the current selection alone', () {
      final stack = LayerStack();
      stack.add(_emoji('a'));
      stack.add(_emoji('b'), select: false);

      expect(stack.selectedId, 'a');
      expect(stack.length, 2);
      expect(stack.revision, 2);
    });

    test('bumpRevision increments the revision counter', () {
      final stack = LayerStack();
      expect(stack.revision, 0);
      stack.bumpRevision();
      expect(stack.revision, 1);
      stack.bumpRevision();
      expect(stack.revision, 2);
    });

    test('remove(selected) reselects the new last layer', () {
      final stack = LayerStack()
        ..add(_emoji('a'))
        ..add(_emoji('b'))
        ..add(_emoji('c'));

      expect(stack.selectedId, 'c');
      stack.remove('c');

      expect(stack.length, 2);
      expect(stack.selectedId, 'b');
    });

    test('remove(selected) nulls selectedId when the stack becomes empty', () {
      final stack = LayerStack()..add(_emoji('only'));
      stack.remove('only');

      expect(stack.isEmpty, isTrue);
      expect(stack.selectedId, isNull);
    });

    test('remove(non-selected) preserves the current selection', () {
      final stack = LayerStack()
        ..add(_emoji('a'))
        ..add(_emoji('b'));
      expect(stack.selectedId, 'b');

      stack.remove('a');

      expect(stack.length, 1);
      expect(stack.selectedId, 'b');
    });

    test('bringToFront moves the matching layer to the end and selects it',
        () {
      final stack = LayerStack()
        ..add(_emoji('a'))
        ..add(_emoji('b'))
        ..add(_emoji('c'));

      stack.bringToFront('a');

      expect(stack.layers.map((l) => l.id).toList(), ['b', 'c', 'a']);
      expect(stack.selectedId, 'a');
    });

    test('bringToFront on the top layer is a no-op', () {
      final stack = LayerStack()
        ..add(_emoji('a'))
        ..add(_emoji('b'));
      final revBefore = stack.revision;

      stack.bringToFront('b');

      expect(stack.layers.map((l) => l.id).toList(), ['a', 'b']);
      expect(stack.revision, revBefore);
    });

    test('clear empties the layers and nulls selectedId', () {
      final stack = LayerStack()
        ..add(_emoji('a'))
        ..add(_emoji('b'));

      stack.clear();

      expect(stack.isEmpty, isTrue);
      expect(stack.selectedId, isNull);
    });

    test('paintStrokes returns only PaintStrokeLayer instances in order', () {
      final s1 = _stroke('s1');
      final s2 = _stroke('s2');
      final stack = LayerStack()
        ..add(_emoji('e'))
        ..add(s1)
        ..add(_shape('shape'))
        ..add(_text('t'))
        ..add(s2);

      final strokes = stack.paintStrokes;

      expect(strokes, hasLength(2));
      expect(strokes, everyElement(isA<PaintStrokeLayer>()));
      expect(strokes.map((s) => s.id).toList(), ['s1', 's2']);
    });
  });
}
