import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'draw_placement.dart';

/// Maps between image pixel space and the editor overlay stack.
///
/// The overlay [Stack] sits **inside** the [InteractiveViewer]'s child, so all
/// positions and gesture deltas are already in pre-transform child space — we
/// must not apply the viewer matrix again here (Flutter does that on paint
/// and hit-test). Drag deltas captured via `globalToLocal` automatically scale
/// with the viewer zoom because the stack box itself is transformed.
class LayerCoordinates {
  LayerCoordinates({
    required this.imageWidth,
    required this.imageHeight,
    required this.childSize,
  });

  final int imageWidth;
  final int imageHeight;
  final Size childSize;

  Rect get imageRect {
    if (imageWidth <= 0 || imageHeight <= 0) return Rect.zero;
    return DrawPlacementController.containRect(
      Size(imageWidth.toDouble(), imageHeight.toDouble()),
      childSize,
    );
  }

  double get displayScale {
    final rect = imageRect;
    if (rect.width <= 0) return 1;
    return rect.width / imageWidth;
  }

  /// Image pixel → position in overlay stack (pre-transform child) space.
  Offset imagePixelToStack(Offset pixel) {
    final rect = imageRect;
    final scale = displayScale;
    return Offset(
      rect.left + pixel.dx * scale,
      rect.top + pixel.dy * scale,
    );
  }

  /// Overlay stack position → image pixel.
  ///
  /// [clampToImage] should be false while dragging layers so the sticker can
  /// move smoothly past the image edge; clamp only when persisting if needed.
  Offset stackToImagePixel(Offset stackLocal, {bool clampToImage = false}) {
    final rect = imageRect;
    final scale = displayScale;
    if (scale <= 0) return Offset.zero;
    var x = (stackLocal.dx - rect.left) / scale;
    var y = (stackLocal.dy - rect.top) / scale;
    if (clampToImage) {
      x = x.clamp(0.0, imageWidth.toDouble());
      y = y.clamp(0.0, imageHeight.toDouble());
    }
    return Offset(x, y);
  }

  /// Converts a screen-space focal movement (from [ScaleUpdateDetails]) into
  /// image-pixel delta. Matches pro_image_editor's
  /// `focalPointDelta / editorScaleFactor`, but uses the stack [RenderBox] so
  /// InteractiveViewer zoom/pan is accounted for automatically.
  Offset globalFocalDeltaToImagePixel({
    required Offset globalFocalPoint,
    required Offset globalFocalPointDelta,
    required RenderBox stackBox,
  }) {
    final scale = displayScale;
    if (scale <= 0) return Offset.zero;
    final now = stackBox.globalToLocal(globalFocalPoint);
    final prev = stackBox.globalToLocal(globalFocalPoint - globalFocalPointDelta);
    return Offset(
      (now.dx - prev.dx) / scale,
      (now.dy - prev.dy) / scale,
    );
  }

  /// Layer widget local point → overlay stack space (via shared screen space).
  Offset layerLocalToStack(
    Offset localInLayer,
    RenderBox layerBox,
    RenderBox stackBox,
  ) {
    final global = layerBox.localToGlobal(localInLayer);
    return stackBox.globalToLocal(global);
  }

  /// Display size in stack logical pixels for a layer bitmap / glyph.
  Size layerDisplaySize({
    required double sourceWidth,
    required double sourceHeight,
    required double layerScale,
  }) {
    final s = displayScale * layerScale;
    return Size(
      math.max(8, sourceWidth * s),
      math.max(8, sourceHeight * s),
    );
  }

  /// Allowed [LayerTransform.scale] for pinch — large enough to cover the full image.
  ({double min, double max}) layerScaleLimits({
    required double sourceWidth,
    required double sourceHeight,
  }) {
    final sw = sourceWidth > 0 ? sourceWidth : 1.0;
    final sh = sourceHeight > 0 ? sourceHeight : 1.0;
    final iw = imageWidth.toDouble();
    final ih = imageHeight.toDouble();

    // Layer extent in image pixels ≈ source × scale; allow ~3× the long image edge.
    final cover = math.max(
      iw > 0 ? iw / sw : 64.0,
      ih > 0 ? ih / sh : 64.0,
    );
    final maxScale = math.max(32.0, cover * 3.0);

    return (min: 0.05, max: maxScale);
  }

  double clampLayerScale(
    double scale, {
    required double sourceWidth,
    required double sourceHeight,
  }) {
    final lim = layerScaleLimits(
      sourceWidth: sourceWidth,
      sourceHeight: sourceHeight,
    );
    return scale.clamp(lim.min, lim.max);
  }
}
