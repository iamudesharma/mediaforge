import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../layer_coordinates.dart';
import '../models/layer_stack.dart';
import '../models/overlay_layer.dart';
import 'paint_canvas.dart';
import 'paint_stroke_painter.dart';
import 'transformable_layer.dart';

/// Renders all overlay layers on top of the image preview.
class LayerEditorOverlay extends StatefulWidget {
  const LayerEditorOverlay({
    super.key,
    required this.stack,
    required this.imageWidth,
    required this.imageHeight,
    required this.childSize,
    required this.viewerTransform,
    required this.paintMode,
    required this.onStackChanged,
    this.onTransformBegin,
    this.onUserImageStickerTap,
    this.onPaintStroke,
    this.onActiveStrokeUpdate,
    this.activePaintStrokeListenable,
    this.activePaintColor,
    this.activePaintWidth,
    this.activePaintOpacity,
  });

  final LayerStack stack;
  final int imageWidth;
  final int imageHeight;
  final Size childSize;
  final Matrix4 viewerTransform;
  final bool paintMode;
  final VoidCallback onStackChanged;
  final VoidCallback? onTransformBegin;
  final void Function(StickerLayer layer)? onUserImageStickerTap;
  final void Function(List<Offset> points, {required Size childSize})?
      onPaintStroke;
  final void Function(List<Offset> points)? onActiveStrokeUpdate;
  final ValueListenable<List<Offset>>? activePaintStrokeListenable;
  final Color? activePaintColor;
  final double? activePaintWidth;
  final double? activePaintOpacity;

  @override
  State<LayerEditorOverlay> createState() => _LayerEditorOverlayState();
}

class _LayerEditorOverlayState extends State<LayerEditorOverlay> {
  final _stackKey = GlobalKey();
  LayerCoordinates? _coords;
  int _coordsRevision = -1;
  List<OverlayLayer>? _hitTestLayers;
  int _hitTestRevision = -1;

  /// Selected layer last so its expanded pinch hit box wins the gesture arena.
  static List<OverlayLayer> _layersForHitTest(LayerStack stack) {
    final ordered = List<OverlayLayer>.from(stack.layers);
    final id = stack.selectedId;
    if (id == null) return ordered;
    final i = ordered.indexWhere((l) => l.id == id);
    if (i < 0) return ordered;
    final selected = ordered.removeAt(i);
    ordered.add(selected);
    return ordered;
  }

  LayerCoordinates _layerCoords() {
    if (_coords == null || _coordsRevision != widget.stack.revision) {
      _coords = LayerCoordinates(
        imageWidth: widget.imageWidth,
        imageHeight: widget.imageHeight,
        childSize: widget.childSize,
      );
      _coordsRevision = widget.stack.revision;
    }
    return _coords!;
  }

  List<OverlayLayer> _hitTestLayersList() {
    if (_hitTestLayers == null || _hitTestRevision != widget.stack.revision) {
      _hitTestLayers = _layersForHitTest(widget.stack);
      _hitTestRevision = widget.stack.revision;
    }
    return _hitTestLayers!;
  }

  RenderBox? get _stackBox {
    final ctx = _stackKey.currentContext;
    final ro = ctx?.findRenderObject();
    return ro is RenderBox ? ro : null;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stackBox = _stackBox;
        final childSize = constraints.biggest;
        return Stack(
          key: _stackKey,
          fit: StackFit.expand,
          children: [
            RepaintBoundary(
              child: CustomPaint(
                painter: CommittedPaintStrokePainter(
                  stack: widget.stack,
                  imageWidth: widget.imageWidth,
                  imageHeight: widget.imageHeight,
                  childSize: childSize,
                ),
              ),
            ),
            if (widget.activePaintStrokeListenable != null)
              RepaintBoundary(
                child: ValueListenableBuilder<List<Offset>>(
                  valueListenable: widget.activePaintStrokeListenable!,
                  builder: (context, stroke, _) {
                    return CustomPaint(
                      painter: ActivePaintStrokePainter(
                        imageWidth: widget.imageWidth,
                        imageHeight: widget.imageHeight,
                        childSize: childSize,
                        points: stroke,
                        color: widget.activePaintColor ?? const Color(0xFF4EDEA3),
                        width: widget.activePaintWidth ?? 8,
                        opacity: widget.activePaintOpacity ?? 0.9,
                      ),
                    );
                  },
                ),
              ),
        if (widget.paintMode)
          Positioned.fill(
            child: PaintCanvas(
              imageWidth: widget.imageWidth,
              imageHeight: widget.imageHeight,
              childSize: childSize,
              viewerTransform: widget.viewerTransform,
              onStroke: widget.onPaintStroke == null
                  ? null
                  : (pts) => widget.onPaintStroke!(
                        pts,
                        childSize: childSize,
                      ),
              onStrokeUpdate: widget.onActiveStrokeUpdate,
            ),
          ),
        if (stackBox != null)
          for (final layer in _hitTestLayersList())
            if (layer is! PaintStrokeLayer)
              TransformableLayer(
                key: ValueKey(layer.id),
                layer: layer,
                coords: _layerCoords(),
                stackBox: stackBox,
                selected: layer.id == widget.stack.selectedId,
                onTransformCommit: widget.onStackChanged,
                onTap: () {
                  widget.stack.select(layer.id);
                  widget.onStackChanged();
                  if (layer is StickerLayer &&
                      layer.userBytes != null &&
                      layer.userBytes!.isNotEmpty) {
                    widget.onUserImageStickerTap?.call(layer);
                  }
                },
                onDoubleTap: () {
                  widget.stack.remove(layer.id);
                  widget.onStackChanged();
                },
                onLongPress: () {
                  widget.stack.bringToFront(layer.id);
                  widget.onStackChanged();
                },
                onTransformBegin: widget.onTransformBegin,
              ),
          ],
        );
      },
    );
  }
}
