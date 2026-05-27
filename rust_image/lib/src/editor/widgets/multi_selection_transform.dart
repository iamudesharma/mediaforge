import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../layer_coordinates.dart';
import '../models/layer_stack.dart';
import '../models/layer_transform.dart';
import '../models/overlay_layer.dart';
import '../services/layer_bounds.dart';
import '../theme/lumina_tokens.dart';

/// Shared pinch/drag/rotate for multiple selected layers (Sprint 17).
class MultiSelectionTransform extends StatefulWidget {
  const MultiSelectionTransform({
    super.key,
    required this.stack,
    required this.coords,
    required this.stackBox,
    required this.layerIds,
    required this.onCommit,
    this.onTransformBegin,
  });

  final LayerStack stack;
  final LayerCoordinates coords;
  final RenderBox stackBox;
  final Set<String> layerIds;
  final VoidCallback onCommit;
  final VoidCallback? onTransformBegin;

  @override
  State<MultiSelectionTransform> createState() =>
      _MultiSelectionTransformState();
}

class _MultiSelectionTransformState extends State<MultiSelectionTransform> {
  static final _selectionDecoration = BoxDecoration(
    border: Border.fromBorderSide(
      BorderSide(color: LuminaTokens.primary, width: 2),
    ),
    borderRadius: const BorderRadius.all(Radius.circular(4)),
  );

  Offset? _pivot;
  final Map<String, LayerTransform> _baseTransforms = {};
  Offset _dragDeltaPixel = Offset.zero;
  bool _gesturePinchRotate = false;
  bool _undoPushed = false;

  static const _pinchScaleEpsilon = 0.02;
  static const _pinchRotationEpsilon = 0.01;

  Rect? _unionRect() {
    final layers = widget.layerIds
        .map(widget.stack.findById)
        .whereType<OverlayLayer>()
        .where((l) => l is! PaintStrokeLayer)
        .toList();
    return LayerBounds.unionBounds(layers);
  }

  List<OverlayLayer> get _targets => widget.layerIds
      .map(widget.stack.findById)
      .whereType<OverlayLayer>()
      .where((l) => l is! PaintStrokeLayer)
      .toList();

  @override
  Widget build(BuildContext context) {
    final union = _unionRect();
    if (union == null || union.width <= 0 || union.height <= 0) {
      return const SizedBox.shrink();
    }

    final pivot = Offset(union.center.dx, union.center.dy);
    final halfW = union.width / 2;
    final halfH = union.height / 2;
    final centerStack = widget.coords.imagePixelToStack(pivot);
    final scale = widget.coords.displayScale;
    final hitW = math.max(halfW * 2 * scale, 120.0);
    final hitH = math.max(halfH * 2 * scale, 120.0);

    return Positioned(
      left: centerStack.dx - hitW / 2,
      top: centerStack.dy - hitH / 2,
      width: hitW,
      height: hitH,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onScaleStart: (_) => _onScaleStart(pivot),
        onScaleUpdate: _onScaleUpdate,
        onScaleEnd: _onScaleEnd,
        child: Container(
          decoration: _selectionDecoration,
          child: Center(
            child: Icon(
              Icons.crop_free,
              size: 28,
              color: LuminaTokens.primary.withValues(alpha: 0.5),
            ),
          ),
        ),
      ),
    );
  }

  void _onScaleStart(Offset pivot) {
    if (!_undoPushed) {
      widget.onTransformBegin?.call();
      _undoPushed = true;
    }
    _pivot = pivot;
    _baseTransforms.clear();
    for (final l in _targets) {
      _baseTransforms[l.id] = LayerTransform(
        centerX: l.transform.centerX,
        centerY: l.transform.centerY,
        scale: l.transform.scale,
        rotationRad: l.transform.rotationRad,
        opacity: l.transform.opacity,
      );
    }
    _dragDeltaPixel = Offset.zero;
    _gesturePinchRotate = false;
  }

  bool _isPinchOrRotate(ScaleUpdateDetails details) {
    return details.pointerCount >= 2 ||
        (details.scale - 1.0).abs() > _pinchScaleEpsilon ||
        details.rotation.abs() > _pinchRotationEpsilon;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final pivot = _pivot;
    if (pivot == null) return;
    if (_isPinchOrRotate(details)) _gesturePinchRotate = true;

    if (_gesturePinchRotate) {
      final scaleFactor = details.scale;
      final rotDelta = details.rotation;
      for (final l in _targets) {
        final base = _baseTransforms[l.id];
        if (base == null) continue;
        l.transform = LayerTransform.applyDeltaAboutPivot(
          t: base,
          pivot: pivot,
          translation: Offset.zero,
          scaleFactor: scaleFactor,
          rotationDelta: rotDelta,
        );
      }
      setState(() {});
      return;
    }

    _dragDeltaPixel += widget.coords.globalFocalDeltaToImagePixel(
      globalFocalPoint: details.focalPoint,
      globalFocalPointDelta: details.focalPointDelta,
      stackBox: widget.stackBox,
    );
    for (final l in _targets) {
      final base = _baseTransforms[l.id];
      if (base == null) continue;
      l.transform = base.copyWith(
        centerX: base.centerX + _dragDeltaPixel.dx,
        centerY: base.centerY + _dragDeltaPixel.dy,
      );
    }
    setState(() {});
  }

  void _onScaleEnd(ScaleEndDetails details) {
    _pivot = null;
    _baseTransforms.clear();
    _undoPushed = false;
    widget.onCommit();
    if (mounted) setState(() {});
  }
}
