import 'dart:math' as math;
import 'dart:ui';

import '../models/layer_transform.dart';
import '../models/overlay_layer.dart';

/// Axis-aligned bounds for layers in image pixel space (Sprint 17).
abstract final class LayerBounds {
  static Size sourceSize(OverlayLayer layer) {
    return switch (layer) {
      StickerLayer(:final userBytes, :final userSourceWidth, :final userSourceHeight)
          when userBytes != null && userBytes.isNotEmpty =>
        userSourceWidth > 0 && userSourceHeight > 0
            ? Size(userSourceWidth.toDouble(), userSourceHeight.toDouble())
            : const Size(512, 512),
      EmojiLayer(:final fontSize) => Size.square(fontSize * 1.35),
      TextLayer(:final fontSize, :final padding, :final text) => Size(
          (text.length * fontSize * 0.55 + padding * 2).clamp(48, 420),
          fontSize + padding * 2,
        ),
      StickerLayer(:final cachedWidth, :final cachedHeight)
          when cachedWidth > 0 && cachedHeight > 0 =>
        Size(cachedWidth.toDouble(), cachedHeight.toDouble()),
      StickerLayer() => const Size(120, 120),
      ShapeLayer(:final width, :final height) => Size(width, height),
      GroupLayer(:final children) => _unionSourceSize(children),
      PaintStrokeLayer(:final points) => _paintSourceSize(points),
      _ when layer.cachedWidth > 0 && layer.cachedHeight > 0 =>
        Size(layer.cachedWidth.toDouble(), layer.cachedHeight.toDouble()),
      _ => const Size(80, 80),
    };
  }

  static Size _unionSourceSize(List<OverlayLayer> children) {
    if (children.isEmpty) return const Size(80, 80);
    var maxW = 0.0;
    var maxH = 0.0;
    for (final c in children) {
      final s = sourceSize(c);
      maxW = math.max(maxW, s.width);
      maxH = math.max(maxH, s.height);
    }
    return Size(maxW, maxH);
  }

  static Size _paintSourceSize(List<Offset> points) {
    if (points.isEmpty) return const Size(1, 1);
    var minX = points.first.dx;
    var maxX = points.first.dx;
    var minY = points.first.dy;
    var maxY = points.first.dy;
    for (final p in points.skip(1)) {
      minX = math.min(minX, p.dx);
      maxX = math.max(maxX, p.dx);
      minY = math.min(minY, p.dy);
      maxY = math.max(maxY, p.dy);
    }
    return Size(
      math.max(1, maxX - minX),
      math.max(1, maxY - minY),
    );
  }

  /// World transform for a layer (composes group ancestors).
  static LayerTransform worldTransform(
    OverlayLayer layer, {
    LayerTransform? parentGroup,
  }) {
    if (parentGroup == null) return layer.transform;
    return LayerTransform.multiply(parentGroup, layer.transform);
  }

  /// Rotated AABB in image pixels for hit-testing and marquee select.
  static Rect? boundsInImagePixels(
    OverlayLayer layer, {
    LayerTransform? parentGroup,
  }) {
    if (layer is PaintStrokeLayer) {
      return _paintBounds(layer, parentGroup: parentGroup);
    }
    if (layer is GroupLayer) {
      return unionBounds(layer.children, parentGroup: layer.transform);
    }

    final t = worldTransform(layer, parentGroup: parentGroup);
    final source = sourceSize(layer);
    final hw = source.width * t.scale / 2;
    final hh = source.height * t.scale / 2;
    if (hw <= 0 || hh <= 0) return null;

    final corners = [
      Offset(-hw, -hh),
      Offset(hw, -hh),
      Offset(hw, hh),
      Offset(-hw, hh),
    ];
    final c = math.cos(t.rotationRad);
    final s = math.sin(t.rotationRad);
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;
    for (final p in corners) {
      final rx = p.dx * c - p.dy * s + t.centerX;
      final ry = p.dx * s + p.dy * c + t.centerY;
      minX = math.min(minX, rx);
      minY = math.min(minY, ry);
      maxX = math.max(maxX, rx);
      maxY = math.max(maxY, ry);
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  static Rect? _paintBounds(
    PaintStrokeLayer layer, {
    LayerTransform? parentGroup,
  }) {
    if (layer.points.isEmpty) return null;
    var minX = layer.points.first.dx;
    var maxX = layer.points.first.dx;
    var minY = layer.points.first.dy;
    var maxY = layer.points.first.dy;
    for (final p in layer.points.skip(1)) {
      minX = math.min(minX, p.dx);
      maxX = math.max(maxX, p.dx);
      minY = math.min(minY, p.dy);
      maxY = math.max(maxY, p.dy);
    }
    final pad = layer.width / 2;
    final rect = Rect.fromLTRB(
      minX - pad,
      minY - pad,
      maxX + pad,
      maxY + pad,
    );
    if (parentGroup == null) return rect;
    final t = worldTransform(layer, parentGroup: parentGroup);
    return boundsInImagePixels(
      PaintStrokeLayer(
        id: layer.id,
        transform: t,
        points: [
          Offset(rect.left, rect.top),
          Offset(rect.right, rect.bottom),
        ],
        width: 0,
      ),
    );
  }

  static Rect? unionBounds(
    Iterable<OverlayLayer> layers, {
    LayerTransform? parentGroup,
  }) {
    Rect? union;
    for (final layer in layers) {
      final b = boundsInImagePixels(layer, parentGroup: parentGroup);
      if (b == null) continue;
      union = union == null ? b : union.expandToInclude(b);
    }
    return union;
  }

  static bool intersects(Rect a, Rect b) => a.overlaps(b);
}
