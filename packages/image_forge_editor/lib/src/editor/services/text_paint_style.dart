import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/overlay_layer.dart';

/// Builds a [TextStyle] for canvas preview and rasterization.
TextStyle textPaintStyle(
  TextLayer layer, {
  required double layoutWidth,
  required double layoutHeight,
}) {
  final base = TextStyle(
    fontSize: layer.fontSize,
    fontWeight: layer.fontWeight,
    fontStyle: layer.fontStyle,
    fontFamily: layer.fontFamily,
    shadows: const [],
  );

  if (layer.fillMode == TextFillMode.solid) {
    return base.copyWith(color: layer.color);
  }

  final rect = Rect.fromLTWH(0, 0, layoutWidth, layoutHeight);
  final rad = layer.gradientAngleDeg * math.pi / 180;
  final gradient = LinearGradient(
    colors: [layer.color, layer.gradientEnd],
    transform: GradientRotation(rad),
  );

  return base.copyWith(
    foreground: Paint()..shader = gradient.createShader(rect),
  );
}
