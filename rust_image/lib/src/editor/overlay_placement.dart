import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Drag-to-position state for the Overlay tab.
class OverlayPlacementController extends ChangeNotifier {
  int imageWidth = 1;
  int imageHeight = 1;
  int overlayWidth = 100;
  int overlayHeight = 100;

  int x = 24;
  int y = 24;

  void syncImageSize(int width, int height) {
    if (width <= 0 || height <= 0) return;
    if (imageWidth == width && imageHeight == height) return;
    imageWidth = width;
    imageHeight = height;
    notifyListeners();
  }

  void setOverlaySize(int width, int height) {
    if (width > 0) overlayWidth = width;
    if (height > 0) overlayHeight = height;
    notifyListeners();
  }

  void setPosition(int newX, int newY) {
    x = newX;
    y = newY;
    notifyListeners();
  }

  Offset? pointerToImagePixel(
    Offset localInChild,
    Size childSize,
    Matrix4 viewerTransform,
  ) {
    if (imageWidth <= 0 || imageHeight <= 0) return null;

    final inverse = Matrix4.inverted(viewerTransform);
    final untransformed = MatrixUtils.transformPoint(inverse, localInChild);

    final imageSize = Size(imageWidth.toDouble(), imageHeight.toDouble());
    final rect = _containRect(imageSize, childSize);
    if (!rect.contains(untransformed)) return null;

    final scale = rect.width / imageWidth;
    final px = ((untransformed.dx - rect.left) / scale).clamp(0.0, imageWidth.toDouble());
    final py = ((untransformed.dy - rect.top) / scale).clamp(0.0, imageHeight.toDouble());
    return Offset(px, py);
  }

  Offset imagePixelToChild(Offset pixel, Size childSize) {
    final imageSize = Size(imageWidth.toDouble(), imageHeight.toDouble());
    final rect = _containRect(imageSize, childSize);
    final scale = rect.width / imageWidth;
    return Offset(
      rect.left + pixel.dx * scale,
      rect.top + pixel.dy * scale,
    );
  }

  Rect overlayRectInChild(Size childSize) {
    final topLeft = imagePixelToChild(Offset(x.toDouble(), y.toDouble()), childSize);
    final imageSize = Size(imageWidth.toDouble(), imageHeight.toDouble());
    final rect = _containRect(imageSize, childSize);
    final scale = rect.width / imageWidth;
    return Rect.fromLTWH(
      topLeft.dx,
      topLeft.dy,
      overlayWidth * scale,
      overlayHeight * scale,
    );
  }

  static Rect _containRect(Size imageSize, Size boxSize) {
    if (imageSize.width <= 0 || imageSize.height <= 0) return Rect.zero;
    final scale = math.min(
      boxSize.width / imageSize.width,
      boxSize.height / imageSize.height,
    );
    final w = imageSize.width * scale;
    final h = imageSize.height * scale;
    return Rect.fromLTWH(
      (boxSize.width - w) / 2,
      (boxSize.height - h) / 2,
      w,
      h,
    );
  }
}
