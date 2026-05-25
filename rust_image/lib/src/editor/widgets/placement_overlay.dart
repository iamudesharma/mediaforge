import 'package:flutter/material.dart';

import '../draw_placement.dart';

/// Handles drag/tap on the preview to set draw positions (text, line, circle).
class PlacementOverlay extends StatefulWidget {
  const PlacementOverlay({
    super.key,
    required this.placement,
    required this.childSize,
    required this.viewerTransform,
    required this.child,
  });

  final DrawPlacementController placement;
  final Size childSize;
  final Matrix4 viewerTransform;
  final Widget child;

  @override
  State<PlacementOverlay> createState() => _PlacementOverlayState();
}

class _PlacementOverlayState extends State<PlacementOverlay> {
  int? _dragging; // 0=start/anchor, 1=end, 2=circle center

  DrawPlacementController get p => widget.placement;

  Offset? _pixel(Offset local) =>
      p.pointerToImagePixel(local, widget.childSize, widget.viewerTransform);

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        ListenableBuilder(
          listenable: p,
          builder: (context, _) {
            return Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTapDown: (d) => _onTap(d.localPosition),
                    onPanStart: (d) => _onPanStart(d.localPosition),
                    onPanUpdate: (d) => _onPanUpdate(d.localPosition),
                    onPanEnd: (_) => setState(() => _dragging = null),
                    child: CustomPaint(
                      painter: _PlacementPainter(
                        placement: p,
                        childSize: widget.childSize,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 8,
                  bottom: 8,
                  child: _HintChip(kind: p.kind),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  void _onTap(Offset local) {
    final px = _pixel(local);
    if (px == null) return;
    _apply(px, isStart: true);
  }

  void _onPanStart(Offset local) {
    final px = _pixel(local);
    if (px == null) return;
    switch (p.kind) {
      case DrawPlaceKind.text:
        _dragging = 0;
      case DrawPlaceKind.line:
        final d0 = (px.dx - p.lineX0).abs() + (px.dy - p.lineY0).abs();
        final d1 = (px.dx - p.lineX1).abs() + (px.dy - p.lineY1).abs();
        _dragging = d0 <= d1 ? 0 : 1;
      case DrawPlaceKind.circle:
        _dragging = 2;
    }
    _apply(px, isStart: true);
  }

  void _onPanUpdate(Offset local) {
    if (_dragging == null) return;
    final px = _pixel(local);
    if (px == null) return;
    _apply(px, isStart: false);
  }

  void _apply(Offset px, {required bool isStart}) {
    final x = px.dx.round();
    final y = px.dy.round();
    switch (p.kind) {
      case DrawPlaceKind.text:
        p.setTextPos(x, y);
      case DrawPlaceKind.line:
        if (_dragging == 0 || isStart) {
          p.setLineStart(x, y);
        } else {
          p.setLineEnd(x, y);
        }
      case DrawPlaceKind.circle:
        p.setCircleCenter(x, y);
    }
  }
}

class _HintChip extends StatelessWidget {
  const _HintChip({required this.kind});

  final DrawPlaceKind kind;

  @override
  Widget build(BuildContext context) {
    final msg = switch (kind) {
      DrawPlaceKind.text => 'Tap or drag to place text',
      DrawPlaceKind.line => 'Drag green / teal handles for line ends',
      DrawPlaceKind.circle => 'Drag to move circle center',
    };
    return Material(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(msg, style: const TextStyle(color: Colors.white, fontSize: 11)),
      ),
    );
  }
}

class _PlacementPainter extends CustomPainter {
  _PlacementPainter({required this.placement, required this.childSize});

  final DrawPlacementController placement;
  final Size childSize;

  @override
  void paint(Canvas canvas, Size size) {
    if (placement.imageWidth <= 0) return;

    final border = Paint()
      ..color = const Color(0xFF00D4AA)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    switch (placement.kind) {
      case DrawPlaceKind.text:
        final c = placement.imagePixelToChild(
          Offset(placement.textX.toDouble(), placement.textY.toDouble()),
          childSize,
        );
        canvas.drawCircle(c, 8, Paint()..color = const Color(0xFF00D4AA));
        canvas.drawLine(
          Offset(c.dx - 16, c.dy),
          Offset(c.dx + 16, c.dy),
          border,
        );
        canvas.drawLine(
          Offset(c.dx, c.dy - 16),
          Offset(c.dx, c.dy + 16),
          border,
        );
      case DrawPlaceKind.line:
        final a = placement.imagePixelToChild(
          Offset(placement.lineX0.toDouble(), placement.lineY0.toDouble()),
          childSize,
        );
        final b = placement.imagePixelToChild(
          Offset(placement.lineX1.toDouble(), placement.lineY1.toDouble()),
          childSize,
        );
        canvas.drawLine(a, b, border..strokeWidth = 3);
        _handle(canvas, a, Colors.greenAccent);
        _handle(canvas, b, const Color(0xFF00D4AA));
      case DrawPlaceKind.circle:
        final center = placement.imagePixelToChild(
          Offset(placement.circleX.toDouble(), placement.circleY.toDouble()),
          childSize,
        );
        final scale = DrawPlacementController.containRect(
          Size(placement.imageWidth.toDouble(), placement.imageHeight.toDouble()),
          childSize,
        ).width / placement.imageWidth;
        final r = placement.circleRadius * scale;
        canvas.drawCircle(center, r, border);
        _handle(canvas, center, const Color(0xFFFF5078));
    }
  }

  void _handle(Canvas canvas, Offset c, Color color) {
    canvas.drawCircle(
      c,
      10,
      Paint()..color = color.withValues(alpha: 0.9),
    );
    canvas.drawCircle(
      c,
      10,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _PlacementPainter old) =>
      old.placement.kind != placement.kind ||
      old.placement.textX != placement.textX ||
      old.placement.textY != placement.textY ||
      old.placement.lineX0 != placement.lineX0 ||
      old.placement.lineY0 != placement.lineY0 ||
      old.placement.lineX1 != placement.lineX1 ||
      old.placement.lineY1 != placement.lineY1 ||
      old.placement.circleX != placement.circleX ||
      old.placement.circleY != placement.circleY ||
      old.placement.circleRadius != placement.circleRadius ||
      old.childSize != childSize;
}
