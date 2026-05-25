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
}

enum TextBackgroundStyle { none, solid, rounded }

enum ShapeKind { rect, ellipse, line, arrow }

enum PaintBrushKind { pen, marker, highlighter, eraser }

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
    this.cachedPixels,
    this.cachedWidth = 0,
    this.cachedHeight = 0,
  });

  final String id;
  LayerTransform transform;

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
    required this.text,
    this.fontSize = 32,
    this.color = Colors.white,
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
        text: text,
        fontSize: fontSize,
        color: color,
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
    required this.points,
    this.color = const Color(0xFF4EDEA3),
    this.width = 8,
    this.opacity = 1,
    this.brush = PaintBrushKind.pen,
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

  /// Prebuilt stack-space path for canvas paint (set at commit).
  Path? displayPath;

  @override
  OverlayLayerKind get kind => OverlayLayerKind.paintStroke;

  @override
  PaintStrokeLayer copy() => PaintStrokeLayer(
        id: id,
        transform: transform.copyWith(),
        points: List<Offset>.from(points),
        color: color,
        width: width,
        opacity: opacity,
        brush: brush,
      )..displayPath = displayPath;
}

String newLayerId() => DateTime.now().microsecondsSinceEpoch.toString();
