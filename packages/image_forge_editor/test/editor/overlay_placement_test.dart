import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_forge_editor/src/editor/overlay_placement.dart';

void main() {
  test('childPointToImagePixel maps child space without viewer matrix', () {
    final p = OverlayPlacementController()
      ..imageWidth = 1000
      ..imageHeight = 500
      ..x = 100
      ..y = 50
      ..overlayWidth = 200
      ..overlayHeight = 100;

    const childSize = Size(400, 400);
    final rect = p.imageRectInChild(childSize);
    final scale = p.displayScale(childSize);

    final local = Offset(rect.left + 250 * scale, rect.top + 125 * scale);
    final px = p.childPointToImagePixel(local, childSize);
    expect(px, isNotNull);
    expect(px!.dx, closeTo(250, 0.5));
    expect(px.dy, closeTo(125, 0.5));
  });

  test('resizeFromCorner grows overlay from bottom-right drag', () {
    final p = OverlayPlacementController()
      ..imageWidth = 1000
      ..imageHeight = 1000
      ..x = 100
      ..y = 100
      ..overlayWidth = 200
      ..overlayHeight = 150;

    p.resizeFromCorner(
      top: false,
      left: false,
      anchorX: 400,
      anchorY: 350,
    );

    expect(p.x, 100);
    expect(p.y, 100);
    expect(p.overlayWidth, 300);
    expect(p.overlayHeight, 250);
  });
}
