import 'package:flutter/material.dart';

import 'layer_transform.dart';
import 'overlay_layer.dart';

/// Editable text appearance (UI + [TextLayer] mapping).
class TextStyleDraft {
  const TextStyleDraft({
    this.fillMode = TextFillMode.solid,
    this.color = Colors.white,
    this.gradientEnd = const Color(0xFFFF4081),
    this.gradientAngleDeg = 0,
    this.fontWeight = FontWeight.w600,
    this.fontStyle = FontStyle.normal,
    this.fontFamily,
    this.fontSize = 36,
  });

  final TextFillMode fillMode;
  final Color color;
  final Color gradientEnd;
  final double gradientAngleDeg;
  final FontWeight fontWeight;
  final FontStyle fontStyle;
  final String? fontFamily;
  final double fontSize;

  TextStyleDraft copyWith({
    TextFillMode? fillMode,
    Color? color,
    Color? gradientEnd,
    double? gradientAngleDeg,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    String? fontFamily,
    bool clearFontFamily = false,
    double? fontSize,
  }) {
    return TextStyleDraft(
      fillMode: fillMode ?? this.fillMode,
      color: color ?? this.color,
      gradientEnd: gradientEnd ?? this.gradientEnd,
      gradientAngleDeg: gradientAngleDeg ?? this.gradientAngleDeg,
      fontWeight: fontWeight ?? this.fontWeight,
      fontStyle: fontStyle ?? this.fontStyle,
      fontFamily: clearFontFamily ? null : (fontFamily ?? this.fontFamily),
      fontSize: fontSize ?? this.fontSize,
    );
  }

  factory TextStyleDraft.fromLayer(TextLayer layer) {
    return TextStyleDraft(
      fillMode: layer.fillMode,
      color: layer.color,
      gradientEnd: layer.gradientEnd,
      gradientAngleDeg: layer.gradientAngleDeg,
      fontWeight: layer.fontWeight,
      fontStyle: layer.fontStyle,
      fontFamily: layer.fontFamily,
      fontSize: layer.fontSize,
    );
  }

  TextLayer mergeInto(TextLayer base) {
    return TextLayer(
      id: base.id,
      transform: base.transform.copyWith(),
      visible: base.visible,
      text: base.text,
      fontSize: fontSize,
      color: color,
      fillMode: fillMode,
      gradientEnd: gradientEnd,
      gradientAngleDeg: gradientAngleDeg,
      fontWeight: fontWeight,
      fontStyle: fontStyle,
      fontFamily: fontFamily,
      backgroundStyle: base.backgroundStyle,
      backgroundColor: base.backgroundColor,
      padding: base.padding,
      cornerRadius: base.cornerRadius,
      cachedPixels: base.cachedPixels,
      cachedWidth: base.cachedWidth,
      cachedHeight: base.cachedHeight,
    );
  }

  TextLayer toLayer({
    required String id,
    required LayerTransform transform,
    required String text,
    TextBackgroundStyle backgroundStyle = TextBackgroundStyle.rounded,
    Color backgroundColor = const Color(0xE6000000),
    double padding = 12,
    double cornerRadius = 16,
    bool visible = true,
  }) {
    return TextLayer(
      id: id,
      transform: transform,
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
    );
  }
}
