import 'dart:math' as math;
import 'dart:ui' show ImageFilter;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../layer_coordinates.dart';
import '../models/layer_stack.dart';
import '../models/layer_transform.dart';
import '../models/overlay_layer.dart';
import 'paint_canvas.dart';
import 'paint_stroke_painter.dart';
import 'multi_selection_transform.dart';
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
    this.layersToolActive = false,
    required this.eraserMode,
    required this.onStackChanged,
    this.onTransformBegin,
    this.onUserImageStickerTap,
    this.onTextLayerDoubleTap,
    this.onPaintStroke,
    this.onActiveStrokeUpdate,
    this.activePaintStrokeListenable,
    this.activePaintColor,
    this.activePaintWidth,
    this.activePaintOpacity,
    this.activePaintBrush,
    this.activePaintFilled = false,
    this.hiddenTextLayerId,
    this.onObjectErase,
  });

  final LayerStack stack;
  final int imageWidth;
  final int imageHeight;
  final Size childSize;
  final Matrix4 viewerTransform;
  final bool paintMode;
  final bool layersToolActive;
  final EraserMode eraserMode;
  final VoidCallback onStackChanged;
  final VoidCallback? onTransformBegin;
  final void Function(StickerLayer layer)? onUserImageStickerTap;
  final void Function(TextLayer layer)? onTextLayerDoubleTap;
  final void Function(List<Offset> points, {required Size childSize})?
      onPaintStroke;
  final void Function(List<Offset> points)? onActiveStrokeUpdate;
  final ValueListenable<List<Offset>>? activePaintStrokeListenable;
  final Color? activePaintColor;
  final double? activePaintWidth;
  final double? activePaintOpacity;
  final PaintBrushKind? activePaintBrush;
  final bool activePaintFilled;

  /// Hide rasterized text while inline edit overlay is open.
  final String? hiddenTextLayerId;
  final void Function(Offset imagePixel)? onObjectErase;

  @override
  State<LayerEditorOverlay> createState() => _LayerEditorOverlayState();
}

class _LayerEditorOverlayState extends State<LayerEditorOverlay> {
  final _stackKey = GlobalKey();
  LayerCoordinates? _coords;
  int _coordsRevision = -1;
  List<OverlayLayer>? _hitTestLayers;
  int _hitTestRevision = -1;

  /// After first layout, [RenderBox] is available for layer hit targets.
  bool _layoutReady = false;

  Offset? _marqueeStartStack;
  Offset? _marqueeCurrentStack;

  /// Selected layers last so expanded pinch hit boxes win the gesture arena.
  static List<OverlayLayer> _layersForHitTest(LayerStack stack) {
    final ordered = List<OverlayLayer>.from(stack.layers);
    final selected = stack.selectedIds.toList();
    for (final id in selected) {
      final i = ordered.indexWhere((l) => l.id == id);
      if (i < 0) continue;
      final layer = ordered.removeAt(i);
      ordered.add(layer);
    }
    return ordered;
  }

  bool get _showMultiTransform =>
      widget.layersToolActive &&
      !widget.paintMode &&
      widget.stack.selectedTransformableLayers.length > 1;

  void _handleLayerTap(OverlayLayer layer) {
    final shift = HardwareKeyboard.instance.isShiftPressed;
    if (shift && widget.layersToolActive) {
      widget.stack.toggleSelect(layer.id);
    } else {
      widget.stack.selectOnly(layer.id);
    }
    widget.onStackChanged();
  }

  void _finishMarquee() {
    final start = _marqueeStartStack;
    final end = _marqueeCurrentStack;
    _marqueeStartStack = null;
    _marqueeCurrentStack = null;
    if (start == null || end == null) return;

    final coords = _layerCoords();
    final a = coords.stackToImagePixel(start, clampToImage: false);
    final b = coords.stackToImagePixel(end, clampToImage: false);
    final rect = Rect.fromPoints(a, b);
    if (rect.width < 4 && rect.height < 4) {
      widget.stack.clearSelection();
    } else {
      widget.stack.selectAllInRect(rect);
    }
    widget.onStackChanged();
    if (mounted) setState(() {});
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
  void didUpdateWidget(covariant LayerEditorOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageWidth != widget.imageWidth ||
        oldWidget.imageHeight != widget.imageHeight) {
      _layoutReady = false;
      _scheduleLayoutReadyCheck();
    }
  }

  void _scheduleLayoutReadyCheck() {
    if (_layoutReady) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _layoutReady) return;
      if (_stackBox == null) return;
      setState(() => _layoutReady = true);
    });
  }

  @override
  void initState() {
    super.initState();
    _scheduleLayoutReadyCheck();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stackBox = _layoutReady ? _stackBox : null;
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
                    final brush =
                        widget.activePaintBrush ?? PaintBrushKind.pen;
                    final isCensor = brush == PaintBrushKind.blur ||
                        brush == PaintBrushKind.pixelate;
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        if (isCensor && stroke.length >= 2)
                          _buildActiveCensorOverlay(
                            stroke,
                            brush,
                            childSize,
                          ),
                        CustomPaint(
                          painter: ActivePaintStrokePainter(
                            imageWidth: widget.imageWidth,
                            imageHeight: widget.imageHeight,
                            childSize: childSize,
                            points: stroke,
                            color: widget.activePaintColor ??
                                const Color(0xFF4EDEA3),
                            width: widget.activePaintWidth ?? 8,
                            opacity: widget.activePaintOpacity ?? 0.9,
                            brush: brush,
                            filled: widget.activePaintFilled,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            if (widget.layersToolActive &&
                !widget.paintMode &&
                stackBox != null)
              Positioned.fill(
                child: Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: (e) {
                    if (e.buttons != 1) return;
                    final local = stackBox.globalToLocal(e.position);
                    setState(() {
                      _marqueeStartStack = local;
                      _marqueeCurrentStack = local;
                    });
                  },
                  onPointerMove: (e) {
                    if (_marqueeStartStack == null) return;
                    setState(() {
                      _marqueeCurrentStack =
                          stackBox.globalToLocal(e.position);
                    });
                  },
                  onPointerUp: (_) => _finishMarquee(),
                  onPointerCancel: (_) => _finishMarquee(),
                  child: CustomPaint(
                    painter: _MarqueePainter(
                      start: _marqueeStartStack,
                      end: _marqueeCurrentStack,
                    ),
                  ),
                ),
              ),
        if (stackBox != null)
          for (final layer in _hitTestLayersList())
            if (layer.visible &&
                layer is! PaintStrokeLayer &&
                layer.id != widget.hiddenTextLayerId)
              TransformableLayer(
                key: ValueKey(layer.id),
                layer: layer,
                coords: _layerCoords(),
                stackBox: stackBox,
                selected: widget.stack.isSelected(layer.id),
                ignorePointer: widget.paintMode ||
                    (_showMultiTransform && widget.stack.isSelected(layer.id)),
                onTransformCommit: widget.onStackChanged,
                onTap: () => _handleLayerTap(layer),
                onDoubleTap: () {
                  if (layer is TextLayer) {
                    widget.onTextLayerDoubleTap?.call(layer);
                    return;
                  }
                  if (layer is StickerLayer &&
                      layer.userBytes != null &&
                      layer.userBytes!.isNotEmpty) {
                    widget.onUserImageStickerTap?.call(layer);
                    return;
                  }
                  widget.stack.remove(layer.id);
                  widget.onStackChanged();
                },
                onLongPress: () {
                  widget.stack.bringToFront(layer.id);
                  widget.onStackChanged();
                },
                onTransformBegin: widget.onTransformBegin,
              ),
            if (stackBox != null && _showMultiTransform)
              MultiSelectionTransform(
                stack: widget.stack,
                coords: _layerCoords(),
                stackBox: stackBox,
                layerIds: widget.stack.selectedIds,
                onCommit: widget.onStackChanged,
                onTransformBegin: widget.onTransformBegin,
              ),
            for (final layer in widget.stack.layers)
              if (layer.visible &&
                  layer is PaintStrokeLayer &&
                  layer.points.length >= 2 &&
                  (layer.brush == PaintBrushKind.blur ||
                      layer.brush == PaintBrushKind.pixelate))
                _buildCensorOverlay(layer, childSize),
            if (widget.paintMode)
              Positioned.fill(
                child: PaintCanvas(
                  imageWidth: widget.imageWidth,
                  imageHeight: widget.imageHeight,
                  childSize: childSize,
                  viewerTransform: widget.viewerTransform,
                  activeBrush: widget.activePaintBrush ?? PaintBrushKind.pen,
                  eraserMode: widget.eraserMode,
                  onStroke: widget.onPaintStroke == null
                      ? null
                      : (pts) => widget.onPaintStroke!(
                            pts,
                            childSize: childSize,
                          ),
                  onStrokeUpdate: widget.onActiveStrokeUpdate,
                  onObjectErase: widget.onObjectErase,
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildActiveCensorOverlay(
    List<Offset> points,
    PaintBrushKind brush,
    Size childSize,
  ) {
    final layer = PaintStrokeLayer(
      id: '_active_censor',
      transform: const LayerTransform(),
      points: points,
      brush: brush,
    );
    return _buildCensorOverlay(layer, childSize);
  }

  Widget _buildCensorOverlay(PaintStrokeLayer layer, Size childSize) {
    final iw = widget.imageWidth.toDouble();
    final ih = widget.imageHeight.toDouble();
    if (iw <= 0 || ih <= 0) return const SizedBox.shrink();

    final scale = math.min(childSize.width / iw, childSize.height / ih);
    final w = iw * scale;
    final h = ih * scale;
    final left = (childSize.width - w) / 2;
    final top = (childSize.height - h) / 2;
    final s = w / widget.imageWidth;

    Offset toChild(Offset pixel) =>
        Offset(left + pixel.dx * s, top + pixel.dy * s);

    final start = toChild(layer.points.first);
    final end = toChild(layer.points.last);
    final rect = Rect.fromPoints(start, end);

    final isPixelate = layer.brush == PaintBrushKind.pixelate;

    return Positioned.fromRect(
      rect: rect,
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: isPixelate ? 5.0 : 12.0,
                sigmaY: isPixelate ? 5.0 : 12.0,
              ),
              child: const SizedBox.expand(),
            ),
            if (isPixelate)
              CustomPaint(
                painter: _CensorGridPainter(
                  color: Colors.black.withValues(alpha: 0.15),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MarqueePainter extends CustomPainter {
  const _MarqueePainter({this.start, this.end});

  final Offset? start;
  final Offset? end;

  @override
  void paint(Canvas canvas, Size size) {
    if (start == null || end == null) return;
    final rect = Rect.fromPoints(start!, end!);
    if (rect.width < 2 && rect.height < 2) return;
    final fill = Paint()
      ..color = const Color(0x334EDEA3)
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = const Color(0xFF4EDEA3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRect(rect, fill);
    canvas.drawRect(rect, stroke);
  }

  @override
  bool shouldRepaint(covariant _MarqueePainter oldDelegate) =>
      oldDelegate.start != start || oldDelegate.end != end;
}

class _CensorGridPainter extends CustomPainter {
  const _CensorGridPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    const double cellSize = 12.0;
    for (double x = 0; x < size.width; x += cellSize) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += cellSize) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CensorGridPainter oldDelegate) =>
      oldDelegate.color != color;
}
