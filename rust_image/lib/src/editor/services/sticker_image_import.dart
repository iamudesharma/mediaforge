import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';

import '../editor_session.dart';
import '../models/layer_transform.dart';
import '../models/overlay_layer.dart';
import '../panels/shape_mask_sheet.dart';
import 'image_bytes_normalizer.dart';
import 'image_source_picker.dart';
import 'layer_rasterizer.dart';
import 'sticker_image_cache.dart';

/// Import gallery images as [StickerLayer]s with shape masks (Sprint 8).
abstract final class StickerImageImport {
  static const defaultLayerScale = 1.4;

  static Future<Size> probeImageDimensions(Uint8List bytes) async {
    final prepared = await ImageBytesNormalizer.prepareForEditor(bytes);
    final dims = await StickerImageCache.dimensionsFor(prepared);
    return Size(dims.width, dims.height);
  }

  static double scaleForCanvas({
    required int canvasWidth,
    required int canvasHeight,
    required double stickerWidth,
    required double stickerHeight,
  }) {
    if (canvasWidth <= 0 || canvasHeight <= 0) return defaultLayerScale;
    final target = math.min(canvasWidth, canvasHeight) * 0.35;
    final longSide = math.max(stickerWidth, stickerHeight);
    if (longSide <= 0) return defaultLayerScale;
    return (target / longSide).clamp(0.15, 8.0);
  }

  /// Top bar / Stickers panel: multi-pick then shape sheet, adds layers.
  static Future<void> importFromGallery(
    BuildContext context,
    EditorSession session, {
    Future<StickerShapeMask?> Function(int imageCount)? pickShapeMask,
  }) async {
    if (!session.hasImage || session.busy) return;

    final images = await ImageSourcePicker.pickMultipleImageBytes();
    if (images.isEmpty || !context.mounted) return;

    final mask = pickShapeMask != null
        ? await pickShapeMask(images.length)
        : await ShapeMaskSheet.pick(
            context,
            imageCount: images.length,
            title: 'Shape for new stickers',
          );
    if (!context.mounted || mask == null) return;

    await _addLayers(
      session: session,
      images: images,
      mask: mask,
    );
  }

  static Future<void> ensureUserSourceDimensions(StickerLayer layer) async {
    if (layer.userBytes == null ||
        layer.userBytes!.isEmpty ||
        layer.userSourceWidth > 0) {
      return;
    }
    final dims = await probeImageDimensions(layer.userBytes!);
    layer.userSourceWidth = dims.width.round();
    layer.userSourceHeight = dims.height.round();
  }

  /// Tap on canvas: change shape for one uploaded image sticker only.
  static Future<void> pickShapeForLayer(
    BuildContext context,
    EditorSession session,
    StickerLayer layer, {
    Future<StickerShapeMask?> Function()? pickShapeMask,
  }) async {
    if (layer.userBytes == null || layer.userBytes!.isEmpty) return;
    await ensureUserSourceDimensions(layer);

    final mask = pickShapeMask != null
        ? await pickShapeMask()
        : await ShapeMaskSheet.pick(
            context,
            imageCount: 1,
            title: 'Sticker shape',
            initial: layer.shapeMask,
          );
    if (!context.mounted || mask == null) return;

    await applyShape(session, layer, mask);
  }

  static Future<void> applyShape(
    EditorSession session,
    StickerLayer layer,
    StickerShapeMask mask,
  ) async {
    session.pushLayerUndo();
    layer.shapeMask = mask;
    LayerRasterizer.invalidateCache(layer);
    session.notifyLayerChanged();
    await LayerRasterizer.cacheLayerBitmap(layer);
    session.notifyLayerChanged();
  }

  static Future<void> _addLayers({
    required EditorSession session,
    required List<Uint8List> images,
    required StickerShapeMask mask,
  }) async {
    final info = session.imageInfo;
    final cx = (info?.width ?? 1080) / 2;
    final cy = (info?.height ?? 1080) / 2;
    final cw = info?.width ?? 1080;
    final ch = info?.height ?? 1080;

    session.pushLayerUndo();
    for (var i = 0; i < images.length; i++) {
      final bytes = await ImageBytesNormalizer.prepareForEditor(images[i]);
      final dims = await probeImageDimensions(bytes);
      final layer = StickerLayer(
        id: newLayerId(),
        transform: LayerTransform(
          centerX: cx + (i % 3 - 1) * 120,
          centerY: cy + (i ~/ 3 - 1) * 120,
          scale: scaleForCanvas(
            canvasWidth: cw,
            canvasHeight: ch,
            stickerWidth: dims.width,
            stickerHeight: dims.height,
          ),
        ),
        userBytes: bytes,
        shapeMask: mask,
      );
      layer.userSourceWidth = dims.width.round();
      layer.userSourceHeight = dims.height.round();
      session.layerStack.add(layer, select: i == images.length - 1);
      unawaited(LayerRasterizer.cacheLayerBitmap(layer));
    }
    session.notifyLayerChanged();
  }
}
