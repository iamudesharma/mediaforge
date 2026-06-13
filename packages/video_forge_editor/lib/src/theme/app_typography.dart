import 'package:flutter/material.dart';

import 'lumina_tokens.dart';

/// Lumina typography — system fallbacks, no runtime network fetch.
///
/// Style philosophy:
///  - Sentence-case for buttons, panel headers, and tool titles
///    (iOS 18 / Apple Photos convention).
///  - All-caps 11 pt only for VSCO-style section labels in the inspector.
///  - Mono digits for live slider values, accent color so the eye tracks them.
///  - The active tool name is 17 pt w600 (iOS HIG "title 3").
abstract final class AppTypography {
  static const _sansFamily = '.AppleSystemUIFont';
  static const _monoFamily = 'Menlo';
  static const _noShadow = <Shadow>[];

  static void ensureConfigured() {}

  static TextStyle _sans({
    required double fontSize,
    FontWeight? fontWeight,
    double? height,
    double? letterSpacing,
    required Color color,
  }) {
    return TextStyle(
      fontFamily: _sansFamily,
      fontSize: fontSize,
      fontWeight: fontWeight,
      height: height,
      letterSpacing: letterSpacing,
      color: color,
      shadows: _noShadow,
    );
  }

  static TextTheme luminaTextTheme(ColorScheme scheme) {
    return TextTheme(
      displaySmall: _sans(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        height: 34 / 28,
        letterSpacing: -0.02 * 28,
        color: scheme.onSurface,
      ),
      headlineLarge: _sans(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        height: 28 / 22,
        color: scheme.onSurface,
      ),
      headlineMedium: _sans(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        height: 22 / 17,
        color: scheme.onSurface,
      ),
      titleLarge: _sans(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      titleMedium: _sans(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        height: 20 / 15,
        color: scheme.onSurface,
      ),
      titleSmall: _sans(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      bodyLarge: _sans(fontSize: 15, height: 22 / 15, color: scheme.onSurface),
      bodyMedium: _sans(fontSize: 14, height: 20 / 14, color: scheme.onSurfaceVariant),
      bodySmall: _sans(fontSize: 12, color: scheme.onSurfaceVariant),
      labelLarge: _sans(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      labelMedium: _sans(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
        color: scheme.onSurfaceVariant,
      ),
      labelSmall: _sans(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
        color: LuminaTokens.onSurfaceMuted,
      ),
    );
  }

  /// Active tool name (17 pt w600) — shown in the title bar and inspector header.
  static TextStyle toolName(BuildContext context) {
    return const TextStyle(
      fontFamily: _sansFamily,
      fontSize: 17,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.2,
      color: LuminaTokens.onSurface,
      shadows: _noShadow,
    );
  }

  /// Section label inside the inspector (11 pt caps, VSCO style).
  static TextStyle sectionCaps(BuildContext context) {
    return const TextStyle(
      fontFamily: _sansFamily,
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.4,
      color: LuminaTokens.onSurfaceVariant,
      shadows: _noShadow,
    );
  }

  /// Body label for chips and inline controls.
  static TextStyle navLabel(BuildContext context, {required bool selected}) {
    return TextStyle(
      fontFamily: _sansFamily,
      fontSize: 11,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.2,
      shadows: _noShadow,
      color: selected ? LuminaTokens.onAccent : LuminaTokens.onSurfaceVariant,
    );
  }

  /// Numeric value for slider bubbles (13 pt mono w500, accent color).
  static TextStyle sliderValueBubble(BuildContext context) {
    return const TextStyle(
      fontFamily: _monoFamily,
      fontSize: 12,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.3,
      color: LuminaTokens.onAccent,
      shadows: _noShadow,
    );
  }

  /// Legacy numeric value (right-column of LabeledSlider).
  static TextStyle numericValue(BuildContext context) {
    return const TextStyle(
      fontFamily: _monoFamily,
      fontSize: 12,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.4,
      color: LuminaTokens.accent,
      shadows: _noShadow,
    );
  }

  /// Legacy brand title (kept for back-compat).
  static TextStyle brandTitle(BuildContext context) {
    return const TextStyle(
      fontFamily: _sansFamily,
      fontSize: 15,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
      color: LuminaTokens.onSurface,
      shadows: _noShadow,
    );
  }
}
