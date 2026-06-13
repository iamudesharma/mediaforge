import 'package:flutter/material.dart';

import '../playback/compositor_layout.dart';
import 'video_overlay_item.dart';

/// Clamps normalized overlay anchor to 0–1.
Offset clampVideoOverlayAnchor(Offset anchor) {
  return Offset(anchor.dx.clamp(0.0, 1.0), anchor.dy.clamp(0.0, 1.0));
}

/// Timeline-visible overlays with double-tap-to-select and drag-to-reposition.
class DraggableVideoOverlays extends StatelessWidget {
  const DraggableVideoOverlays({
    super.key,
    required this.frameSize,
    required this.overlays,
    required this.playheadMs,
    this.selectedOverlayId,
    this.onOverlayChanged,
    this.onSelectOverlay,
  });

  final Size frameSize;
  final List<VideoOverlayItem> overlays;
  final int playheadMs;
  final String? selectedOverlayId;
  final ValueChanged<VideoOverlayItem>? onOverlayChanged;
  final ValueChanged<String?>? onSelectOverlay;

  @override
  Widget build(BuildContext context) {
    final visible = overlays.where((o) => o.isVisibleAt(playheadMs)).toList();
    if (visible.isEmpty) {
      return const SizedBox.shrink();
    }

    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.expand,
      children: [
        for (final overlay in visible)
          _DraggableOverlayLayer(
            key: ValueKey(overlay.id),
            overlay: overlay,
            frameSize: frameSize,
            playheadMs: playheadMs,
            selected: overlay.id == selectedOverlayId,
            onOverlayChanged: onOverlayChanged,
            onSelectOverlay: onSelectOverlay,
          ),
      ],
    );
  }
}

class _DraggableOverlayLayer extends StatefulWidget {
  const _DraggableOverlayLayer({
    super.key,
    required this.overlay,
    required this.frameSize,
    required this.playheadMs,
    required this.selected,
    this.onOverlayChanged,
    this.onSelectOverlay,
  });

  final VideoOverlayItem overlay;
  final Size frameSize;
  final int playheadMs;
  final bool selected;
  final ValueChanged<VideoOverlayItem>? onOverlayChanged;
  final ValueChanged<String?>? onSelectOverlay;

  @override
  State<_DraggableOverlayLayer> createState() => _DraggableOverlayLayerState();
}

class _DraggableOverlayLayerState extends State<_DraggableOverlayLayer> {
  Offset? _dragAnchor;
  bool _dragging = false;

  VideoOverlayItem get _item => widget.overlay;

  Offset get _displayAnchor => _dragAnchor ?? _item.anchor;

  bool get _interactive =>
      widget.onOverlayChanged != null || widget.onSelectOverlay != null;

  void _onPanStart(DragStartDetails details) {
    setState(() {
      _dragging = true;
      _dragAnchor = _item.anchor;
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (widget.onOverlayChanged == null) return;
    final w = widget.frameSize.width;
    final h = widget.frameSize.height;
    if (w <= 0 || h <= 0) return;

    final base = _dragAnchor ?? _item.anchor;
    final next = clampVideoOverlayAnchor(
      Offset(
        base.dx + details.delta.dx / w,
        base.dy + details.delta.dy / h,
      ),
    );
    setState(() => _dragAnchor = next);
    widget.onOverlayChanged!(_item.copyWith(anchor: next));
  }

  void _onPanEnd(DragEndDetails details) {
    setState(() {
      _dragAnchor = null;
      _dragging = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final showChrome = (widget.selected || _dragging) && _interactive;
    final child = showChrome
        ? DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFF00D4AA), width: 2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: _item.child,
          )
        : _item.child;

    if (!_interactive) {
      return VideoOverlayPositioned(
        anchor: _displayAnchor,
        opacity: _item.opacityAt(widget.playheadMs),
        child: child,
      );
    }

    return VideoOverlayPositioned(
      anchor: _displayAnchor,
      opacity: _item.opacityAt(widget.playheadMs),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: () => widget.onSelectOverlay?.call(_item.id),
        onPanStart: widget.onOverlayChanged != null ? _onPanStart : null,
        onPanUpdate: widget.onOverlayChanged != null ? _onPanUpdate : null,
        onPanEnd: widget.onOverlayChanged != null ? _onPanEnd : null,
        child: child,
      ),
    );
  }
}
