import 'package:flutter/gestures.dart';
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
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) {
        if (!_isDrawingPointer(e)) return;
        _points
          ..clear()
          ..add(_toPixel(e.localPosition));
        widget.onStrokeUpdate?.call(List.unmodifiable(_points));
      },
      onPointerMove: (e) {
        if (_points.isEmpty || !_isDrawingPointer(e)) return;
        final p = _toPixel(e.localPosition);
        if ((p - _points.last).distance > 0.5) {
          _points.add(p);
          widget.onStrokeUpdate?.call(List.unmodifiable(_points));
        }
      },
      onPointerUp: (e) {
        if (_points.isEmpty) return;
        if (_points.length == 1) {
          _points.add(_points.last);
        }
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

  /// Mouse, pen, and touch; ignore trackpad hover (buttons == 0).
  static bool _isDrawingPointer(PointerEvent e) {
    if (e.kind == PointerDeviceKind.mouse) {
      return e.buttons != 0;
    }
    return e.kind == PointerDeviceKind.touch ||
        e.kind == PointerDeviceKind.stylus ||
        e.kind == PointerDeviceKind.invertedStylus ||
        e.kind == PointerDeviceKind.unknown;
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
