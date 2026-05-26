import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'draw_placement.dart';

/// Drag-to-position and resize state for the Overlay (watermark) tab.
class OverlayPlacementController extends ChangeNotifier {
  int imageWidth = 1;
  int imageHeight = 1;
  int overlayWidth = 100;
  int overlayHeight = 100;

  int x = 24;
  int y = 24;

  static const int minOverlayEdge = 24;

  void syncImageSize(int width, int height) {
    if (width <= 0 || height <= 0) return;
    if (imageWidth == width && imageHeight == height) return;
    imageWidth = width;
    imageHeight = height;
    notifyListeners();
  }

  void setOverlaySize(int width, int height) {
    final w = width
        .clamp(minOverlayEdge, math.max(minOverlayEdge, imageWidth))
        .toInt();
    final h = height
        .clamp(minOverlayEdge, math.max(minOverlayEdge, imageHeight))
        .toInt();
    if (overlayWidth == w && overlayHeight == h) return;
    overlayWidth = w;
    overlayHeight = h;
    normalize();
    notifyListeners();
  }

  void setPosition(int newX, int newY) {
    x = newX;
    y = newY;
    normalize();
    notifyListeners();
  }

  /// Keep watermark rect inside the active preview image (edit-scale pixels).
  void normalize() {
    if (imageWidth <= 0 || imageHeight <= 0) return;
    overlayWidth = overlayWidth
        .clamp(minOverlayEdge, imageWidth)
        .toInt();
    overlayHeight = overlayHeight
        .clamp(minOverlayEdge, imageHeight)
        .toInt();
    final maxX = math.max(0, imageWidth - overlayWidth);
    final maxY = math.max(0, imageHeight - overlayHeight);
    x = x.clamp(0, maxX).toInt();
    y = y.clamp(0, maxY).toInt();
  }

  Rect imageRectInChild(Size childSize) {
    if (imageWidth <= 0 || imageHeight <= 0) return Rect.zero;
    return DrawPlacementController.containRect(
      Size(imageWidth.toDouble(), imageHeight.toDouble()),
      childSize,
    );
  }

  double displayScale(Size childSize) {
    final rect = imageRectInChild(childSize);
    if (rect.width <= 0 || imageWidth <= 0) return 1;
    return rect.width / imageWidth;
  }

  /// Map a point in [InteractiveViewer] child space → image pixels.
  ///
  /// Do not apply [Matrix4.inverted] on the viewer here — Flutter already
  /// delivers child-local coordinates; extra inversion breaks drag when zoomed.
  Offset? childPointToImagePixel(
    Offset localInChild,
    Size childSize, {
    bool clampToImage = true,
  }) {
    if (imageWidth <= 0 || imageHeight <= 0) return null;

    final rect = imageRectInChild(childSize);
    final scale = displayScale(childSize);
    if (scale <= 0) return null;

    var px = (localInChild.dx - rect.left) / scale;
    var py = (localInChild.dy - rect.top) / scale;
    if (clampToImage) {
      px = px.clamp(0.0, imageWidth.toDouble());
      py = py.clamp(0.0, imageHeight.toDouble());
    }
    return Offset(px, py);
  }

  Offset imagePixelToChild(Offset pixel, Size childSize) {
    final rect = imageRectInChild(childSize);
    final scale = displayScale(childSize);
    return Offset(
      rect.left + pixel.dx * scale,
      rect.top + pixel.dy * scale,
    );
  }

  Rect overlayRectInChild(Size childSize) {
    final topLeft = imagePixelToChild(Offset(x.toDouble(), y.toDouble()), childSize);
    final scale = displayScale(childSize);
    return Rect.fromLTWH(
      topLeft.dx,
      topLeft.dy,
      overlayWidth * scale,
      overlayHeight * scale,
    );
  }

  /// Resize watermark rect; ([anchorX], [anchorY]) is the dragged corner in image pixels.
  void resizeFromCorner({
    required bool top,
    required bool left,
    required int anchorX,
    required int anchorY,
  }) {
    var x0 = left ? anchorX : x;
    var y0 = top ? anchorY : y;
    var x1 = left ? x + overlayWidth : anchorX;
    var y1 = top ? y + overlayHeight : anchorY;

    if (x0 > x1) {
      final t = x0;
      x0 = x1;
      x1 = t;
    }
    if (y0 > y1) {
      final t = y0;
      y0 = y1;
      y1 = t;
    }

    overlayWidth = (x1 - x0).clamp(minOverlayEdge, imageWidth).toInt();
    overlayHeight = (y1 - y0).clamp(minOverlayEdge, imageHeight).toInt();
    x = x0;
    y = y0;
    normalize();
    notifyListeners();
  }

  @Deprecated('Use childPointToImagePixel — viewer matrix must not be applied twice')
  Offset? pointerToImagePixel(
    Offset localInChild,
    Size childSize,
    Matrix4 viewerTransform,
  ) =>
      childPointToImagePixel(localInChild, childSize);
}
