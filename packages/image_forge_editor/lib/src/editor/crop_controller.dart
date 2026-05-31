import 'package:flutter/material.dart';

import 'draw_placement.dart';

/// Instagram-style crop aspect presets (aligned with [BlankAspect]).
enum CropAspect {
  free,
  square1x1,
  portrait4x5,
  story9x16,
  landscape16x9,
  original,
}

extension CropAspectX on CropAspect {
  String get label => switch (this) {
        CropAspect.free => 'Free',
        CropAspect.square1x1 => '1:1',
        CropAspect.portrait4x5 => '4:5',
        CropAspect.story9x16 => '9:16',
        CropAspect.landscape16x9 => '16:9',
        CropAspect.original => 'Original',
      };

  /// Target width/height ratio, or null for free/original.
  double? get targetRatio => switch (this) {
        CropAspect.free || CropAspect.original => null,
        CropAspect.square1x1 => 1,
        CropAspect.portrait4x5 => 4 / 5,
        CropAspect.story9x16 => 9 / 16,
        CropAspect.landscape16x9 => 16 / 9,
      };
}

/// Shared crop rect — synced with Transform panel and preview overlay.
class CropController extends ChangeNotifier {
  CropAspect aspect = CropAspect.free;

  int imageWidth = 1;
  int imageHeight = 1;

  int cropX = 0;
  int cropY = 0;
  int cropW = 1;
  int cropH = 1;

  /// Live straighten preview (−15° … +15°). Reset to 0 after apply.
  double straightenDegrees = 0;

  void syncImageSize(int width, int height) {
    if (width <= 0 || height <= 0) return;
    if (imageWidth == width && imageHeight == height) return;
    imageWidth = width;
    imageHeight = height;
    _resetCropToDefault();
    notifyListeners();
  }

  void _resetCropToDefault() {
    if (aspect == CropAspect.original) {
      cropX = 0;
      cropY = 0;
      cropW = imageWidth;
      cropH = imageHeight;
      return;
    }
    cropW = (imageWidth * 0.8).round().clamp(1, imageWidth);
    cropH = (imageHeight * 0.8).round().clamp(1, imageHeight);
    cropX = ((imageWidth - cropW) / 2).round();
    cropY = ((imageHeight - cropH) / 2).round();
    if (aspect != CropAspect.free) {
      applyAspect(aspect);
    }
  }

  void setAspect(CropAspect value) {
    if (aspect == value) return;
    aspect = value;
    applyAspect(value);
    notifyListeners();
  }

  void applyAspect(CropAspect value) {
    aspect = value;
    final w = imageWidth;
    final h = imageHeight;
    if (w <= 0 || h <= 0) return;

    if (value == CropAspect.original) {
      cropX = 0;
      cropY = 0;
      cropW = w;
      cropH = h;
      return;
    }

    final ratio = value.targetRatio;
    if (ratio == null) {
      return;
    }

    int cw;
    int ch;
    if (ratio >= w / h) {
      cw = w;
      ch = (w / ratio).round().clamp(1, h);
    } else {
      ch = h;
      cw = (h * ratio).round().clamp(1, w);
    }
    cropW = cw;
    cropH = ch;
    cropX = ((w - cw) / 2).round().clamp(0, w - cw);
    cropY = ((h - ch) / 2).round().clamp(0, h - ch);
  }

  void setCropRect(int x, int y, int width, int height) {
    final maxW = imageWidth;
    final maxH = imageHeight;
    var cw = width.clamp(32, maxW);
    var ch = height.clamp(32, maxH);
    final locked = aspect.targetRatio;
    if (locked != null) {
      if (cw / ch > locked) {
        cw = (ch * locked).round().clamp(32, maxW);
      } else {
        ch = (cw / locked).round().clamp(32, maxH);
      }
    }
    cropW = cw;
    cropH = ch;
    cropX = x.clamp(0, maxW - cw);
    cropY = y.clamp(0, maxH - ch);
    notifyListeners();
  }

  void moveCropBy(int dx, int dy) {
    setCropRect(cropX + dx, cropY + dy, cropW, cropH);
  }

  void setStraightenDegrees(double degrees) {
    final d = degrees.clamp(-15.0, 15.0);
    if ((straightenDegrees - d).abs() < 0.001) return;
    straightenDegrees = d;
    notifyListeners();
  }

  void resetStraighten() {
    if (straightenDegrees == 0) return;
    straightenDegrees = 0;
    notifyListeners();
  }

  void resizeCropFromCorner({
    required bool top,
    required bool left,
    required int anchorX,
    required int anchorY,
  }) {
    var x0 = left ? anchorX : cropX;
    var y0 = top ? anchorY : cropY;
    var x1 = left ? cropX + cropW : anchorX;
    var y1 = top ? cropY + cropH : anchorY;

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

    var w = (x1 - x0).clamp(32, imageWidth);
    var h = (y1 - y0).clamp(32, imageHeight);
    final locked = aspect.targetRatio;
    if (locked != null) {
      if (w / h > locked) {
        w = (h * locked).round().clamp(32, imageWidth);
      } else {
        h = (w / locked).round().clamp(32, imageHeight);
      }
      if (left) {
        x0 = x1 - w;
      } else {
        x1 = x0 + w;
      }
      if (top) {
        y0 = y1 - h;
      } else {
        y1 = y0 + h;
      }
    }

    setCropRect(x0, y0, w, h);
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
    final rect = DrawPlacementController.containRect(imageSize, childSize);
    if (!rect.contains(untransformed)) return null;
    final scale = rect.width / imageWidth;
    final x = ((untransformed.dx - rect.left) / scale).clamp(0.0, imageWidth.toDouble());
    final y = ((untransformed.dy - rect.top) / scale).clamp(0.0, imageHeight.toDouble());
    return Offset(x, y);
  }

  Rect cropRectInChild(Size childSize) {
    final tl = imagePixelToChild(Offset(cropX.toDouble(), cropY.toDouble()), childSize);
    final br = imagePixelToChild(
      Offset((cropX + cropW).toDouble(), (cropY + cropH).toDouble()),
      childSize,
    );
    return Rect.fromPoints(tl, br);
  }

  Offset imagePixelToChild(Offset pixel, Size childSize) {
    final imageSize = Size(imageWidth.toDouble(), imageHeight.toDouble());
    final rect = DrawPlacementController.containRect(imageSize, childSize);
    final scale = rect.width / imageWidth;
    return Offset(
      rect.left + pixel.dx * scale,
      rect.top + pixel.dy * scale,
    );
  }
}
