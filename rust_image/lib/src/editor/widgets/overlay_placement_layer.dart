import 'package:flutter/material.dart';

import '../overlay_placement.dart';

/// Drag overlay sticker position on the preview.
class OverlayPlacementLayer extends StatefulWidget {
  const OverlayPlacementLayer({
    super.key,
    required this.placement,
    required this.childSize,
    required this.viewerTransform,
    required this.child,
    this.onPositionChanged,
  });

  final OverlayPlacementController placement;
  final Size childSize;
  final Matrix4 viewerTransform;
  final Widget child;
  final VoidCallback? onPositionChanged;

  @override
  State<OverlayPlacementLayer> createState() => _OverlayPlacementLayerState();
}

class _OverlayPlacementLayerState extends State<OverlayPlacementLayer> {
  OverlayPlacementController get p => widget.placement;

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
                    onTapDown: (d) => _moveTo(d.localPosition),
                    onPanUpdate: (d) => _moveTo(d.localPosition),
                    onPanEnd: (_) => widget.onPositionChanged?.call(),
                    child: CustomPaint(
                      painter: _OverlayPlacementPainter(
                        placement: p,
                        childSize: widget.childSize,
                      ),
                    ),
                  ),
                ),
                const Positioned(
                  left: 8,
                  bottom: 8,
                  child: _HintChip(),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  void _moveTo(Offset local) {
    final px = _pixel(local);
    if (px == null) return;
    p.setPosition(px.dx.round(), px.dy.round());
    widget.onPositionChanged?.call();
  }
}

class _HintChip extends StatelessWidget {
  const _HintChip();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(8),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          'Drag to position overlay',
          style: TextStyle(color: Colors.white, fontSize: 11),
        ),
      ),
    );
  }
}

class _OverlayPlacementPainter extends CustomPainter {
  _OverlayPlacementPainter({required this.placement, required this.childSize});

  final OverlayPlacementController placement;
  final Size childSize;

  @override
  void paint(Canvas canvas, Size size) {
    if (placement.imageWidth <= 0) return;
    final rect = placement.overlayRectInChild(childSize);
    canvas.drawRect(
      rect,
      Paint()..color = const Color(0xFF00D4AA).withValues(alpha: 0.25),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..color = const Color(0xFF00D4AA)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    final handle = rect.topLeft;
    canvas.drawCircle(
      handle,
      10,
      Paint()..color = const Color(0xFFFF5078),
    );
  }

  @override
  bool shouldRepaint(covariant _OverlayPlacementPainter old) =>
      old.placement.x != placement.x ||
      old.placement.y != placement.y ||
      old.childSize != childSize;
}
