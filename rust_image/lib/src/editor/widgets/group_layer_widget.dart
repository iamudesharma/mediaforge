import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../layer_coordinates.dart';
import '../models/overlay_layer.dart';
import '../services/layer_bounds.dart';
import 'layer_content_widgets.dart';

/// Renders [GroupLayer] children with local transforms inside the group box.
class GroupLayerWidget extends StatelessWidget {
  const GroupLayerWidget({
    super.key,
    required this.group,
    required this.coords,
  });

  final GroupLayer group;
  final LayerCoordinates coords;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        for (final child in group.children)
          if (child.visible) _ChildLayer(group: group, child: child, coords: coords),
      ],
    );
  }
}

class _ChildLayer extends StatelessWidget {
  const _ChildLayer({
    required this.group,
    required this.child,
    required this.coords,
  });

  final GroupLayer group;
  final OverlayLayer child;
  final LayerCoordinates coords;

  @override
  Widget build(BuildContext context) {
    final source = LayerBounds.sourceSize(child);
    final t = child.transform;
    final visual = coords.layerDisplaySize(
      sourceWidth: source.width,
      sourceHeight: source.height,
      layerScale: t.scale,
    );

    return Transform.translate(
      offset: Offset(t.centerX * coords.displayScale, t.centerY * coords.displayScale),
      child: Transform.rotate(
        angle: t.rotationRad,
        child: Opacity(
          opacity: t.opacity.clamp(0, 1),
          child: SizedBox(
            width: visual.width,
            height: visual.height,
            child: LayerContentWidget(layer: child),
          ),
        ),
      ),
    );
  }
}
