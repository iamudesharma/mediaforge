import 'package:flutter/material.dart';

import 'lumina_tokens.dart';

/// Lumina typography (system fallbacks — no runtime network fetch).
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
      headlineLarge: _sans(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        height: 32 / 24,
        letterSpacing: -0.02 * 24,
        color: scheme.onSurface,
      ),
      headlineMedium: _sans(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        height: 24 / 18,
        color: scheme.onSurface,
      ),
      titleMedium: _sans(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        height: 22 / 16,
        color: scheme.onSurface,
      ),
      titleSmall: _sans(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      bodyLarge: _sans(fontSize: 16, height: 24 / 16, color: scheme.onSurface),
      bodyMedium: _sans(fontSize: 14, height: 20 / 14, color: scheme.onSurfaceVariant),
      bodySmall: _sans(fontSize: 12, color: scheme.onSurfaceVariant),
      labelLarge: _sans(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.1 * 11,
        color: scheme.onSurfaceVariant,
      ),
      labelMedium: TextStyle(
        fontFamily: _monoFamily,
        fontSize: 12,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.05 * 12,
        color: scheme.primary,
        shadows: _noShadow,
      ),
    );
  }

  static TextStyle brandTitle(BuildContext context) {
    return const TextStyle(
      fontFamily: _sansFamily,
      fontSize: 16,
      fontWeight: FontWeight.w700,
      letterSpacing: 2.4,
      color: LuminaTokens.onSurface,
      shadows: _noShadow,
    );
  }

  static TextStyle navLabel(BuildContext context, {required bool selected}) {
    return TextStyle(
      fontFamily: _sansFamily,
      fontSize: 10,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.4,
      shadows: _noShadow,
      color: selected ? LuminaTokens.primary : LuminaTokens.onSurfaceVariant,
    );
  }

  static TextStyle numericValue(BuildContext context) {
    return TextStyle(
      fontFamily: _monoFamily,
      fontSize: 12,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.6,
      shadows: _noShadow,
      color: Theme.of(context).colorScheme.primary,
    );
  }

  static TextStyle sectionCaps(BuildContext context) {
    return const TextStyle(
      fontFamily: _sansFamily,
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.1,
      color: LuminaTokens.onSurfaceVariant,
      shadows: _noShadow,
    );
  }
}
