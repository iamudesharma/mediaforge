import 'package:flutter/material.dart';

/// Solid fill or linear gradient on text glyphs.
enum VideoTextFillMode { solid, gradient }

/// Background behind caption text.
enum VideoTextBackgroundStyle { none, solid, rounded }

/// Full text appearance for [VideoOverlayItem] captions (matches image editor text layers).
class VideoTextOverlayStyle {
  const VideoTextOverlayStyle({
    this.fillMode = VideoTextFillMode.solid,
    this.color = Colors.white,
    this.gradientEnd = const Color(0xFFFF4081),
    this.gradientAngleDeg = 0,
    this.fontWeight = FontWeight.w600,
    this.fontStyle = FontStyle.normal,
    this.fontFamily,
    this.fontSize = 32,
    this.backgroundStyle = VideoTextBackgroundStyle.rounded,
    this.backgroundColor = const Color(0xE6000000),
    this.padding = 12,
    this.cornerRadius = 16,
    this.maxWidth = 280,
  });

  final VideoTextFillMode fillMode;
  final Color color;
  final Color gradientEnd;
  final double gradientAngleDeg;
  final FontWeight fontWeight;
  final FontStyle fontStyle;
  final String? fontFamily;
  final double fontSize;
  final VideoTextBackgroundStyle backgroundStyle;
  final Color backgroundColor;
  final double padding;
  final double cornerRadius;
  final double maxWidth;

  static const defaults = VideoTextOverlayStyle();

  VideoTextOverlayStyle copyWith({
    VideoTextFillMode? fillMode,
    Color? color,
    Color? gradientEnd,
    double? gradientAngleDeg,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    String? fontFamily,
    bool clearFontFamily = false,
    double? fontSize,
    VideoTextBackgroundStyle? backgroundStyle,
    Color? backgroundColor,
    double? padding,
    double? cornerRadius,
    double? maxWidth,
  }) {
    return VideoTextOverlayStyle(
      fillMode: fillMode ?? this.fillMode,
      color: color ?? this.color,
      gradientEnd: gradientEnd ?? this.gradientEnd,
      gradientAngleDeg: gradientAngleDeg ?? this.gradientAngleDeg,
      fontWeight: fontWeight ?? this.fontWeight,
      fontStyle: fontStyle ?? this.fontStyle,
      fontFamily: clearFontFamily ? null : (fontFamily ?? this.fontFamily),
      fontSize: fontSize ?? this.fontSize,
      backgroundStyle: backgroundStyle ?? this.backgroundStyle,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      padding: padding ?? this.padding,
      cornerRadius: cornerRadius ?? this.cornerRadius,
      maxWidth: maxWidth ?? this.maxWidth,
    );
  }
}

/// Label + style for a timeline text overlay.
class VideoTextOverlaySpec {
  const VideoTextOverlaySpec({
    required this.label,
    this.style = VideoTextOverlayStyle.defaults,
  });

  final String label;
  final VideoTextOverlayStyle style;

  VideoTextOverlaySpec copyWith({
    String? label,
    VideoTextOverlayStyle? style,
  }) {
    return VideoTextOverlaySpec(
      label: label ?? this.label,
      style: style ?? this.style,
    );
  }
}
