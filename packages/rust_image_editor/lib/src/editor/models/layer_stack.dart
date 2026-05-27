import 'dart:math' as math;
import 'dart:ui';

import '../services/layer_bounds.dart';
import 'layer_transform.dart';
import 'overlay_layer.dart';

/// Non-destructive overlay layers on top of the image.
class LayerStack {
  LayerStack([
    List<OverlayLayer>? layers,
    String? selectedId,
    Set<String>? selectedIds,
  ]) : layers = List<OverlayLayer>.from(layers ?? const []) {
    if (selectedIds != null && selectedIds.isNotEmpty) {
      this.selectedIds.addAll(selectedIds);
      _primarySelectedId =
          selectedId ?? selectedIds.last;
    } else if (selectedId != null) {
      this.selectedIds.add(selectedId);
      _primarySelectedId = selectedId;
    }
  }

  final List<OverlayLayer> layers;
  final Set<String> selectedIds = {};

  String? _primarySelectedId;

  /// Primary selection (backward compatible).
  String? get selectedId => _primarySelectedId;

  set selectedId(String? id) {
    if (id == null) {
      selectedIds.clear();
      _primarySelectedId = null;
    } else {
      selectedIds
        ..clear()
        ..add(id);
      _primarySelectedId = id;
    }
    bumpRevision();
  }

  /// Bumped when layers are added/removed/reordered/selection changes.
  int revision = 0;

  void bumpRevision() => revision++;

  bool get isEmpty => layers.isEmpty;

  bool get isNotEmpty => layers.isNotEmpty;

  int get length => layers.length;

  bool isSelected(String id) => selectedIds.contains(id);

  bool get hasMultiSelection => selectedIds.length > 1;

  OverlayLayer? get selected {
    final id = _primarySelectedId;
    if (id == null) return null;
    return findById(id);
  }

  OverlayLayer? findById(String id) {
    for (final l in layers) {
      if (l.id == id) return l;
      if (l is GroupLayer) {
        for (final c in l.children) {
          if (c.id == id) return c;
        }
      }
    }
    return null;
  }

  LayerStack copy() {
    final c = LayerStack(
      layers.map((l) => l.copy()).toList(),
      _primarySelectedId,
      Set<String>.from(selectedIds),
    );
    c.revision = revision;
    return c;
  }

  void add(OverlayLayer layer, {bool select = true}) {
    layers.add(layer);
    if (select) {
      selectOnly(layer.id);
    } else {
      bumpRevision();
    }
  }

  void remove(String id) {
    layers.removeWhere((l) => l.id == id);
    selectedIds.remove(id);
    if (_primarySelectedId == id || selectedIds.isEmpty) {
      if (layers.isEmpty) {
        _primarySelectedId = null;
        selectedIds.clear();
      } else {
        _primarySelectedId = layers.last.id;
        selectedIds
          ..clear()
          ..add(_primarySelectedId!);
      }
    } else {
      _primarySelectedId = selectedIds.last;
    }
    bumpRevision();
  }

  void bringToFront(String id) {
    final i = layers.indexWhere((l) => l.id == id);
    if (i < 0 || i == layers.length - 1) return;
    final layer = layers.removeAt(i);
    layers.add(layer);
    selectOnly(id);
  }

  void sendToBack(String id) {
    final i = layers.indexWhere((l) => l.id == id);
    if (i <= 0) return;
    final layer = layers.removeAt(i);
    layers.insert(0, layer);
    selectOnly(id);
  }

  void moveUp(String id) {
    final i = layers.indexWhere((l) => l.id == id);
    if (i < 0 || i >= layers.length - 1) return;
    final layer = layers.removeAt(i);
    layers.insert(i + 1, layer);
    selectOnly(id);
  }

  void moveDown(String id) {
    final i = layers.indexWhere((l) => l.id == id);
    if (i <= 0) return;
    final layer = layers.removeAt(i);
    layers.insert(i - 1, layer);
    selectOnly(id);
  }

  void insertAt(int index, String id) {
    final i = layers.indexWhere((l) => l.id == id);
    if (i < 0) return;
    final layer = layers.removeAt(i);
    final clamped = index.clamp(0, layers.length);
    layers.insert(clamped, layer);
    selectOnly(id);
  }

  void setVisible(String id, bool visible) {
    final layer = findById(id);
    if (layer == null || layer.visible == visible) return;
    layer.visible = visible;
    bumpRevision();
  }

  void select(String? id) => selectOnly(id);

  void selectOnly(String? id) {
    selectedIds.clear();
    if (id != null) selectedIds.add(id);
    _primarySelectedId = id;
    bumpRevision();
  }

  void toggleSelect(String id) {
    if (selectedIds.contains(id)) {
      selectedIds.remove(id);
      if (_primarySelectedId == id) {
        _primarySelectedId = selectedIds.isEmpty ? null : selectedIds.last;
      }
    } else {
      selectedIds.add(id);
      _primarySelectedId = id;
    }
    bumpRevision();
  }

  void selectMany(Iterable<String> ids) {
    selectedIds
      ..clear()
      ..addAll(ids);
    _primarySelectedId = selectedIds.isEmpty ? null : selectedIds.last;
    bumpRevision();
  }

  void clearSelection() {
    if (selectedIds.isEmpty && _primarySelectedId == null) return;
    selectedIds.clear();
    _primarySelectedId = null;
    bumpRevision();
  }

  /// Select top-level layers whose bounds intersect [rect] (image pixels).
  void selectAllInRect(Rect rect) {
    final hits = <String>[];
    for (final layer in layers) {
      if (!layer.visible) continue;
      final b = LayerBounds.boundsInImagePixels(layer);
      if (b != null && LayerBounds.intersects(b, rect)) {
        hits.add(layer.id);
      }
    }
    selectMany(hits);
  }

  void updateTransform(String id, LayerTransform t) {
    final layer = findById(id);
    if (layer == null) return;
    layer.transform = t;
  }

  void clear() {
    layers.clear();
    selectedIds.clear();
    _primarySelectedId = null;
    bumpRevision();
  }

  List<PaintStrokeLayer> get paintStrokes =>
      layers.whereType<PaintStrokeLayer>().toList();

  /// Top-level transformable layers for multi-select (excludes paint).
  List<OverlayLayer> get selectedTransformableLayers {
    final out = <OverlayLayer>[];
    for (final id in selectedIds) {
      final l = findById(id);
      if (l == null || l is PaintStrokeLayer) continue;
      if (layers.any((x) => x.id == id)) out.add(l);
    }
    return out;
  }

  /// Flatten groups for bake/export.
  List<OverlayLayer> flattenForBake() {
    final out = <OverlayLayer>[];
    for (final layer in layers) {
      if (!layer.visible) continue;
      if (layer is GroupLayer) {
        for (final child in layer.children) {
          if (!child.visible) continue;
          if (child is PaintStrokeLayer) {
            final t = LayerTransform.multiply(layer.transform, child.transform);
            final c = math.cos(t.rotationRad);
            final s = math.sin(t.rotationRad);
            final pts = child.points
                .map((p) {
                  final sx = p.dx * t.scale;
                  final sy = p.dy * t.scale;
                  return Offset(
                    t.centerX + sx * c - sy * s,
                    t.centerY + sx * s + sy * c,
                  );
                })
                .toList();
            out.add(
              PaintStrokeLayer(
                id: child.id,
                transform: const LayerTransform(),
                visible: child.visible,
                points: pts,
                color: child.color,
                width: child.width,
                opacity: child.opacity,
                brush: child.brush,
                filled: child.filled,
              ),
            );
          } else {
            final flat = child.copy();
            flat.transform =
                LayerTransform.multiply(layer.transform, child.transform);
            out.add(flat);
          }
        }
      } else {
        out.add(layer);
      }
    }
    return out;
  }

  /// Group ≥2 top-level layers; returns error message or null on success.
  String? groupSelected() {
    if (selectedIds.length < 2) {
      return 'Select at least two layers to group';
    }
    final toGroup = <OverlayLayer>[];
    for (final id in selectedIds) {
      OverlayLayer? l;
      for (final x in layers) {
        if (x.id == id) {
          l = x;
          break;
        }
      }
      if (l == null) return 'Layer not found';
      if (l is GroupLayer) return 'Cannot nest groups';
      if (l is PaintStrokeLayer) {
        return 'Paint strokes cannot be grouped (duplicate/delete only)';
      }
      toGroup.add(l);
    }
    if (toGroup.length < 2) return 'Select at least two layers to group';

    final bounds = LayerBounds.unionBounds(toGroup);
    if (bounds == null) return 'Could not compute group bounds';
    final pivot = bounds.center;

    final locals = <OverlayLayer>[];
    for (final child in toGroup) {
      final local = child.copy();
      local.transform = LayerTransform.localFromWorld(
        LayerTransform(centerX: pivot.dx, centerY: pivot.dy),
        child.transform,
      );
      locals.add(local);
    }

    var maxIndex = -1;
    for (final id in selectedIds) {
      final i = layers.indexWhere((l) => l.id == id);
      if (i > maxIndex) maxIndex = i;
    }

    for (final id in selectedIds.toList()) {
      layers.removeWhere((l) => l.id == id);
    }

    final group = GroupLayer(
      id: newLayerId(),
      transform: LayerTransform(centerX: pivot.dx, centerY: pivot.dy),
      children: locals,
    );
    layers.insert(maxIndex.clamp(0, layers.length), group);
    selectOnly(group.id);
    return null;
  }

  String? ungroup(String groupId) {
    final i = layers.indexWhere((l) => l.id == groupId);
    if (i < 0) return 'Group not found';
    final layer = layers[i];
    if (layer is! GroupLayer) return 'Not a group';

    final worldChildren = <OverlayLayer>[];
    for (final child in layer.children) {
      final w = child.copy();
      w.transform = LayerTransform.multiply(layer.transform, child.transform);
      worldChildren.add(w);
    }

    layers.removeAt(i);
    layers.insertAll(i, worldChildren);
    selectMany(worldChildren.map((c) => c.id));
    return null;
  }
}

// Fix flattenForBake - I used invalid syntax with import inside method. Let me fix layer_stack.dart
