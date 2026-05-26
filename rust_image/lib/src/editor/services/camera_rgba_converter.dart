import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:rust_image/src/rust/api/image.dart';

/// YUV420 [CameraImage] → RGBA for Rust beauty pipeline (Nexus A).
abstract final class CameraRgbaConverter {
  /// Convert camera frame to [RgbaImageBuffer] (full frame dimensions).
  static RgbaImageBuffer? toRgba(CameraImage image) {
    final width = image.width;
    final height = image.height;
    if (width <= 0 || height <= 0 || image.planes.isEmpty) return null;

    if (image.planes.length == 2) {
      return _nv21ToRgba(image);
    }
    if (image.planes.length >= 3) {
      return _yuv420ToRgba(image);
    }
    return null;
  }

  static RgbaImageBuffer? _yuv420ToRgba(CameraImage image) {
    final width = image.width;
    final height = image.height;
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];
    final uPixel = uPlane.bytesPerPixel ?? 1;
    final vPixel = vPlane.bytesPerPixel ?? 1;

    final out = Uint8List(width * height * 4);
    var o = 0;
    for (var y = 0; y < height; y++) {
      final yRow = y * yPlane.bytesPerRow;
      final uvRow = (y >> 1);
      for (var x = 0; x < width; x++) {
        final yi = yRow + x;
        if (yi >= yPlane.bytes.length) continue;
        final uvi = uvRow * uPlane.bytesPerRow + (x >> 1) * uPixel;
        final vvi = uvRow * vPlane.bytesPerRow + (x >> 1) * vPixel;
        if (uvi >= uPlane.bytes.length || vvi >= vPlane.bytes.length) continue;

        final rgb = _yuvToRgb(
          yPlane.bytes[yi],
          uPlane.bytes[uvi],
          vPlane.bytes[vvi],
        );
        out[o++] = rgb[0];
        out[o++] = rgb[1];
        out[o++] = rgb[2];
        out[o++] = 255;
      }
    }
    return RgbaImageBuffer(width: width, height: height, pixels: out);
  }

  /// NV21 / NV12-style interleaved UV plane (common on Android).
  static RgbaImageBuffer? _nv21ToRgba(CameraImage image) {
    final width = image.width;
    final height = image.height;
    final yPlane = image.planes[0];
    final uvPlane = image.planes[1];
    final uvPixel = uvPlane.bytesPerPixel ?? 2;

    final out = Uint8List(width * height * 4);
    var o = 0;
    for (var y = 0; y < height; y++) {
      final yRow = y * yPlane.bytesPerRow;
      final uvRow = (y >> 1) * uvPlane.bytesPerRow;
      for (var x = 0; x < width; x++) {
        final yi = yRow + x;
        if (yi >= yPlane.bytes.length) continue;
        final uvIndex = uvRow + (x >> 1) * uvPixel;
        if (uvIndex + 1 >= uvPlane.bytes.length) continue;

        // NV21: V then U in interleaved plane.
        final vVal = uvPlane.bytes[uvIndex];
        final uVal = uvPlane.bytes[uvIndex + 1];
        final rgb = _yuvToRgb(yPlane.bytes[yi], uVal, vVal);
        out[o++] = rgb[0];
        out[o++] = rgb[1];
        out[o++] = rgb[2];
        out[o++] = 255;
      }
    }
    return RgbaImageBuffer(width: width, height: height, pixels: out);
  }

  /// Downscale RGBA so live beauty stays ≤ [maxEdge] (720p target).
  static RgbaImageBuffer downscaleMaxEdge(RgbaImageBuffer src, int maxEdge) {
    if (maxEdge <= 0) return src;
    final w = src.width;
    final h = src.height;
    final edge = w > h ? w : h;
    if (edge <= maxEdge) return src;
    final scale = maxEdge / edge;
    final nw = (w * scale).round().clamp(1, w);
    final nh = (h * scale).round().clamp(1, h);
    final out = Uint8List(nw * nh * 4);
    for (var y = 0; y < nh; y++) {
      final sy = (y * h / nh).floor().clamp(0, h - 1);
      for (var x = 0; x < nw; x++) {
        final sx = (x * w / nw).floor().clamp(0, w - 1);
        final si = (sy * w + sx) * 4;
        final di = (y * nw + x) * 4;
        out[di] = src.pixels[si];
        out[di + 1] = src.pixels[si + 1];
        out[di + 2] = src.pixels[si + 2];
        out[di + 3] = src.pixels[si + 3];
      }
    }
    return RgbaImageBuffer(width: nw, height: nh, pixels: out);
  }

  /// Mirror front-camera preview horizontally (matches [CameraPreview] on Android).
  static RgbaImageBuffer mirrorHorizontal(RgbaImageBuffer src) {
    if (!Platform.isAndroid) return src;
    final w = src.width;
    final h = src.height;
    final out = Uint8List.fromList(src.pixels);
    for (var y = 0; y < h; y++) {
      final row = y * w * 4;
      for (var x = 0; x < w ~/ 2; x++) {
        final left = row + x * 4;
        final right = row + (w - 1 - x) * 4;
        for (var c = 0; c < 4; c++) {
          final t = out[left + c];
          out[left + c] = out[right + c];
          out[right + c] = t;
        }
      }
    }
    return RgbaImageBuffer(width: w, height: h, pixels: out);
  }

  static List<int> _yuvToRgb(int y, int u, int v) {
    final c = y - 16;
    final d = u - 128;
    final e = v - 128;
    final r = ((298 * c + 409 * e + 128) >> 8).clamp(0, 255);
    final g = ((298 * c - 100 * d - 208 * e + 128) >> 8).clamp(0, 255);
    final b = ((298 * c + 516 * d + 128) >> 8).clamp(0, 255);
    return [r, g, b];
  }
}
