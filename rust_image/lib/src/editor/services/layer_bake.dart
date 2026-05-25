import 'package:rust_image/src/rust/api/image.dart';
import 'package:rust_image/src/rust/api/layers.dart';
import 'package:rust_image/src/rust_image_editor.dart';

import '../models/layer_stack.dart';
import '../models/overlay_layer.dart';
import 'layer_rasterizer.dart';

/// Prepare FRB inputs and bake [stack] onto [buffer].
abstract final class LayerBake {
  static Future<RgbaImageBuffer> bakeOnto(
    RgbaImageBuffer buffer,
    LayerStack stack,
  ) async {
    final rasterInputs = <RasterLayerInput>[];

    for (final layer in stack.layers) {
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
    for (final layer in stack.paintStrokes) {
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
        ),
      );
    }

    return RustImageEditor.bakeLayers(
      buffer: buffer,
      rasterLayers: rasterInputs,
      paintStrokes: strokeInputs,
    );
  }
}
