import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'video_text_overlay_style.dart';

/// Builds a [TextStyle] for [VideoTextOverlayContent] (image-editor compatible).
TextStyle videoTextPaintStyle(
  VideoTextOverlayStyle style, {
  required double layoutWidth,
  required double layoutHeight,
}) {
  final base = TextStyle(
    fontSize: style.fontSize,
    fontWeight: style.fontWeight,
    fontStyle: style.fontStyle,
    fontFamily: style.fontFamily,
    shadows: const [],
  );

  if (style.fillMode == VideoTextFillMode.solid) {
    return base.copyWith(color: style.color);
  }

  final rect = Rect.fromLTWH(0, 0, layoutWidth, layoutHeight);
  final rad = style.gradientAngleDeg * math.pi / 180;
  final gradient = LinearGradient(
    colors: [style.color, style.gradientEnd],
    transform: GradientRotation(rad),
  );

  return base.copyWith(
    foreground: Paint()..shader = gradient.createShader(rect),
  );
}

/// Renders a styled caption for the video compositor.
class VideoTextOverlayContent extends StatelessWidget {
  const VideoTextOverlayContent({
    super.key,
    required this.spec,
  });

  final VideoTextOverlaySpec spec;

  @override
  Widget build(BuildContext context) {
    final style = spec.style;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: style.maxWidth),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.center,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final lw = constraints.maxWidth.isFinite && constraints.maxWidth > 0
                ? constraints.maxWidth
                : style.maxWidth;
            final lh = constraints.maxHeight.isFinite && constraints.maxHeight > 0
                ? constraints.maxHeight
                : style.fontSize * 2;
            return Container(
              padding: EdgeInsets.all(style.padding),
              decoration: style.backgroundStyle == VideoTextBackgroundStyle.none
                  ? null
                  : BoxDecoration(
                      color: style.backgroundColor,
                      borderRadius: style.backgroundStyle ==
                              VideoTextBackgroundStyle.rounded
                          ? BorderRadius.circular(style.cornerRadius)
                          : BorderRadius.zero,
                    ),
              child: Text(
                spec.label,
                textAlign: TextAlign.center,
                style: videoTextPaintStyle(
                  style,
                  layoutWidth: lw,
                  layoutHeight: lh,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
