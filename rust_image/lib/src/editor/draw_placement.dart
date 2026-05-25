import 'dart:math' as math;

import 'package:flutter/material.dart';

/// What the user is placing on the canvas (Draw tab).
enum DrawPlaceKind { text, line, circle }

/// Shared placement state — synced with Draw panel sliders and canvas drags.
class DrawPlacementController extends ChangeNotifier {
  DrawPlaceKind kind = DrawPlaceKind.text;

  int imageWidth = 1;
  int imageHeight = 1;

  // Text
  int textX = 40;
  int textY = 40;
  double fontSize = 48;
  String text = 'rust_image';

  // Line
  int lineX0 = 0;
  int lineY0 = 0;
  int lineX1 = 200;
  int lineY1 = 200;

  // Circle
  int circleX = 200;
  int circleY = 200;
  int circleRadius = 80;

  void syncImageSize(int width, int height) {
    if (width <= 0 || height <= 0) return;
    if (imageWidth == width && imageHeight == height) return;
    imageWidth = width;
    imageHeight = height;
    circleX = width ~/ 2;
    circleY = height ~/ 2;
    circleRadius = (width < height ? width : height) ~/ 6;
    lineX1 = width;
    lineY1 = height;
    notifyListeners();
  }

  void setKind(DrawPlaceKind value) {
    if (kind == value) return;
    kind = value;
    notifyListeners();
  }

  void setTextPos(int x, int y) {
    textX = x.clamp(0, imageWidth);
    textY = y.clamp(0, imageHeight);
    notifyListeners();
  }

  void setLineStart(int x, int y) {
    lineX0 = x.clamp(0, imageWidth);
    lineY0 = y.clamp(0, imageHeight);
    notifyListeners();
  }

  void setLineEnd(int x, int y) {
    lineX1 = x.clamp(0, imageWidth);
    lineY1 = y.clamp(0, imageHeight);
    notifyListeners();
  }

  void setCircleCenter(int x, int y) {
    circleX = x.clamp(0, imageWidth);
    circleY = y.clamp(0, imageHeight);
    notifyListeners();
  }

  void setCircleRadius(int r) {
    circleRadius = r.clamp(4, imageWidth);
    notifyListeners();
  }

  void setText(String value) {
    text = value;
    notifyListeners();
  }

  void setFontSize(double value) {
    fontSize = value;
    notifyListeners();
  }

  /// Map pointer in [InteractiveViewer] child space → image pixel coordinates.
  Offset? pointerToImagePixel(
    Offset localInChild,
    Size childSize,
    Matrix4 viewerTransform,
  ) {
    if (imageWidth <= 0 || imageHeight <= 0) return null;

    final inverse = Matrix4.inverted(viewerTransform);
    final untransformed = MatrixUtils.transformPoint(inverse, localInChild);

    final imageSize = Size(imageWidth.toDouble(), imageHeight.toDouble());
    final rect = containRect(imageSize, childSize);
    if (!rect.contains(untransformed)) return null;

    final scale = rect.width / imageWidth;
    final x = ((untransformed.dx - rect.left) / scale).clamp(0.0, imageWidth.toDouble());
    final y = ((untransformed.dy - rect.top) / scale).clamp(0.0, imageHeight.toDouble());
    return Offset(x, y);
  }

  /// Image pixel → position in child stack (for painting handles).
  Offset imagePixelToChild(Offset pixel, Size childSize) {
    final imageSize = Size(imageWidth.toDouble(), imageHeight.toDouble());
    final rect = containRect(imageSize, childSize);
    final scale = rect.width / imageWidth;
    return Offset(
      rect.left + pixel.dx * scale,
      rect.top + pixel.dy * scale,
    );
  }

  static Rect containRect(Size imageSize, Size boxSize) {
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
