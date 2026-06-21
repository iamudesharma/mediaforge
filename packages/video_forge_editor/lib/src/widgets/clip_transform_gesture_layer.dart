import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:video_forge_kit/video_forge_kit.dart';

/// Pinch / pan / rotate gestures that update [ClipTransformBase] on the preview.
class ClipTransformGestureLayer extends StatefulWidget {
  const ClipTransformGestureLayer({
    super.key,
    required this.child,
    required this.effects,
    required this.enabled,
    required this.onPreview,
    required this.onCommit,
  });

  final Widget child;
  final ClipEffects effects;
  final bool enabled;
  final ValueChanged<ClipEffects> onPreview;
  final ValueChanged<ClipEffects> onCommit;

  @override
  State<ClipTransformGestureLayer> createState() =>
      _ClipTransformGestureLayerState();
}

class _ClipTransformGestureLayerState extends State<ClipTransformGestureLayer> {
  double _startScale = 1;
  double _startRotation = 0;
  double _startTranslateX = 0;
  double _startTranslateY = 0;
  Offset _startFocal = Offset.zero;
  ClipEffects? _draft;

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onScaleStart: (details) {
        final base = widget.effects.base;
        _startScale = base.scale;
        _startRotation = base.rotation;
        _startTranslateX = base.translateX;
        _startTranslateY = base.translateY;
        _startFocal = details.focalPoint;
        _draft = widget.effects;
      },
      onScaleUpdate: (details) {
        final scale = (_startScale * details.scale).clamp(1.0, 3.0);
        final rotation = _startRotation + details.rotation * 180 / math.pi;
        final delta = details.focalPoint - _startFocal;
        final next = ClipEffectsKit.copyWithBase(
          widget.effects,
          scale: scale,
          rotation: rotation,
          translateX: (_startTranslateX + delta.dx / 240).clamp(-0.5, 0.5),
          translateY: (_startTranslateY + delta.dy / 240).clamp(-0.5, 0.5),
        );
        _draft = next;
        widget.onPreview(next);
      },
      onScaleEnd: (_) {
        final committed = _draft ?? widget.effects;
        _draft = null;
        widget.onCommit(committed);
      },
      child: widget.child,
    );
  }
}
