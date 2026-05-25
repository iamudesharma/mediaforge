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
}
