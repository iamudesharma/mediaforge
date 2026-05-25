import 'layer_transform.dart';
import 'overlay_layer.dart';

/// Non-destructive overlay layers on top of the image.
class LayerStack {
  LayerStack([List<OverlayLayer>? layers, this.selectedId])
      : layers = List<OverlayLayer>.from(layers ?? const []);

  final List<OverlayLayer> layers;
  String? selectedId;

  /// Bumped when layers are added/removed/reordered (not on in-gesture transform).
  int revision = 0;

  void bumpRevision() => revision++;

  bool get isEmpty => layers.isEmpty;

  bool get isNotEmpty => layers.isNotEmpty;

  int get length => layers.length;

  OverlayLayer? get selected {
    if (selectedId == null) return null;
    for (final l in layers) {
      if (l.id == selectedId) return l;
    }
    return null;
  }

  LayerStack copy() {
    final c = LayerStack(
      layers.map((l) => l.copy()).toList(),
      selectedId,
    );
    c.revision = revision;
    return c;
  }

  void add(OverlayLayer layer, {bool select = true}) {
    layers.add(layer);
    if (select) selectedId = layer.id;
    bumpRevision();
  }

  void remove(String id) {
    layers.removeWhere((l) => l.id == id);
    if (selectedId == id) {
      selectedId = layers.isEmpty ? null : layers.last.id;
    }
    bumpRevision();
  }

  void bringToFront(String id) {
    final i = layers.indexWhere((l) => l.id == id);
    if (i < 0 || i == layers.length - 1) return;
    final layer = layers.removeAt(i);
    layers.add(layer);
    selectedId = id;
    bumpRevision();
  }

  void select(String? id) {
    if (selectedId == id) return;
    selectedId = id;
    bumpRevision();
  }

  void updateTransform(String id, LayerTransform t) {
    final layer = layers.cast<OverlayLayer?>().firstWhere(
      (l) => l!.id == id,
      orElse: () => null,
    );
    if (layer == null) return;
    layer.transform = t;
  }

  void clear() {
    layers.clear();
    selectedId = null;
  }

  List<PaintStrokeLayer> get paintStrokes =>
      layers.whereType<PaintStrokeLayer>().toList();
}
