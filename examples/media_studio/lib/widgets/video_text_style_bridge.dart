import 'package:flutter/material.dart';
import 'package:video_forge_kit/video_forge_kit.dart';
import 'package:image_forge_editor/image_forge_editor.dart';

VideoTextOverlayStyle videoStyleFromDraft(
  TextStyleDraft draft, {
  required VideoTextBackgroundStyle backgroundStyle,
  required Color backgroundColor,
  required double padding,
  required double cornerRadius,
  required double maxWidth,
}) {
  return VideoTextOverlayStyle(
    fillMode: draft.fillMode == TextFillMode.gradient
        ? VideoTextFillMode.gradient
        : VideoTextFillMode.solid,
    color: draft.color,
    gradientEnd: draft.gradientEnd,
    gradientAngleDeg: draft.gradientAngleDeg,
    fontWeight: draft.fontWeight,
    fontStyle: draft.fontStyle,
    fontFamily: draft.fontFamily,
    fontSize: draft.fontSize,
    backgroundStyle: backgroundStyle,
    backgroundColor: backgroundColor,
    padding: padding,
    cornerRadius: cornerRadius,
    maxWidth: maxWidth,
  );
}

TextStyleDraft draftFromVideoStyle(VideoTextOverlayStyle style) {
  return TextStyleDraft(
    fillMode: style.fillMode == VideoTextFillMode.gradient
        ? TextFillMode.gradient
        : TextFillMode.solid,
    color: style.color,
    gradientEnd: style.gradientEnd,
    gradientAngleDeg: style.gradientAngleDeg,
    fontWeight: style.fontWeight,
    fontStyle: style.fontStyle,
    fontFamily: style.fontFamily,
    fontSize: style.fontSize,
  );
}

TextBackgroundStyle editorBackgroundStyle(VideoTextBackgroundStyle style) {
  return switch (style) {
    VideoTextBackgroundStyle.none => TextBackgroundStyle.none,
    VideoTextBackgroundStyle.solid => TextBackgroundStyle.solid,
    VideoTextBackgroundStyle.rounded => TextBackgroundStyle.rounded,
  };
}

VideoTextBackgroundStyle videoBackgroundStyle(TextBackgroundStyle style) {
  return switch (style) {
    TextBackgroundStyle.none => VideoTextBackgroundStyle.none,
    TextBackgroundStyle.solid => VideoTextBackgroundStyle.solid,
    TextBackgroundStyle.rounded => VideoTextBackgroundStyle.rounded,
  };
}
