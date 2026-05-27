import 'package:flutter/material.dart';

import '../overlay_placement.dart';

enum _OverlayDragMode { move, topLeft, topRight, bottomLeft, bottomRight }

/// Drag, pinch-resize, and corner-scale the watermark (inside [InteractiveViewer]).
class OverlayPlacementLayer extends StatefulWidget {
  const OverlayPlacementLayer({
    super.key,
    required this.placement,
    required this.childSize,
    required this.child,
    this.onPositionChanged,
  });

  final OverlayPlacementController placement;
  final Size childSize;
  final Widget child;
  final VoidCallback? onPositionChanged;

  @override
  State<OverlayPlacementLayer> createState() => _OverlayPlacementLayerState();
}

class _OverlayPlacementLayerState extends State<OverlayPlacementLayer> {
  final _stackKey = GlobalKey();
  _OverlayDragMode? _mode;
  Offset? _startPointerPx;
  int _startX = 0;
  int _startY = 0;
  int _startW = 0;
  int _startH = 0;
  bool _pinchResize = false;

  OverlayPlacementController get p => widget.placement;
  Size get _childSize => widget.childSize;

  static const _handleHit = 28.0;
  static const _pinchScaleEpsilon = 0.02;

  RenderBox? get _stackBox {
    final ro = _stackKey.currentContext?.findRenderObject();
    return ro is RenderBox ? ro : null;
  }

  Offset? _pixelFromGlobal(Offset global) {
    final box = _stackBox;
    if (box == null) return null;
    final local = box.globalToLocal(global);
    return p.childPointToImagePixel(local, _childSize, clampToImage: false);
  }

  Offset? _pixelFromLocal(Offset local) =>
      p.childPointToImagePixel(local, _childSize, clampToImage: false);

  _OverlayDragMode? _hitTest(Offset local) {
    final rect = p.overlayRectInChild(_childSize);
    if (rect.isEmpty) return null;

    Offset corner(bool left, bool top) => Offset(
          left ? rect.left : rect.right,
          top ? rect.top : rect.bottom,
        );

    for (final entry in <(_OverlayDragMode, Offset)>[
      (_OverlayDragMode.topLeft, corner(true, true)),
      (_OverlayDragMode.topRight, corner(false, true)),
      (_OverlayDragMode.bottomLeft, corner(true, false)),
      (_OverlayDragMode.bottomRight, corner(false, false)),
    ]) {
      if ((local - entry.$2).distance < _handleHit) return entry.$1;
    }
    if (rect.contains(local)) return _OverlayDragMode.move;
    return null;
  }

  void _notifyChanged() {
    p.normalize();
    widget.onPositionChanged?.call();
  }

  void _onScaleStart(ScaleStartDetails details) {
    final box = _stackBox;
    if (box == null) return;
    final local = box.globalToLocal(details.focalPoint);
    final px = _pixelFromLocal(local);
    if (px == null) return;

    _mode = _hitTest(local);
    if (_mode == null) return;

    _startPointerPx = px;
    _startX = p.x;
    _startY = p.y;
    _startW = p.overlayWidth;
    _startH = p.overlayHeight;
    _pinchResize = false;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (_mode == null || _startPointerPx == null) return;

    final pinch =
        details.pointerCount >= 2 || (details.scale - 1.0).abs() > _pinchScaleEpsilon;

    if (pinch && _mode == _OverlayDragMode.move) {
      _pinchResize = true;
      final scale = details.scale.clamp(0.15, 8.0);
      final cx = _startX + _startW / 2;
      final cy = _startY + _startH / 2;
      final nw = (_startW * scale).round().clamp(
            OverlayPlacementController.minOverlayEdge,
            p.imageWidth,
          );
      final nh = (_startH * scale).round().clamp(
            OverlayPlacementController.minOverlayEdge,
            p.imageHeight,
          );
      p.setOverlaySize(nw, nh);
      p.setPosition(
        (cx - nw / 2).round(),
        (cy - nh / 2).round(),
      );
      _notifyChanged();
      return;
    }

    if (_pinchResize) return;

    final px = _pixelFromGlobal(details.focalPoint);
    if (px == null) return;

    final dx = (px.dx - _startPointerPx!.dx).round();
    final dy = (px.dy - _startPointerPx!.dy).round();

    switch (_mode!) {
      case _OverlayDragMode.move:
        p.setPosition(_startX + dx, _startY + dy);
      case _OverlayDragMode.topLeft:
        p.resizeFromCorner(
          top: true,
          left: true,
          anchorX: (_startX + _startW + dx).clamp(0, p.imageWidth).round(),
          anchorY: (_startY + _startH + dy).clamp(0, p.imageHeight).round(),
        );
      case _OverlayDragMode.topRight:
        p.resizeFromCorner(
          top: true,
          left: false,
          anchorX: (_startX + dx).clamp(0, p.imageWidth).round(),
          anchorY: (_startY + _startH + dy).clamp(0, p.imageHeight).round(),
        );
      case _OverlayDragMode.bottomLeft:
        p.resizeFromCorner(
          top: false,
          left: true,
          anchorX: (_startX + _startW + dx).clamp(0, p.imageWidth).round(),
          anchorY: (_startY + dy).clamp(0, p.imageHeight).round(),
        );
      case _OverlayDragMode.bottomRight:
        p.resizeFromCorner(
          top: false,
          left: false,
          anchorX: (_startX + dx).clamp(0, p.imageWidth).round(),
          anchorY: (_startY + dy).clamp(0, p.imageHeight).round(),
        );
    }
    _notifyChanged();
  }

  void _onScaleEnd(ScaleEndDetails details) {
    _mode = null;
    _startPointerPx = null;
    _pinchResize = false;
    _notifyChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      key: _stackKey,
      fit: StackFit.expand,
      children: [
        widget.child,
        ListenableBuilder(
          listenable: p,
          builder: (context, _) {
            final rect = p.overlayRectInChild(_childSize);
            if (rect.isEmpty) {
              return const SizedBox.shrink();
            }

            return Stack(
              fit: StackFit.expand,
              children: [
                IgnorePointer(
                  child: CustomPaint(
                    painter: _OverlayPlacementPainter(
                      placement: p,
                      childSize: _childSize,
                    ),
                  ),
                ),
                Positioned.fromRect(
                  rect: rect,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onScaleStart: _onScaleStart,
                    onScaleUpdate: _onScaleUpdate,
                    onScaleEnd: _onScaleEnd,
                    child: const SizedBox.expand(),
                  ),
                ),
                ..._cornerHandles(rect),
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

  List<Widget> _cornerHandles(Rect rect) {
    Widget handle(_OverlayDragMode mode, Alignment alignment) {
      final local = alignment.alongSize(rect.size) + rect.topLeft;
      return Positioned(
        left: local.dx - _handleHit / 2,
        top: local.dy - _handleHit / 2,
        width: _handleHit,
        height: _handleHit,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onScaleStart: (d) {
            final box = _stackBox;
            if (box == null) return;
            final hitLocal = box.globalToLocal(d.focalPoint);
            _mode = mode;
            _startPointerPx = _pixelFromLocal(hitLocal);
            _startX = p.x;
            _startY = p.y;
            _startW = p.overlayWidth;
            _startH = p.overlayHeight;
            _pinchResize = false;
          },
          onScaleUpdate: _onScaleUpdate,
          onScaleEnd: _onScaleEnd,
          child: const DecoratedBox(
            decoration: BoxDecoration(
              color: Color(0xFFFF5078),
              shape: BoxShape.circle,
            ),
          ),
        ),
      );
    }

    return [
      handle(_OverlayDragMode.topLeft, Alignment.topLeft),
      handle(_OverlayDragMode.topRight, Alignment.topRight),
      handle(_OverlayDragMode.bottomLeft, Alignment.bottomLeft),
      handle(_OverlayDragMode.bottomRight, Alignment.bottomRight),
    ];
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
          'Drag to move · pinch box to scale · corners to resize · pinch canvas to zoom',
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
  }

  @override
  bool shouldRepaint(covariant _OverlayPlacementPainter old) =>
      old.placement.x != placement.x ||
      old.placement.y != placement.y ||
      old.placement.overlayWidth != placement.overlayWidth ||
      old.placement.overlayHeight != placement.overlayHeight ||
      old.childSize != childSize;
}
