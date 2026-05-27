import 'dart:typed_data';
import 'dart:ui' show Path;

import 'package:flutter/material.dart';

import 'layer_transform.dart';

enum OverlayLayerKind {
  emoji,
  sticker,
  text,
  shape,
  paintStroke,
  group,
}

enum TextBackgroundStyle { none, solid, rounded }

/// Solid fill or linear gradient on text glyphs.
enum TextFillMode { solid, gradient }

enum ShapeKind { rect, ellipse, line, arrow }

enum PaintBrushKind {
  pen,
  marker,
  highlighter,
  eraser,
  neon,
  line,
  arrow,
  doubleArrow,
  rect,
  circle,
  hexagon,
  polygon,
  dashLine,
  dashDotLine,
  blur,
  pixelate,
}

enum EraserMode { object, partial }

/// Clip mask for image stickers (Sprint 8).
enum StickerShapeMask {
  none,
  roundedRect,
  circle,
  ellipse,
  heart,
  star,
  hexagon,
  squircle,
}

/// Base overlay layer (Sprint 6/7 vector stack).
abstract class OverlayLayer {
  OverlayLayer({
    required this.id,
    required this.transform,
    this.visible = true,
    this.cachedPixels,
    this.cachedWidth = 0,
    this.cachedHeight = 0,
  });

  final String id;
  LayerTransform transform;

  /// When false, layer is hidden on canvas and skipped at export bake.
  bool visible;

  /// Pre-rasterized RGBA for export bake (optional until first bake).
  Uint8List? cachedPixels;
  int cachedWidth;
  int cachedHeight;

  OverlayLayerKind get kind;

  OverlayLayer copy();
}

class EmojiLayer extends OverlayLayer {
  EmojiLayer({
    required super.id,
    required super.transform,
    super.visible,
    required this.glyph,
    this.fontSize = 64,
    super.cachedPixels,
    super.cachedWidth,
    super.cachedHeight,
  });

  final String glyph;
  final double fontSize;

  @override
  OverlayLayerKind get kind => OverlayLayerKind.emoji;

  @override
  EmojiLayer copy() => EmojiLayer(
        id: id,
        transform: transform.copyWith(),
        visible: visible,
        glyph: glyph,
        fontSize: fontSize,
        cachedPixels: cachedPixels != null ? Uint8List.fromList(cachedPixels!) : null,
        cachedWidth: cachedWidth,
        cachedHeight: cachedHeight,
      );
}

class StickerLayer extends OverlayLayer {
  StickerLayer({
    required super.id,
    required super.transform,
    super.visible,
    this.assetKey,
    this.userBytes,
    this.userSourceWidth = 0,
    this.userSourceHeight = 0,
    this.shapeMask = StickerShapeMask.none,
    this.maskCornerRadius = 16,
    super.cachedPixels,
    super.cachedWidth,
    super.cachedHeight,
  });

  final String? assetKey;
  final Uint8List? userBytes;

  /// Decoded pixel size of [userBytes]; used for on-canvas layout (not cleared on cache invalidation).
  int userSourceWidth;
  int userSourceHeight;

  StickerShapeMask shapeMask;
  double maskCornerRadius;

  @override
  OverlayLayerKind get kind => OverlayLayerKind.sticker;

  @override
  StickerLayer copy() => StickerLayer(
        id: id,
        transform: transform.copyWith(),
        visible: visible,
        assetKey: assetKey,
        userBytes: userBytes != null ? Uint8List.fromList(userBytes!) : null,
        userSourceWidth: userSourceWidth,
        userSourceHeight: userSourceHeight,
        shapeMask: shapeMask,
        maskCornerRadius: maskCornerRadius,
        cachedPixels: cachedPixels != null ? Uint8List.fromList(cachedPixels!) : null,
        cachedWidth: cachedWidth,
        cachedHeight: cachedHeight,
      );
}

class TextLayer extends OverlayLayer {
  TextLayer({
    required super.id,
    required super.transform,
    super.visible,
    required this.text,
    this.fontSize = 32,
    this.color = Colors.white,
    this.fillMode = TextFillMode.solid,
    this.gradientEnd = const Color(0xFFFF4081),
    this.gradientAngleDeg = 0,
    this.fontWeight = FontWeight.w600,
    this.fontStyle = FontStyle.normal,
    this.fontFamily,
    this.backgroundStyle = TextBackgroundStyle.rounded,
    this.backgroundColor = const Color(0xE6000000),
    this.padding = 12,
    this.cornerRadius = 16,
    super.cachedPixels,
    super.cachedWidth,
    super.cachedHeight,
  });

  final String text;
  final double fontSize;
  final Color color;
  final TextFillMode fillMode;
  final Color gradientEnd;
  final double gradientAngleDeg;
  final FontWeight fontWeight;
  final FontStyle fontStyle;
  final String? fontFamily;
  final TextBackgroundStyle backgroundStyle;
  final Color backgroundColor;
  final double padding;
  final double cornerRadius;

  @override
  OverlayLayerKind get kind => OverlayLayerKind.text;

  @override
  TextLayer copy() => TextLayer(
        id: id,
        transform: transform.copyWith(),
        visible: visible,
        text: text,
        fontSize: fontSize,
        color: color,
        fillMode: fillMode,
        gradientEnd: gradientEnd,
        gradientAngleDeg: gradientAngleDeg,
        fontWeight: fontWeight,
        fontStyle: fontStyle,
        fontFamily: fontFamily,
        backgroundStyle: backgroundStyle,
        backgroundColor: backgroundColor,
        padding: padding,
        cornerRadius: cornerRadius,
        cachedPixels: cachedPixels != null ? Uint8List.fromList(cachedPixels!) : null,
        cachedWidth: cachedWidth,
        cachedHeight: cachedHeight,
      );
}

class ShapeLayer extends OverlayLayer {
  ShapeLayer({
    required super.id,
    required super.transform,
    super.visible,
    required this.shapeKind,
    this.width = 120,
    this.height = 80,
    this.strokeWidth = 4,
    this.filled = false,
    this.color = const Color(0xFF4EDEA3),
    super.cachedPixels,
    super.cachedWidth,
    super.cachedHeight,
  });

  final ShapeKind shapeKind;
  final double width;
  final double height;
  final double strokeWidth;
  final bool filled;
  final Color color;

  @override
  OverlayLayerKind get kind => OverlayLayerKind.shape;

  @override
  ShapeLayer copy() => ShapeLayer(
        id: id,
        transform: transform.copyWith(),
        visible: visible,
        shapeKind: shapeKind,
        width: width,
        height: height,
        strokeWidth: strokeWidth,
        filled: filled,
        color: color,
        cachedPixels: cachedPixels != null ? Uint8List.fromList(cachedPixels!) : null,
        cachedWidth: cachedWidth,
        cachedHeight: cachedHeight,
      );
}

class PaintStrokeLayer extends OverlayLayer {
  PaintStrokeLayer({
    required super.id,
    required super.transform,
    super.visible,
    required this.points,
    this.color = const Color(0xFF4EDEA3),
    this.width = 8,
    this.opacity = 1,
    this.brush = PaintBrushKind.pen,
    this.filled = false,
  }) : super(
          cachedPixels: null,
          cachedWidth: 0,
          cachedHeight: 0,
        );

  final List<Offset> points;
  final Color color;
  final double width;
  final double opacity;
  final PaintBrushKind brush;
  final bool filled;

  /// Prebuilt stack-space path for canvas paint (set at commit).
  Path? displayPath;

  @override
  OverlayLayerKind get kind => OverlayLayerKind.paintStroke;

  @override
  PaintStrokeLayer copy() => PaintStrokeLayer(
        id: id,
        transform: transform.copyWith(),
        visible: visible,
        points: List<Offset>.from(points),
        color: color,
        width: width,
        opacity: opacity,
        brush: brush,
        filled: filled,
      )..displayPath = displayPath;
}

/// Container for multiple layers moved/scaled/rotated as one unit (Sprint 17).
class GroupLayer extends OverlayLayer {
  GroupLayer({
    required super.id,
    required super.transform,
    super.visible,
    required List<OverlayLayer> children,
    super.cachedPixels,
    super.cachedWidth,
    super.cachedHeight,
  }) : children = List<OverlayLayer>.from(children);

  final List<OverlayLayer> children;

  @override
  OverlayLayerKind get kind => OverlayLayerKind.group;

  @override
  GroupLayer copy() => GroupLayer(
        id: id,
        transform: transform.copyWith(),
        visible: visible,
        children: children.map((c) => c.copy()).toList(),
        cachedPixels: cachedPixels != null ? Uint8List.fromList(cachedPixels!) : null,
        cachedWidth: cachedWidth,
        cachedHeight: cachedHeight,
      );
}

String newLayerId() => DateTime.now().microsecondsSinceEpoch.toString();

LayerTransform _offsetTransform(LayerTransform t, Offset offset) =>
    t.copyWith(
      centerX: t.centerX + offset.dx,
      centerY: t.centerY + offset.dy,
    );

/// Deep copy with a new id (Sprint 17 duplicate).
OverlayLayer cloneLayerWithNewId(
  OverlayLayer layer, {
  Offset offset = const Offset(12, 12),
}) {
  return switch (layer) {
    EmojiLayer l => EmojiLayer(
        id: newLayerId(),
        transform: _offsetTransform(l.transform, offset),
        visible: l.visible,
        glyph: l.glyph,
        fontSize: l.fontSize,
        cachedPixels: l.cachedPixels != null ? Uint8List.fromList(l.cachedPixels!) : null,
        cachedWidth: l.cachedWidth,
        cachedHeight: l.cachedHeight,
      ),
    StickerLayer l => StickerLayer(
        id: newLayerId(),
        transform: _offsetTransform(l.transform, offset),
        visible: l.visible,
        assetKey: l.assetKey,
        userBytes: l.userBytes != null ? Uint8List.fromList(l.userBytes!) : null,
        userSourceWidth: l.userSourceWidth,
        userSourceHeight: l.userSourceHeight,
        shapeMask: l.shapeMask,
        maskCornerRadius: l.maskCornerRadius,
        cachedPixels: l.cachedPixels != null ? Uint8List.fromList(l.cachedPixels!) : null,
        cachedWidth: l.cachedWidth,
        cachedHeight: l.cachedHeight,
      ),
    TextLayer l => TextLayer(
        id: newLayerId(),
        transform: _offsetTransform(l.transform, offset),
        visible: l.visible,
        text: l.text,
        fontSize: l.fontSize,
        color: l.color,
        fillMode: l.fillMode,
        gradientEnd: l.gradientEnd,
        gradientAngleDeg: l.gradientAngleDeg,
        fontWeight: l.fontWeight,
        fontStyle: l.fontStyle,
        fontFamily: l.fontFamily,
        backgroundStyle: l.backgroundStyle,
        backgroundColor: l.backgroundColor,
        padding: l.padding,
        cornerRadius: l.cornerRadius,
        cachedPixels: l.cachedPixels != null ? Uint8List.fromList(l.cachedPixels!) : null,
        cachedWidth: l.cachedWidth,
        cachedHeight: l.cachedHeight,
      ),
    ShapeLayer l => ShapeLayer(
        id: newLayerId(),
        transform: _offsetTransform(l.transform, offset),
        visible: l.visible,
        shapeKind: l.shapeKind,
        width: l.width,
        height: l.height,
        strokeWidth: l.strokeWidth,
        filled: l.filled,
        color: l.color,
        cachedPixels: l.cachedPixels != null ? Uint8List.fromList(l.cachedPixels!) : null,
        cachedWidth: l.cachedWidth,
        cachedHeight: l.cachedHeight,
      ),
    PaintStrokeLayer l => PaintStrokeLayer(
        id: newLayerId(),
        transform: _offsetTransform(l.transform, offset),
        visible: l.visible,
        points: l.points
            .map((p) => Offset(p.dx + offset.dx, p.dy + offset.dy))
            .toList(),
        color: l.color,
        width: l.width,
        opacity: l.opacity,
        brush: l.brush,
        filled: l.filled,
      ),
    GroupLayer l => GroupLayer(
        id: newLayerId(),
        transform: _offsetTransform(l.transform, offset),
        visible: l.visible,
        children: l.children
            .map((c) => cloneLayerWithNewId(c, offset: Offset.zero))
            .toList(),
        cachedPixels: l.cachedPixels != null ? Uint8List.fromList(l.cachedPixels!) : null,
        cachedWidth: l.cachedWidth,
        cachedHeight: l.cachedHeight,
      ),
    _ => throw UnsupportedError(
        'cloneLayerWithNewId: ${layer.runtimeType}',
      ),
  };
}
