import 'package:flutter_test/flutter_test.dart';
import 'package:rust_image_editor/src/editor/models/layer_stack.dart';
import 'package:rust_image_editor/src/editor/models/layer_transform.dart';
import 'package:rust_image_editor/src/editor/models/overlay_layer.dart';

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

    test('setVisible toggles visibility and bumps revision', () {
      final stack = LayerStack()..add(_emoji('a'));
      final rev = stack.revision;
      stack.setVisible('a', false);
      expect(stack.layers.first.visible, isFalse);
      expect(stack.revision, rev + 1);
      stack.setVisible('a', true);
      expect(stack.layers.first.visible, isTrue);
    });

    test('sendToBack moves layer to index 0', () {
      final stack = LayerStack()
        ..add(_emoji('a'))
        ..add(_emoji('b'));
      stack.sendToBack('b');
      expect(stack.layers.map((l) => l.id).toList(), ['b', 'a']);
    });

    test('moveUp and moveDown swap with neighbor', () {
      final stack = LayerStack()
        ..add(_emoji('a'))
        ..add(_emoji('b'))
        ..add(_emoji('c'));
      stack.moveUp('a');
      expect(stack.layers.map((l) => l.id).toList(), ['b', 'a', 'c']);
      stack.moveDown('c');
      expect(stack.layers.map((l) => l.id).toList(), ['b', 'c', 'a']);
    });

    test('insertAt reorders layer', () {
      final stack = LayerStack()
        ..add(_emoji('a'))
        ..add(_emoji('b'))
        ..add(_emoji('c'));
      stack.insertAt(0, 'c');
      expect(stack.layers.map((l) => l.id).toList(), ['c', 'a', 'b']);
    });

    test('copy preserves visible flag', () {
      final layer = _emoji('a');
      layer.visible = false;
      final stack = LayerStack([layer]);
      expect(stack.copy().layers.first.visible, isFalse);
    });

    test('selectMany and isSelected track multiple layers', () {
      final stack = LayerStack()
        ..add(_emoji('a'), select: false)
        ..add(_emoji('b'), select: false)
        ..add(_emoji('c'), select: false);
      stack.selectMany(['a', 'c']);
      expect(stack.isSelected('a'), isTrue);
      expect(stack.isSelected('b'), isFalse);
      expect(stack.isSelected('c'), isTrue);
      expect(stack.selectedId, 'c');
      expect(stack.hasMultiSelection, isTrue);
    });

    test('toggleSelect adds and removes from selection', () {
      final stack = LayerStack()..add(_emoji('a'));
      stack.toggleSelect('a');
      expect(stack.isSelected('a'), isFalse);
      stack.toggleSelect('a');
      expect(stack.isSelected('a'), isTrue);
    });

    test('groupSelected merges layers into GroupLayer', () {
      final stack = LayerStack()
        ..add(_emoji('a'), select: false)
        ..add(_emoji('b'), select: false);
      stack.selectMany(['a', 'b']);
      expect(stack.groupSelected(), isNull);
      expect(stack.length, 1);
      expect(stack.layers.single, isA<GroupLayer>());
      expect((stack.layers.single as GroupLayer).children, hasLength(2));
    });

    test('ungroup restores children at group index', () {
      final stack = LayerStack()
        ..add(_emoji('a'), select: false)
        ..add(_emoji('b'), select: false);
      stack.selectMany(['a', 'b']);
      stack.groupSelected();
      final groupId = stack.layers.single.id;
      stack.ungroup(groupId);
      expect(stack.length, 2);
      expect(stack.layers.every((l) => l is! GroupLayer), isTrue);
    });

    test('flattenForBake expands group children', () {
      final stack = LayerStack()
        ..add(_emoji('a'), select: false)
        ..add(_emoji('b'), select: false);
      stack.selectMany(['a', 'b']);
      stack.groupSelected();
      final flat = stack.flattenForBake();
      expect(flat, hasLength(2));
      expect(flat.every((l) => l is! GroupLayer), isTrue);
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
