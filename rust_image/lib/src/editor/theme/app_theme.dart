import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'app_typography.dart';
import 'lumina_tokens.dart';

abstract final class AppTheme {
  static ColorScheme _scheme() {
    return const ColorScheme.dark(
      brightness: Brightness.dark,
      primary: LuminaTokens.primary,
      onPrimary: LuminaTokens.onPrimary,
      primaryContainer: LuminaTokens.primaryContainer,
      onPrimaryContainer: LuminaTokens.onPrimary,
      secondary: LuminaTokens.secondary,
      onSecondary: LuminaTokens.onPrimary,
      secondaryContainer: LuminaTokens.secondaryContainer,
      onSecondaryContainer: LuminaTokens.onSurface,
      tertiary: LuminaTokens.secondary,
      surface: LuminaTokens.surface,
      onSurface: LuminaTokens.onSurface,
      onSurfaceVariant: LuminaTokens.onSurfaceVariant,
      surfaceContainerHighest: LuminaTokens.surfaceContainerHighest,
      surfaceContainerHigh: LuminaTokens.surfaceContainerHigh,
      surfaceContainer: LuminaTokens.surfaceContainer,
      surfaceContainerLow: LuminaTokens.surfaceContainerLow,
      surfaceContainerLowest: LuminaTokens.surfaceContainerLowest,
      outline: LuminaTokens.outline,
      outlineVariant: LuminaTokens.outlineVariant,
      error: LuminaTokens.error,
      onError: LuminaTokens.onPrimary,
    );
  }

  static ThemeData dark() {
    AppTypography.ensureConfigured();
    final scheme = _scheme();
    final textTheme = AppTypography.luminaTextTheme(scheme);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: LuminaTokens.background,
      textTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
      cardTheme: CardThemeData(
        color: LuminaTokens.surfaceContainer,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LuminaTokens.radiusLg),
          side: const BorderSide(color: LuminaTokens.outlineVariant),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: LuminaTokens.surfaceContainerLow,
        indicatorColor: LuminaTokens.primary.withValues(alpha: 0.15),
        selectedIconTheme: const IconThemeData(color: LuminaTokens.primary, size: 26),
        unselectedIconTheme: const IconThemeData(
          color: LuminaTokens.onSurfaceVariant,
          size: 24,
        ),
        labelType: NavigationRailLabelType.all,
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LuminaTokens.radiusLg),
        ),
        side: const BorderSide(color: LuminaTokens.outlineVariant),
        selectedColor: LuminaTokens.primary.withValues(alpha: 0.2),
        checkmarkColor: LuminaTokens.primary,
        labelStyle: textTheme.bodySmall!,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(LuminaTokens.controlHeight),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(LuminaTokens.radiusLg),
          ),
          elevation: 0,
          backgroundColor: LuminaTokens.primary,
          foregroundColor: LuminaTokens.onPrimary,
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: 13,
            letterSpacing: 0.8,
            color: LuminaTokens.onPrimary,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(LuminaTokens.controlHeight),
          foregroundColor: LuminaTokens.onSurface,
          side: const BorderSide(color: LuminaTokens.outlineVariant),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(LuminaTokens.radiusLg),
          ),
        ),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 4,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
        activeTrackColor: LuminaTokens.primary,
        inactiveTrackColor: LuminaTokens.surfaceContainerHigh,
        thumbColor: Colors.white,
        overlayColor: LuminaTokens.primary.withValues(alpha: 0.12),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: LuminaTokens.onSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(LuminaTokens.radiusMd),
          ),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: LuminaTokens.onSurfaceVariant,
        textColor: LuminaTokens.onSurface,
      ),
      dividerTheme: const DividerThemeData(
        color: LuminaTokens.outlineVariant,
        thickness: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: LuminaTokens.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LuminaTokens.radiusMd),
        ),
      ),
    );
  }
}
