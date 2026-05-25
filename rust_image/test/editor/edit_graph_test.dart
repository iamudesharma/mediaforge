import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rust_image/rust_image.dart';
import 'package:rust_image/src/editor/models/edit_graph.dart';

void main() {
  group('EditGraph', () {
    test('default constructor produces an empty graph', () {
      final graph = EditGraph();
      expect(graph.length, 0);
      expect(graph.isEmpty, isTrue);
      expect(graph.isNotEmpty, isFalse);
      expect(graph.ops, isEmpty);
    });

    test('appendOp returns a new instance and leaves the original unchanged',
        () {
      final original = EditGraph();
      const op = EditOp.filter(filter: ImageFilter.sharpen());
      final next = original.appendOp(op);

      expect(identical(original, next), isFalse);
      expect(original.length, 0);
      expect(original.ops, isEmpty);
      expect(next.length, 1);
      expect(next.ops.single, op);
    });

    test('appendFilter adds a filter op derived from the descriptor', () {
      final original = EditGraph();
      final next = original.appendFilter(
        FilterDescriptor.brightness(amount: 10),
      );

      expect(identical(original, next), isFalse);
      expect(original.length, 0);
      expect(next.length, 1);
      expect(next.ops.single, isA<EditOp_Filter>());

      final filterOp = next.ops.single as EditOp_Filter;
      expect(filterOp.filter, const ImageFilter.brightness(amount: 10));
    });

    test('copy returns a separate but equal instance', () {
      final original = EditGraph().appendFilter(
        FilterDescriptor.contrast(amount: 1.2),
      );
      final clone = original.copy();

      expect(identical(original, clone), isFalse);
      expect(clone, equals(original));
      expect(clone.ops, equals(original.ops));
    });

    test('== and hashCode match across two graphs with the same ops', () {
      final a = EditGraph()
          .appendFilter(FilterDescriptor.brightness(amount: 10))
          .appendFilter(FilterDescriptor.contrast(amount: 1.1));
      final b = EditGraph()
          .appendFilter(FilterDescriptor.brightness(amount: 10))
          .appendFilter(FilterDescriptor.contrast(amount: 1.1));

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('== is false when the op lists differ', () {
      final a = EditGraph().appendFilter(
        FilterDescriptor.brightness(amount: 10),
      );
      final b = EditGraph().appendFilter(
        FilterDescriptor.brightness(amount: 20),
      );

      expect(a == b, isFalse);
    });
  });

  group('EditGraphState', () {
    test('copy() deep-clones bakedFull.pixels', () {
      final pixels = Uint8List.fromList(<int>[
        0, 0, 0, 255,
        255, 255, 255, 255,
        128, 128, 128, 255,
        64, 64, 64, 255,
      ]);
      final buffer = RgbaImageBuffer(
        width: 2,
        height: 2,
        pixels: pixels,
      );
      final state = EditGraphState(
        graph: EditGraph().appendFilter(
          FilterDescriptor.brightness(amount: 5),
        ),
        bakedFull: buffer,
      );

      final clone = state.copy();

      expect(identical(state, clone), isFalse);
      expect(identical(clone.bakedFull, buffer), isFalse);
      expect(identical(clone.bakedFull!.pixels, buffer.pixels), isFalse);
      expect(clone.bakedFull!.width, 2);
      expect(clone.bakedFull!.height, 2);
      expect(clone.bakedFull!.pixels, equals(buffer.pixels));

      clone.bakedFull!.pixels[0] = 99;
      expect(buffer.pixels[0], 0);
    });

    test('copy() leaves null buffers as null and clones the graph', () {
      final state = EditGraphState(graph: EditGraph());
      final clone = state.copy();

      expect(clone.bakedFull, isNull);
      expect(clone.bakedEdit, isNull);
      expect(identical(state.graph, clone.graph), isFalse);
      expect(clone.graph, equals(state.graph));
    });
  });
}
