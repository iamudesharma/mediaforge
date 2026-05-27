import 'package:rust_image/src/rust/api/layers.dart';
import 'package:rust_image/src/rust_image_editor.dart';

import '../models/layer_stack.dart';
import '../models/overlay_layer.dart';
import 'layer_rasterizer.dart';
import 'rust_worker.dart';

/// Prepare FRB inputs and bake [stack] onto [buffer].
abstract final class LayerBake {
  /// Rasterize overlay layers on the UI thread; composite in worker isolate.
  static Future<
      ({
        List<RasterLayerInput> rasterLayers,
        List<PaintStrokeInput> paintStrokes,
      })> prepareInputs(LayerStack stack) async {
    final flat = stack.flattenForBake();
    final rasterInputs = <RasterLayerInput>[];

    for (final layer in flat) {
      if (!layer.visible) continue;
      if (layer is PaintStrokeLayer) continue;
      await LayerRasterizer.cacheLayerBitmap(layer);
      final pixels = layer.cachedPixels;
      if (pixels == null || layer.cachedWidth <= 0 || layer.cachedHeight <= 0) {
        continue;
      }
      final t = layer.transform;
      rasterInputs.add(
        RasterLayerInput(
          pixels: pixels,
          width: layer.cachedWidth,
          height: layer.cachedHeight,
          centerX: t.centerX,
          centerY: t.centerY,
          scale: t.scale,
          rotationRad: t.rotationRad,
          opacity: t.opacity,
        ),
      );
    }

    final strokeInputs = <PaintStrokeInput>[];
    for (final layer in flat.whereType<PaintStrokeLayer>()) {
      if (!layer.visible || layer.points.length < 2) continue;
      final c = layer.color;
      strokeInputs.add(
        PaintStrokeInput(
          points: layer.points.map((p) => (p.dx, p.dy)).toList(),
          colorR: c.red,
          colorG: c.green,
          colorB: c.blue,
          colorA: c.alpha,
          width: layer.width,
          opacity: layer.opacity,
          erase: layer.brush == PaintBrushKind.eraser,
          brushKind: layer.brush.index,
          filled: layer.filled,
        ),
      );
    }

    return (rasterLayers: rasterInputs, paintStrokes: strokeInputs);
  }

  static Future<RgbaImageBuffer> bakeOnto(
    RgbaImageBuffer buffer,
    LayerStack stack,
  ) async {
    final inputs = await prepareInputs(stack);
    if (inputs.rasterLayers.isEmpty && inputs.paintStrokes.isEmpty) {
      return buffer;
    }
    return RustWorker.bakeLayersRgba(
      buffer: buffer,
      rasterLayers: inputs.rasterLayers,
      paintStrokes: inputs.paintStrokes,
    );
  }
}
