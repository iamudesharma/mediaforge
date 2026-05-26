import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../crop_controller.dart';

enum _CropDragMode { move, topLeft, topRight, bottomLeft, bottomRight }

/// Interactive crop box on the preview (Sprint 9).
class CropOverlay extends StatefulWidget {
  const CropOverlay({
    super.key,
    required this.crop,
    required this.childSize,
    required this.viewerTransform,
    required this.child,
  });

  final CropController crop;
  final Size childSize;
  final Matrix4 viewerTransform;
  final Widget child;

  @override
  State<CropOverlay> createState() => _CropOverlayState();
}

class _CropOverlayState extends State<CropOverlay> {
  _CropDragMode? _mode;
  Offset? _startPixel;
  int _startCropX = 0;
  int _startCropY = 0;
  int _startCropW = 0;
  int _startCropH = 0;
  double? _straightenAtScaleStart;

  CropController get c => widget.crop;

  Offset? _pixel(Offset local) =>
      c.pointerToImagePixel(local, widget.childSize, widget.viewerTransform);

  static const _handleHit = 28.0;

  _CropDragMode? _hitTest(Offset local) {
    final rect = c.cropRectInChild(widget.childSize);
    if (rect.isEmpty) return null;

    Offset handle(Alignment a) {
      final x = a == Alignment.topLeft || a == Alignment.bottomLeft
          ? rect.left
          : rect.right;
      final y = a == Alignment.topLeft || a == Alignment.topRight
          ? rect.top
          : rect.bottom;
      return Offset(x, y);
    }

    for (final entry in <(_CropDragMode, Alignment)>[
      (_CropDragMode.topLeft, Alignment.topLeft),
      (_CropDragMode.topRight, Alignment.topRight),
      (_CropDragMode.bottomLeft, Alignment.bottomLeft),
      (_CropDragMode.bottomRight, Alignment.bottomRight),
    ]) {
      final h = handle(entry.$2);
      if ((local - h).distance < _handleHit) return entry.$1;
    }
    if (rect.contains(local)) return _CropDragMode.move;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        return Stack(
          fit: StackFit.expand,
          children: [
            Transform.rotate(
              angle: c.straightenDegrees * math.pi / 180,
              child: widget.child,
            ),
            Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onPanStart: (d) {
                      final px = _pixel(d.localPosition);
                      if (px == null) return;
                      _mode = _hitTest(d.localPosition);
                      if (_mode == null) return;
                      _startPixel = px;
                      _startCropX = c.cropX;
                      _startCropY = c.cropY;
                      _startCropW = c.cropW;
                      _startCropH = c.cropH;
                    },
                    onPanUpdate: (d) {
                      final px = _pixel(d.localPosition);
                      if (px == null || _mode == null || _startPixel == null) return;
                      final dx = (px.dx - _startPixel!.dx).round();
                      final dy = (px.dy - _startPixel!.dy).round();
                      switch (_mode!) {
                        case _CropDragMode.move:
                          c.setCropRect(
                            _startCropX + dx,
                            _startCropY + dy,
                            _startCropW,
                            _startCropH,
                          );
                        case _CropDragMode.topLeft:
                          c.resizeCropFromCorner(
                            top: true,
                            left: true,
                            anchorX: (_startCropX + _startCropW + dx)
                                .clamp(0, c.imageWidth)
                                .round(),
                            anchorY: (_startCropY + _startCropH + dy)
                                .clamp(0, c.imageHeight)
                                .round(),
                          );
                        case _CropDragMode.topRight:
                          c.resizeCropFromCorner(
                            top: true,
                            left: false,
                            anchorX: (_startCropX + dx).clamp(0, c.imageWidth).round(),
                            anchorY: (_startCropY + _startCropH + dy)
                                .clamp(0, c.imageHeight)
                                .round(),
                          );
                        case _CropDragMode.bottomLeft:
                          c.resizeCropFromCorner(
                            top: false,
                            left: true,
                            anchorX: (_startCropX + _startCropW + dx)
                                .clamp(0, c.imageWidth)
                                .round(),
                            anchorY: (_startCropY + dy).clamp(0, c.imageHeight).round(),
                          );
                        case _CropDragMode.bottomRight:
                          c.resizeCropFromCorner(
                            top: false,
                            left: false,
                            anchorX: (_startCropX + dx).clamp(0, c.imageWidth).round(),
                            anchorY: (_startCropY + dy).clamp(0, c.imageHeight).round(),
                          );
                      }
                    },
                    onPanEnd: (_) {
                      _mode = null;
                      _startPixel = null;
                    },
                    onScaleStart: (d) {
                      if (d.pointerCount >= 2) {
                        _straightenAtScaleStart = c.straightenDegrees;
                      }
                    },
                    onScaleUpdate: (d) {
                      if (d.pointerCount >= 2 &&
                          _straightenAtScaleStart != null &&
                          d.rotation.abs() > 0.0005) {
                        final deg = _straightenAtScaleStart! +
                            d.rotation * 180 / math.pi;
                        c.setStraightenDegrees(deg);
                      }
                    },
                    onScaleEnd: (_) => _straightenAtScaleStart = null,
                    child: CustomPaint(
                      painter: _CropOverlayPainter(
                        crop: c,
                        childSize: widget.childSize,
                      ),
                    ),
                  ),
                ),
                const Positioned(
                  left: 8,
                  bottom: 8,
                  child: _CropHint(),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _CropHint extends StatelessWidget {
  const _CropHint();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          'Drag box · two-finger rotate to straighten',
          style: TextStyle(color: Colors.white, fontSize: 11),
        ),
      ),
    );
  }
}

class _CropOverlayPainter extends CustomPainter {
  _CropOverlayPainter({required this.crop, required this.childSize});

  final CropController crop;
  final Size childSize;

  @override
  void paint(Canvas canvas, Size size) {
    if (crop.imageWidth <= 0 || crop.imageHeight <= 0) return;

    final cropRect = crop.cropRectInChild(childSize);
    if (cropRect.isEmpty) return;

    final dim = Paint()..color = const Color(0x99000000);
    final full = Offset.zero & childSize;
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(full),
        Path()..addRect(cropRect),
      ),
      dim,
    );

    final border = Paint()
      ..color = const Color(0xFF4EDEA3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(cropRect, border);

    final gridPaint = Paint()
      ..color = const Color(0x66FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var i = 1; i <= 2; i++) {
      final fx = cropRect.left + cropRect.width * i / 3;
      final fy = cropRect.top + cropRect.height * i / 3;
      canvas.drawLine(Offset(fx, cropRect.top), Offset(fx, cropRect.bottom), gridPaint);
      canvas.drawLine(Offset(cropRect.left, fy), Offset(cropRect.right, fy), gridPaint);
    }

    final handleFill = Paint()..color = const Color(0xFF4EDEA3);
    final handleBorder = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final corner in [
      cropRect.topLeft,
      cropRect.topRight,
      cropRect.bottomLeft,
      cropRect.bottomRight,
    ]) {
      canvas.drawCircle(corner, 8, handleFill);
      canvas.drawCircle(corner, 8, handleBorder);
    }
  }

  @override
  bool shouldRepaint(covariant _CropOverlayPainter old) =>
      old.crop.cropX != crop.cropX ||
      old.crop.cropY != crop.cropY ||
      old.crop.cropW != crop.cropW ||
      old.crop.cropH != crop.cropH ||
      old.crop.imageWidth != crop.imageWidth ||
      old.crop.straightenDegrees != crop.straightenDegrees ||
      old.childSize != childSize;
}
