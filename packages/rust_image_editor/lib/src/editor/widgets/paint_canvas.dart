import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../models/overlay_layer.dart';

/// Captures pointer strokes in image pixel space (Sprint 7/16).
class PaintCanvas extends StatefulWidget {
  const PaintCanvas({
    super.key,
    required this.imageWidth,
    required this.imageHeight,
    required this.childSize,
    required this.viewerTransform,
    required this.activeBrush,
    required this.eraserMode,
    this.onStroke,
    this.onStrokeUpdate,
    this.onObjectErase,
  });

  final int imageWidth;
  final int imageHeight;
  final Size childSize;
  final Matrix4 viewerTransform;
  final PaintBrushKind activeBrush;
  final EraserMode eraserMode;
  final void Function(List<Offset> points)? onStroke;
  final void Function(List<Offset> points)? onStrokeUpdate;
  final void Function(Offset imagePixel)? onObjectErase;

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

  bool get _isFreeStyle {
    final b = widget.activeBrush;
    return b == PaintBrushKind.pen ||
        b == PaintBrushKind.marker ||
        b == PaintBrushKind.highlighter ||
        b == PaintBrushKind.neon ||
        (b == PaintBrushKind.eraser && widget.eraserMode == EraserMode.partial);
  }

  bool get _isObjectEraser =>
      widget.activeBrush == PaintBrushKind.eraser &&
      widget.eraserMode == EraserMode.object;

  bool get _isPolygon => widget.activeBrush == PaintBrushKind.polygon;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) {
        if (!_isDrawingPointer(e)) return;
        final p = _toPixel(e.localPosition);

        if (_isObjectEraser) {
          widget.onObjectErase?.call(p);
          return;
        }

        if (_isPolygon) {
          if (_points.isEmpty) {
            _points.add(p);
          } else {
            // Check if tapping near the start point to close the polygon
            final distToStart = (p - _points.first).distance;
            if (distToStart < 15.0 && _points.length >= 3) {
              _points.add(_points.first);
              widget.onStroke?.call(List.from(_points));
              _points.clear();
              widget.onStrokeUpdate?.call(const []);
              return;
            }
          }
          // Add/update active drawing segment end point
          if (_points.length > 1) {
            _points[_points.length - 1] = p;
          } else {
            _points.add(p);
          }
          widget.onStrokeUpdate?.call(List.unmodifiable(_points));
          return;
        }

        _points
          ..clear()
          ..add(p);
        widget.onStrokeUpdate?.call(List.unmodifiable(_points));
      },
      onPointerMove: (e) {
        if (!_isDrawingPointer(e)) return;
        final p = _toPixel(e.localPosition);

        if (_isObjectEraser) {
          widget.onObjectErase?.call(p);
          return;
        }

        if (_points.isEmpty) return;

        if (_isPolygon) {
          // Update the current preview point
          if (_points.length > 1) {
            _points[_points.length - 1] = p;
          } else {
            _points.add(p);
          }
          widget.onStrokeUpdate?.call(List.unmodifiable(_points));
          return;
        }

        if (_isFreeStyle) {
          if ((p - _points.last).distance > 0.5) {
            _points.add(p);
            widget.onStrokeUpdate?.call(List.unmodifiable(_points));
          }
        } else {
          // 2-point shapes (line, rect, circle, hexagon, dash lines, censors)
          if (_points.length > 1) {
            _points[1] = p;
          } else {
            _points.add(p);
          }
          widget.onStrokeUpdate?.call(List.unmodifiable(_points));
        }
      },
      onPointerUp: (e) {
        if (_isObjectEraser || _isPolygon) return;
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
        if (_isPolygon) return;
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
