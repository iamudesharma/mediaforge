import 'dart:typed_data';

import 'package:rust_image/src/rust_image_editor.dart';

import '../services/filter_descriptor.dart';

/// Non-destructive filter stack (Sprint 3). Replay on edit-scale for preview, full-res on export.
class EditGraph {
  EditGraph([List<EditOp>? ops]) : ops = List.unmodifiable(ops ?? const []);

  final List<EditOp> ops;

  bool get isEmpty => ops.isEmpty;

  bool get isNotEmpty => ops.isNotEmpty;

  int get length => ops.length;

  EditGraph appendFilter(FilterDescriptor descriptor) {
    return EditGraph([
      ...ops,
      EditOp.filter(filter: descriptor.toImageFilter()),
    ]);
  }

  EditGraph appendOp(EditOp op) {
    return EditGraph([...ops, op]);
  }

  EditGraph copy() => EditGraph([...ops]);

  @override
  bool operator ==(Object other) {
    if (other is! EditGraph || other.ops.length != ops.length) return false;
    for (var i = 0; i < ops.length; i++) {
      if (ops[i] != other.ops[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(ops);
}

/// Undo/redo snapshot: filter op list + optional baked pixels after draw/export ops.
class EditGraphState {
  const EditGraphState({
    required this.graph,
    this.bakedFull,
    this.bakedEdit,
  });

  final EditGraph graph;
  final RgbaImageBuffer? bakedFull;
  final RgbaImageBuffer? bakedEdit;

  EditGraphState copy() => EditGraphState(
        graph: graph.copy(),
        bakedFull: bakedFull != null ? _clone(bakedFull!) : null,
        bakedEdit: bakedEdit != null ? _clone(bakedEdit!) : null,
      );

  static RgbaImageBuffer _clone(RgbaImageBuffer b) => RgbaImageBuffer(
        width: b.width,
        height: b.height,
        pixels: Uint8List.fromList(b.pixels),
      );
}
