import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../layer_coordinates.dart';
import '../models/layer_transform.dart';
import '../models/overlay_layer.dart';
import '../theme/lumina_tokens.dart';
import 'layer_content_widgets.dart';

/// Pinch-drag-rotate wrapper for a single overlay layer.
class TransformableLayer extends StatefulWidget {
  const TransformableLayer({
    super.key,
    required this.layer,
    required this.coords,
    required this.stackBox,
    required this.selected,
    this.onTransformCommit,
    required this.onTap,
    required this.onDoubleTap,
    required this.onLongPress,
    this.onTransformBegin,
  });

  final OverlayLayer layer;
  final LayerCoordinates coords;
  final RenderBox stackBox;
  final bool selected;

  /// Called once when a pinch/drag/rotate gesture ends (transform already on [layer]).
  final VoidCallback? onTransformCommit;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final VoidCallback onLongPress;
  final VoidCallback? onTransformBegin;

  @override
  State<TransformableLayer> createState() => _TransformableLayerState();
}

class _TransformableLayerState extends State<TransformableLayer> {
  static final _selectionDecoration = BoxDecoration(
    border: Border.fromBorderSide(
      BorderSide(color: LuminaTokens.primary, width: 2),
    ),
    borderRadius: BorderRadius.all(Radius.circular(4)),
  );

  double _baseScale = 1;
  double _baseRotation = 0;
  Offset _baseCenterPixel = Offset.zero;
  Offset _dragDeltaPixel = Offset.zero;

  /// Live transform during gesture; committed to [layer.transform] on scale end.
  LayerTransform? _liveTransform;

  /// Set once a pinch/rotate is detected (macOS trackpad may keep
  /// [ScaleUpdateDetails.pointerCount] at 1).
  bool _gesturePinchRotate = false;

  LayerTransform get _t => _liveTransform ?? widget.layer.transform;

  @override
  void didUpdateWidget(covariant TransformableLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.layer.id != widget.layer.id) {
      _liveTransform = null;
    }
  }

  static const _pinchScaleEpsilon = 0.02;
  static const _pinchRotationEpsilon = 0.01;

  /// Minimum gesture box so two fingers can pinch on iPhone (visual stays smaller).
  /// Apple HIG: 44pt tap minimum; pinch needs a much larger overlap zone (~120–140pt).
  double _minHitExtent(BuildContext context) {
    final phone = MediaQuery.sizeOf(context).shortestSide < 600;
    return switch (widget.layer) {
      EmojiLayer() => phone ? 140 : 104,
      StickerLayer() => phone ? 132 : 96,
      TextLayer() => phone ? 120 : 88,
      _ => phone ? 120 : 88,
    };
  }

  Size _hitTargetSize(BuildContext context, Size visual) {
    final minSide = _minHitExtent(context);
    return Size(
      math.max(visual.width, minSide),
      math.max(visual.height, minSide),
    );
  }

  Size _sourceSize() {
    return switch (widget.layer) {
      StickerLayer(:final userBytes, :final userSourceWidth, :final userSourceHeight)
          when userBytes != null && userBytes.isNotEmpty =>
        userSourceWidth > 0 && userSourceHeight > 0
            ? Size(userSourceWidth.toDouble(), userSourceHeight.toDouble())
            : const Size(512, 512),
      EmojiLayer(:final fontSize) => Size.square(fontSize * 1.35),
      TextLayer(:final fontSize, :final padding, :final text) => Size(
          (text.length * fontSize * 0.55 + padding * 2).clamp(48, 420),
          fontSize + padding * 2,
        ),
      StickerLayer(:final cachedWidth, :final cachedHeight)
          when cachedWidth > 0 && cachedHeight > 0 =>
        Size(cachedWidth.toDouble(), cachedHeight.toDouble()),
      StickerLayer() => const Size(120, 120),
      _ when widget.layer.cachedWidth > 0 && widget.layer.cachedHeight > 0 =>
        Size(
          widget.layer.cachedWidth.toDouble(),
          widget.layer.cachedHeight.toDouble(),
        ),
      _ => const Size(80, 80),
    };
  }

  @override
  Widget build(BuildContext context) {
    if (widget.layer is PaintStrokeLayer) {
      return const SizedBox.shrink();
    }

    final source = _sourceSize();
    final visual = widget.coords.layerDisplaySize(
      sourceWidth: source.width,
      sourceHeight: source.height,
      layerScale: _t.scale,
    );
    final hit = _hitTargetSize(context, visual);
    final centerStack = widget.coords.imagePixelToStack(_t.center);

    return Positioned(
      left: centerStack.dx - hit.width / 2,
      top: centerStack.dy - hit.height / 2,
      width: hit.width,
      height: hit.height,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: widget.onTap,
        onDoubleTap: widget.onDoubleTap,
        onLongPress: widget.onLongPress,
        onScaleStart: _onScaleStart,
        onScaleUpdate: _onScaleUpdate,
        onScaleEnd: _onScaleEnd,
        child: Center(
          child: SizedBox(
            width: visual.width,
            height: visual.height,
            child: Transform.rotate(
              angle: _t.rotationRad,
              child: Opacity(
                opacity: _t.opacity.clamp(0, 1),
                child: Container(
                  decoration: widget.selected ? _selectionDecoration : null,
                  child: LayerContentWidget(layer: widget.layer),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _onScaleStart(ScaleStartDetails details) {
    widget.onTransformBegin?.call();
    _baseScale = _t.scale;
    _baseRotation = _t.rotationRad;
    _baseCenterPixel = _t.center;
    _dragDeltaPixel = Offset.zero;
    _gesturePinchRotate = false;
  }

  bool _isPinchOrRotate(ScaleUpdateDetails details) {
    return details.pointerCount >= 2 ||
        (details.scale - 1.0).abs() > _pinchScaleEpsilon ||
        details.rotation.abs() > _pinchRotationEpsilon;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (_isPinchOrRotate(details)) {
      _gesturePinchRotate = true;
    }

    if (_gesturePinchRotate) {
      final source = _sourceSize();
      final newScale = widget.coords.clampLayerScale(
        _baseScale * details.scale,
        sourceWidth: source.width,
        sourceHeight: source.height,
      );
      setState(() {
        _liveTransform = widget.layer.transform.copyWith(
          centerX: _baseCenterPixel.dx,
          centerY: _baseCenterPixel.dy,
          scale: newScale,
          rotationRad: _baseRotation + details.rotation,
        );
      });
      return;
    }

    _dragDeltaPixel += widget.coords.globalFocalDeltaToImagePixel(
      globalFocalPoint: details.focalPoint,
      globalFocalPointDelta: details.focalPointDelta,
      stackBox: widget.stackBox,
    );
    final center = _baseCenterPixel + _dragDeltaPixel;

    setState(() {
      _liveTransform = widget.layer.transform.copyWith(
        centerX: center.dx,
        centerY: center.dy,
        scale: _baseScale,
        rotationRad: _baseRotation,
      );
    });
  }

  void _onScaleEnd(ScaleEndDetails details) {
    final live = _liveTransform;
    if (live != null) {
      widget.layer.transform = live;
      widget.onTransformCommit?.call();
    }
    _liveTransform = null;
    if (mounted) setState(() {});
  }
}
