import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_typography.dart';
import 'lumina_tokens.dart';

/// Dark theme for the Lumina Darkroom editor.
///
/// Single mint accent (LuminaTokens.accent). No light theme — the chrome is
/// always dark so user photos stay the hero of the layout.
abstract final class AppTheme {
  static ColorScheme _scheme() {
    return const ColorScheme.dark(
      brightness: Brightness.dark,
      primary: LuminaTokens.accent,
      onPrimary: LuminaTokens.onAccent,
      primaryContainer: LuminaTokens.accentContainer,
      onPrimaryContainer: LuminaTokens.onAccentContainer,
      secondary: LuminaTokens.accent,
      onSecondary: LuminaTokens.onAccent,
      secondaryContainer: LuminaTokens.accentContainer,
      onSecondaryContainer: LuminaTokens.onAccentContainer,
      tertiary: LuminaTokens.accent,
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
      onError: LuminaTokens.onAccent,
    );
  }

  static ThemeData dark() {
    AppTypography.ensureConfigured();
    final scheme = _scheme();
    final textTheme = AppTypography.luminaTextTheme(scheme);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: LuminaTokens.background,
      canvasColor: LuminaTokens.canvas,
      textTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
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
          borderRadius: BorderRadius.circular(LuminaTokens.radiusMd),
          side: const BorderSide(color: LuminaTokens.outlineVariant),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: LuminaTokens.surfaceContainerLow,
        indicatorColor: LuminaTokens.accentContainer,
        selectedIconTheme: const IconThemeData(
          color: LuminaTokens.onAccentContainer,
          size: 24,
        ),
        unselectedIconTheme: const IconThemeData(
          color: LuminaTokens.onSurfaceVariant,
          size: 24,
        ),
        selectedLabelTextStyle: const TextStyle(
          color: LuminaTokens.onAccentContainer,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelTextStyle: const TextStyle(
          color: LuminaTokens.onSurfaceVariant,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        labelType: NavigationRailLabelType.all,
        useIndicator: true,
        indicatorShape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(LuminaTokens.radiusMd)),
        ),
      ),
      // Back-compat: some legacy widgets read [primary] / [onPrimary] / etc.
      primaryIconTheme: const IconThemeData(color: LuminaTokens.onAccent),
      primaryTextTheme: const TextTheme(
        bodyLarge: TextStyle(color: LuminaTokens.onAccent),
        bodyMedium: TextStyle(color: LuminaTokens.onAccent),
        labelLarge: TextStyle(color: LuminaTokens.onAccent),
      ),
      chipTheme: ChipThemeData(
        elevation: 0,
        pressElevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LuminaTokens.radiusLg),
        ),
        side: const BorderSide(color: LuminaTokens.outlineVariant),
        selectedColor: LuminaTokens.accentContainer,
        checkmarkColor: LuminaTokens.onAccentContainer,
        labelStyle: textTheme.bodySmall!,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          // Avoid Size.fromHeight — it sets width to infinity and breaks buttons in Rows.
          minimumSize: const Size(0, LuminaTokens.controlHeight),
          padding: const EdgeInsets.symmetric(
            horizontal: LuminaTokens.space4,
            vertical: LuminaTokens.space2,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(LuminaTokens.radiusLg),
          ),
          elevation: 0,
          backgroundColor: LuminaTokens.accent,
          foregroundColor: LuminaTokens.onAccent,
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: LuminaTokens.onAccent,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, LuminaTokens.controlHeight),
          foregroundColor: LuminaTokens.onSurface,
          side: const BorderSide(color: LuminaTokens.outlineVariant),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(LuminaTokens.radiusLg),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: LuminaTokens.accent,
          padding: const EdgeInsets.symmetric(
            horizontal: LuminaTokens.space3,
            vertical: LuminaTokens.space2,
          ),
          minimumSize: const Size(0, LuminaTokens.controlHeight),
        ),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: LuminaTokens.sliderTrackHeight,
        thumbShape: const RoundSliderThumbShape(
          enabledThumbRadius: LuminaTokens.sliderThumbRadius,
        ),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
        activeTrackColor: LuminaTokens.accent,
        inactiveTrackColor: LuminaTokens.surfaceContainerHigh,
        thumbColor: Colors.white,
        overlayColor: LuminaTokens.accentSurface,
        valueIndicatorColor: LuminaTokens.accentContainer,
        valueIndicatorTextStyle: AppTypography.sliderValueBubble(
          // No context available here; theme builder doesn't have a BuildContext.
          // The bubble style is overridden in [ValueChipSlider] when needed.
          // ignore: deprecated_member_use
          _nullContext,
        ).copyWith(color: LuminaTokens.onAccentContainer),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: LuminaTokens.onSurface,
          minimumSize: const Size.square(LuminaTokens.touchTarget),
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
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: LuminaTokens.surfaceContainerHigh,
        contentTextStyle: textTheme.bodyMedium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LuminaTokens.radiusMd),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: LuminaTokens.surfaceContainer,
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: LuminaTokens.onSurfaceMuted,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: LuminaTokens.space3,
          vertical: LuminaTokens.space3,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(LuminaTokens.radiusMd),
          borderSide: const BorderSide(color: LuminaTokens.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(LuminaTokens.radiusMd),
          borderSide: const BorderSide(color: LuminaTokens.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(LuminaTokens.radiusMd),
          borderSide: const BorderSide(color: LuminaTokens.accent, width: 1.5),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: LuminaTokens.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(LuminaTokens.radiusSm),
          border: Border.all(color: LuminaTokens.outlineVariant),
        ),
        textStyle: textTheme.bodySmall?.copyWith(color: LuminaTokens.onSurface),
        waitDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  // Sentinel for slider theme (which doesn't have a BuildContext).
  // ignore: deprecated_member_use
  static final BuildContext _nullContext = _NullContext();
}

class _NullContext implements BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
