import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'video_text_overlay_style.dart';
import 'video_text_presets.dart';

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
    letterSpacing: style.letterSpacing,
    shadows: style.useThreeD
        ? const [
            Shadow(color: Color(0xFF1A237E), offset: Offset(3, 3), blurRadius: 0),
            Shadow(color: Color(0x88000000), offset: Offset(6, 6), blurRadius: 2),
          ]
        : style.lookPreset == VideoTextLookPreset.neon
            ? [
                Shadow(
                  color: style.color.withValues(alpha: style.glowIntensity),
                  blurRadius: 8 + 16 * style.glowIntensity,
                ),
                Shadow(
                  color: style.color.withValues(alpha: 0.35 * style.glowIntensity),
                  blurRadius: 20 + 12 * style.glowIntensity,
                ),
              ]
            : const [],
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
            final showBox = style.showBackground &&
                style.backgroundStyle != VideoTextBackgroundStyle.none;
            return Container(
              padding: EdgeInsets.all(style.padding),
              decoration: showBox
                  ? BoxDecoration(
                      color: style.backgroundColor,
                      borderRadius: style.backgroundStyle ==
                              VideoTextBackgroundStyle.rounded
                          ? BorderRadius.circular(style.cornerRadius)
                          : BorderRadius.zero,
                    )
                  : null,
              child: Transform(
                alignment: Alignment.center,
                transform: style.useThreeD
                    ? (Matrix4.identity()
                      ..setEntry(3, 2, 0.001)
                      ..rotateX(-0.12)
                      ..rotateY(0.08))
                    : Matrix4.identity(),
                child: Text(
                  spec.label,
                  textAlign: style.textAlign,
                  style: videoTextPaintStyle(
                    style,
                    layoutWidth: lw,
                    layoutHeight: lh,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
