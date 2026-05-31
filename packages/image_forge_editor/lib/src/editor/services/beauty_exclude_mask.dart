import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_forge/image_forge.dart';

/// Paints soft brush strokes into a beauty exclusion mask (255 = no effect).
abstract final class BeautyExcludeMask {
  static SegmentationMask empty({required int width, required int height}) {
    return SegmentationMask(
      width: width,
      height: height,
      pixels: Uint8List(width * height),
    );
  }

  static bool hasEffect(SegmentationMask? mask) {
    if (mask == null || mask.pixels.isEmpty) return false;
    return mask.pixels.any((v) => v > 0);
  }

  /// Nearest-neighbor upscale/downscale for export at a different resolution.
  static SegmentationMask scaledTo({
    required SegmentationMask source,
    required int width,
    required int height,
  }) {
    if (source.width == width && source.height == height) return source;
    final out = Uint8List(width * height);
    final sw = source.width;
    final sh = source.height;
    if (sw <= 0 || sh <= 0) {
      return SegmentationMask(width: width, height: height, pixels: out);
    }
    for (var y = 0; y < height; y++) {
      final sy = (y * sh / height).floor().clamp(0, sh - 1);
      for (var x = 0; x < width; x++) {
        final sx = (x * sw / width).floor().clamp(0, sw - 1);
        out[y * width + x] = source.pixels[sy * sw + sx];
      }
    }
    return SegmentationMask(width: width, height: height, pixels: out);
  }

  /// Stamp a stroke in image pixel space onto [mask] (mutates pixels in place).
  static void stampStroke({
    required SegmentationMask mask,
    required List<Offset> points,
    required double radiusPx,
    double strength = 1.0,
  }) {
    if (points.isEmpty || radiusPx <= 0.5) return;
    final w = mask.width;
    final h = mask.height;
    final px = mask.pixels;
    final r = radiusPx.clamp(2.0, 128.0);
    final r2 = r * r;
    final peak = (255 * strength.clamp(0.0, 1.0)).round().clamp(0, 255);

    void stamp(Offset p) {
      final cx = p.dx.round();
      final cy = p.dy.round();
      final x0 = math.max(0, cx - r.ceil());
      final x1 = math.min(w - 1, cx + r.ceil());
      final y0 = math.max(0, cy - r.ceil());
      final y1 = math.min(h - 1, cy + r.ceil());
      for (var y = y0; y <= y1; y++) {
        final row = y * w;
        for (var x = x0; x <= x1; x++) {
          final dx = x - p.dx;
          final dy = y - p.dy;
          final d2 = dx * dx + dy * dy;
          if (d2 > r2) continue;
          final t = 1.0 - math.sqrt(d2) / r;
          final add = (peak * t * t).round();
          final i = row + x;
          final next = px[i] + add;
          px[i] = next > 255 ? 255 : next;
        }
      }
    }

    if (points.length == 1) {
      stamp(points.first);
      return;
    }
    for (var i = 0; i < points.length - 1; i++) {
      final a = points[i];
      final b = points[i + 1];
      final dist = (b - a).distance;
      final steps = math.max(1, (dist / (r * 0.35)).ceil());
      for (var s = 0; s <= steps; s++) {
        stamp(Offset.lerp(a, b, s / steps)!);
      }
    }
  }
}
