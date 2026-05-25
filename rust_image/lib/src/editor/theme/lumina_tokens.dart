import 'package:flutter/material.dart';

/// Design tokens from Lumina Darkroom [DESIGN.md].
abstract final class LuminaTokens {
  static const canvas = Color(0xFF020617);
  static const background = Color(0xFF0C1324);
  static const surface = Color(0xFF0C1324);
  static const surfaceContainerLowest = Color(0xFF070D1F);
  static const surfaceContainerLow = Color(0xFF151B2D);
  static const surfaceContainer = Color(0xFF191F31);
  static const surfaceContainerHigh = Color(0xFF23293C);
  static const surfaceContainerHighest = Color(0xFF2E3447);
  static const surfaceVariant = Color(0xFF2E3447);
  static const onSurface = Color(0xFFDCE1FB);
  static const onSurfaceVariant = Color(0xFFBBCABF);
  static const outline = Color(0xFF86948A);
  static const outlineVariant = Color(0xFF3C4A42);
  static const primary = Color(0xFF4EDEA3);
  static const onPrimary = Color(0xFF003824);
  static const primaryContainer = Color(0xFF10B981);
  static const secondary = Color(0xFFBEC6E0);
  static const secondaryContainer = Color(0xFF3F465C);
  static const error = Color(0xFFFFB4AB);

  static const radiusSm = 4.0;
  static const radiusMd = 12.0;
  static const radiusLg = 16.0;
  static const radiusXl = 24.0;

  static const padXs = 4.0;
  static const padSm = 8.0;
  static const padMd = 16.0;
  static const gutterTool = 12.0;
  static const controlHeight = 48.0;

  /// Tool sheet max height as fraction of viewport (DESIGN.md: 40%).
  static const sheetMaxViewportFraction = 0.4;

  static const sheetBlurSigma = 20.0;
}
