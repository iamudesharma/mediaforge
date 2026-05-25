import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/overlay_layer.dart';
import 'shape_paths.dart';
import 'sticker_catalog.dart';

/// Rasterize overlay layers to RGBA bytes for preview cache / export bake.
abstract final class LayerRasterizer {
  static Future<({Uint8List pixels, int width, int height})> rasterizeEmoji({
    required String glyph,
    required double fontSize,
  }) async {
    final tp = TextPainter(
      text: TextSpan(
        text: glyph,
        style: TextStyle(fontSize: fontSize),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final w = (tp.width + 8).ceil().clamp(1, 4096);
    final h = (tp.height + 8).ceil().clamp(1, 4096);
    return _textPainterToRgba(tp, w, h, offset: const Offset(4, 4));
  }

  static Future<({Uint8List pixels, int width, int height})> rasterizeText(
    TextLayer layer,
  ) async {
    final style = TextStyle(
      color: layer.color,
      fontSize: layer.fontSize,
      fontWeight: FontWeight.w600,
    );
    final tp = TextPainter(
      text: TextSpan(text: layer.text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();

    final pad = layer.padding;
    final w = (tp.width + pad * 2).ceil().clamp(1, 2048);
    final h = (tp.height + pad * 2).ceil().clamp(1, 2048);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    if (layer.backgroundStyle != TextBackgroundStyle.none) {
      final rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
        Radius.circular(layer.cornerRadius),
      );
      canvas.drawRRect(
        rrect,
        Paint()..color = layer.backgroundColor,
      );
    }
    tp.paint(canvas, Offset(pad, pad));
    final picture = recorder.endRecording();
    final image = await picture.toImage(w, h);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    if (bytes == null) throw StateError('Failed to rasterize text');
    return (pixels: bytes.buffer.asUint8List(), width: w, height: h);
  }

  static Future<({Uint8List pixels, int width, int height})> rasterizeStickerBytes(
    Uint8List pngOrJpeg, {
    StickerShapeMask mask = StickerShapeMask.none,
    double cornerRadius = 16,
  }) async {
    final codec = await ui.instantiateImageCodec(pngOrJpeg);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final w = image.width;
    final h = image.height;

    if (mask == StickerShapeMask.none) {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      if (bytes == null) throw StateError('Failed to decode sticker');
      return (pixels: bytes.buffer.asUint8List(), width: w, height: h);
    }

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final clip = ShapePaths.build(
      mask,
      width: w.toDouble(),
      height: h.toDouble(),
      cornerRadius: cornerRadius,
    );
    canvas.clipPath(clip);
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..filterQuality = FilterQuality.medium,
    );
    image.dispose();

    final picture = recorder.endRecording();
    final out = await picture.toImage(w, h);
    final bytes = await out.toByteData(format: ui.ImageByteFormat.rawRgba);
    out.dispose();
    if (bytes == null) throw StateError('Failed to rasterize masked sticker');
    return (pixels: bytes.buffer.asUint8List(), width: w, height: h);
  }

  static Future<({Uint8List pixels, int width, int height})> rasterizeIconSticker({
    required IconData icon,
    required Color color,
    double size = 96,
  }) async {
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: size,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final w = (tp.width + 16).ceil().clamp(1, 256);
    final h = (tp.height + 16).ceil().clamp(1, 256);
    return _textPainterToRgba(tp, w, h, offset: const Offset(8, 8));
  }

  static Future<void> cacheLayerBitmap(OverlayLayer layer) async {
    if (layer is PaintStrokeLayer) return;
    if (layer.cachedPixels != null && layer.cachedWidth > 0) return;

    final ({Uint8List pixels, int width, int height}) result = switch (layer) {
      EmojiLayer(:final glyph, :final fontSize) =>
        await rasterizeEmoji(glyph: glyph, fontSize: fontSize),
      TextLayer() => await rasterizeText(layer),
      StickerLayer sticker => await _rasterizeSticker(sticker),
      ShapeLayer(:final color) => await rasterizeIconSticker(
          icon: Icons.crop_square,
          color: color,
        ),
      PaintStrokeLayer() => throw StateError('paint stroke has no bitmap'),
      _ => throw StateError('Unknown overlay layer'),
    };
    layer.cachedPixels = result.pixels;
    layer.cachedWidth = result.width;
    layer.cachedHeight = result.height;
  }

  static Future<({Uint8List pixels, int width, int height})> _rasterizeSticker(
    StickerLayer layer,
  ) async {
    final mask = layer.shapeMask;
    final radius = layer.maskCornerRadius;
    if (layer.userBytes != null) {
      return rasterizeStickerBytes(
        layer.userBytes!,
        mask: mask,
        cornerRadius: radius,
      );
    }
    final key = layer.assetKey ?? 'star';
    final assetBytes = await _loadStickerAsset(key);
    if (assetBytes != null) {
      return rasterizeStickerBytes(
        assetBytes,
        mask: mask,
        cornerRadius: radius,
      );
    }
    return rasterizeIconSticker(
      icon: builtinStickerIcon(key),
      color: const Color(0xFF4EDEA3),
    );
  }

  /// Clears cached bitmap so shape / image changes re-rasterize.
  static void invalidateCache(OverlayLayer layer) {
    layer.cachedPixels = null;
    // Keep [StickerLayer.userSourceWidth]/[userSourceHeight] for layout; only drop raster dims.
    if (layer is StickerLayer &&
        layer.userBytes != null &&
        layer.userBytes!.isNotEmpty) {
      return;
    }
    layer.cachedWidth = 0;
    layer.cachedHeight = 0;
  }

  static Future<Uint8List?> _loadStickerAsset(String key) async {
    try {
      final data = await rootBundle.load(
        'packages/${StickerCatalog.assetPackage}/${StickerCatalog.assetPath(key)}',
      );
      return data.buffer.asUint8List();
    } catch (_) {
      try {
        final data = await rootBundle.load(
          'packages/${StickerCatalog.assetPackage}/${StickerCatalog.assetPath(key)}',
        );
        return data.buffer.asUint8List();
      } catch (_) {
        return null;
      }
    }
  }

  static IconData builtinStickerIcon(String key) => switch (key) {
        'heart' => Icons.favorite,
        'star' => Icons.star,
        'arrow' => Icons.arrow_forward,
        'chat' => Icons.chat_bubble,
        'bolt' => Icons.bolt,
        'check' => Icons.check_circle,
        _ => Icons.star,
      };

  static Future<({Uint8List pixels, int width, int height})> _textPainterToRgba(
    TextPainter tp,
    int w,
    int h, {
    required Offset offset,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    tp.paint(canvas, offset);
    final picture = recorder.endRecording();
    final image = await picture.toImage(w, h);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    if (bytes == null) throw StateError('Rasterize failed');
    return (pixels: bytes.buffer.asUint8List(), width: w, height: h);
  }
}
