import 'package:flutter/material.dart';

/// Captures pointer strokes in image pixel space (Sprint 7).
class PaintCanvas extends StatefulWidget {
  const PaintCanvas({
    super.key,
    required this.imageWidth,
    required this.imageHeight,
    required this.childSize,
    required this.viewerTransform,
    this.onStroke,
    this.onStrokeUpdate,
  });

  final int imageWidth;
  final int imageHeight;
  final Size childSize;
  final Matrix4 viewerTransform;
  final void Function(List<Offset> points)? onStroke;
  final void Function(List<Offset> points)? onStrokeUpdate;

  @override
  State<PaintCanvas> createState() => _PaintCanvasState();
}

class _PaintCanvasState extends State<PaintCanvas> {
  final _points = <Offset>[];
  Matrix4? _inverseViewer;

  @override
  void didUpdateWidget(covariant PaintCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewerTransform != widget.viewerTransform) {
      _inverseViewer = null;
    }
  }

  Matrix4 get _inverseViewerMatrix =>
      _inverseViewer ??= Matrix4.inverted(widget.viewerTransform);

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) {
        _points
          ..clear()
          ..add(_toPixel(e.localPosition));
        widget.onStrokeUpdate?.call(List.unmodifiable(_points));
      },
      onPointerMove: (e) {
        final p = _toPixel(e.localPosition);
        if (_points.isEmpty || (p - _points.last).distance > 1) {
          _points.add(p);
          widget.onStrokeUpdate?.call(List.unmodifiable(_points));
        }
      },
      onPointerUp: (_) {
        if (_points.length >= 2) {
          widget.onStroke?.call(List.from(_points));
        }
        _points.clear();
        widget.onStrokeUpdate?.call(const []);
      },
      onPointerCancel: (_) {
        _points.clear();
        widget.onStrokeUpdate?.call(const []);
      },
      child: const SizedBox.expand(),
    );
  }

  Offset _toPixel(Offset local) {
    final u = MatrixUtils.transformPoint(_inverseViewerMatrix, local);
    final iw = widget.imageWidth.toDouble();
    final ih = widget.imageHeight.toDouble();
    final scale = (widget.childSize.width / iw).clamp(0.001, 999.0);
    final rectW = iw * scale;
    final rectH = ih * scale;
    final left = (widget.childSize.width - rectW) / 2;
    final top = (widget.childSize.height - rectH) / 2;
    return Offset(
      ((u.dx - left) / scale).clamp(0.0, iw),
      ((u.dy - top) / scale).clamp(0.0, ih),
    );
  }
}
