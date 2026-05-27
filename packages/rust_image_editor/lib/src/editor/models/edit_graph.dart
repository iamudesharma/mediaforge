import 'dart:typed_data';

import 'package:rust_image_editor/src/rust_image_editor.dart';

import '../services/filter_descriptor.dart';
import 'beauty_params.dart';

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

  /// Strip swipe mood ops (at most one is kept on replace).
  EditGraph withoutMoodFilter() {
    return EditGraph(
      ops.where((op) => !_isMoodOp(op)).toList(),
    );
  }

  /// Strip combo swipe look ops.
  EditGraph withoutSwipeLookFilter() {
    return EditGraph(
      ops.where((op) => !_isSwipeLookOp(op)).toList(),
    );
  }

  /// Strip committed beauty ops.
  EditGraph withoutBeautyFilter() {
    return EditGraph(
      ops.where((op) => !_isBeautyOp(op)).toList(),
    );
  }

  /// Replace the dedicated mood-filter slot (append mood last in pipeline).
  EditGraph replaceMoodFilter(FilterDescriptor? mood) {
    final kept = ops.where((op) => !_isMoodOp(op)).toList();
    if (mood != null) {
      kept.add(EditOp.filter(filter: mood.toImageFilter()));
    }
    return EditGraph(kept);
  }

  /// Replace the dedicated combo swipe look slot.
  EditGraph replaceSwipeLookFilter(FilterDescriptor? look) {
    final kept = ops.where((op) => !_isSwipeLookOp(op)).toList();
    if (look != null) {
      kept.add(EditOp.filter(filter: look.toImageFilter()));
    }
    return EditGraph(kept);
  }

  /// Replace the dedicated beauty slot (masks + landmarks in [EditorSession]).
  EditGraph replaceBeautyParams(BeautyParams? params) {
    final kept = ops.where((op) => !_isBeautyOp(op)).toList();
    final p = params?.clamped();
    if (p != null && p.hasEffect) {
      kept.add(EditOp.filter(filter: ImageFilter.beauty(params: p)));
    }
    return EditGraph(kept);
  }

  /// Legacy skin-only replace — maps to [replaceBeautyParams].
  EditGraph replaceBeautyFilter(double? strength) {
    final current = committedBeautyParams ?? BeautyParamsX.zero;
    if (strength == null || strength <= 0.001) {
      final next = current.copyWith(skinSmooth: 0);
      return replaceBeautyParams(next.hasEffect ? next : null);
    }
    return replaceBeautyParams(current.copyWith(skinSmooth: strength.clamp(0.0, 1.0)));
  }

  /// Committed regional beauty params, if any.
  BeautyParams? get committedBeautyParams {
    for (final op in ops.reversed) {
      if (op is EditOp_Filter) {
        final filter = op.filter;
        if (filter is ImageFilter_Beauty) {
          return filter.params;
        }
        if (filter is ImageFilter_SkinSmooth) {
          return BeautyParams(
            skinSmooth: filter.strength,
            eyeBrighten: 0,
            lipTint: LipTintPreset.none,
            lipTintStrength: 0,
            lipPlump: 0,
            blush: 0,
            underEye: 0,
            teethWhiten: 0,
            skinPreserveDetail: 0,
            eyeEnlarge: 0,
            jawSlim: 0,
            noseSlim: 0,
            faceSlim: 0,
            chinVshape: 0,
          );
        }
      }
    }
    return null;
  }

  /// Committed skin smooth strength (0–1), if any.
  double? get committedSkinSmoothStrength =>
      committedBeautyParams?.skinSmooth;

  /// Committed swipe mood filter, if any.
  MoodFilterPreset? get committedMoodPreset {
    for (final op in ops.reversed) {
      if (op is EditOp_Filter) {
        final filter = op.filter;
        if (filter is ImageFilter_Mood) {
          return filter.preset;
        }
      }
    }
    return null;
  }

  /// Committed combo swipe look, if any.
  SwipeLookPreset? get committedSwipeLookPreset {
    for (final op in ops.reversed) {
      if (op is EditOp_Filter) {
        final filter = op.filter;
        if (filter is ImageFilter_SwipeLook) {
          return filter.preset;
        }
      }
    }
    return null;
  }

  static bool _isMoodOp(EditOp op) {
    if (op is EditOp_Filter) {
      return op.filter is ImageFilter_Mood;
    }
    return false;
  }

  static bool _isSwipeLookOp(EditOp op) {
    if (op is EditOp_Filter) {
      return op.filter is ImageFilter_SwipeLook;
    }
    return false;
  }

  static bool _isBeautyOp(EditOp op) {
    if (op is EditOp_Filter) {
      return op.filter is ImageFilter_Beauty ||
          op.filter is ImageFilter_SkinSmooth;
    }
    return false;
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
