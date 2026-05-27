import 'dart:math' as math;
import 'dart:ui';

/// Transform for an overlay layer in image pixel space.
class LayerTransform {
  const LayerTransform({
    this.centerX = 0,
    this.centerY = 0,
    this.scale = 1,
    this.rotationRad = 0,
    this.opacity = 1,
  });

  final double centerX;
  final double centerY;
  final double scale;
  final double rotationRad;
  final double opacity;

  LayerTransform copyWith({
    double? centerX,
    double? centerY,
    double? scale,
    double? rotationRad,
    double? opacity,
  }) {
    return LayerTransform(
      centerX: centerX ?? this.centerX,
      centerY: centerY ?? this.centerY,
      scale: scale ?? this.scale,
      rotationRad: rotationRad ?? this.rotationRad,
      opacity: opacity ?? this.opacity,
    );
  }

  Offset get center => Offset(centerX, centerY);

  /// [inner] is in local space of [outer]; result is world/image space.
  static LayerTransform multiply(LayerTransform outer, LayerTransform inner) {
    final c = math.cos(outer.rotationRad);
    final s = math.sin(outer.rotationRad);
    final lx = inner.centerX * outer.scale;
    final ly = inner.centerY * outer.scale;
    final rx = lx * c - ly * s;
    final ry = lx * s + ly * c;
    return LayerTransform(
      centerX: outer.centerX + rx,
      centerY: outer.centerY + ry,
      scale: outer.scale * inner.scale,
      rotationRad: outer.rotationRad + inner.rotationRad,
      opacity: (outer.opacity * inner.opacity).clamp(0.0, 1.0),
    );
  }

  /// Express [world] relative to [group] pivot (inverse of [multiply]).
  static LayerTransform localFromWorld(
    LayerTransform group,
    LayerTransform world,
  ) {
    final dx = world.centerX - group.centerX;
    final dy = world.centerY - group.centerY;
    final c = math.cos(-group.rotationRad);
    final s = math.sin(-group.rotationRad);
    final rx = dx * c - dy * s;
    final ry = dx * s + dy * c;
    final gScale = group.scale.abs() < 1e-9 ? 1.0 : group.scale;
    return LayerTransform(
      centerX: rx / gScale,
      centerY: ry / gScale,
      scale: world.scale / gScale,
      rotationRad: world.rotationRad - group.rotationRad,
      opacity: group.opacity.abs() < 1e-9
          ? world.opacity
          : (world.opacity / group.opacity).clamp(0.0, 1.0),
    );
  }

  /// Apply uniform delta (translation, scale, rotation) about [pivot] to [t].
  static LayerTransform applyDeltaAboutPivot({
    required LayerTransform t,
    required Offset pivot,
    required Offset translation,
    required double scaleFactor,
    required double rotationDelta,
  }) {
    final dx = t.centerX - pivot.dx;
    final dy = t.centerY - pivot.dy;
    final c = math.cos(rotationDelta);
    final s = math.sin(rotationDelta);
    final rx = (dx * c - dy * s) * scaleFactor;
    final ry = (dx * s + dy * c) * scaleFactor;
    return t.copyWith(
      centerX: pivot.dx + rx + translation.dx,
      centerY: pivot.dy + ry + translation.dy,
      scale: t.scale * scaleFactor,
      rotationRad: t.rotationRad + rotationDelta,
    );
  }
}
