import 'package:flutter/material.dart';

/// Lumina Edit design tokens (Electric Mint + deep charcoal surfaces).
///
/// Palette from `lumina_edit/DESIGN.md`. Dark-only chrome so video content
/// stays the hero. Primary actions use Electric Mint; creative/timeline
/// accents may use secondary purple.
abstract final class LuminaTokens {
  // --- Surfaces (DESIGN.md Material scale) ---

  static const canvas = Color(0xFF111317);
  static const background = Color(0xFF111317);
  static const surface = Color(0xFF1E2024);
  static const surfaceDim = Color(0xFF111317);
  static const surfaceBright = Color(0xFF37393E);
  static const surfaceContainerLowest = Color(0xFF0C0E12);
  static const surfaceContainerLow = Color(0xFF1A1C20);
  static const surfaceContainer = Color(0xFF1E2024);
  static const surfaceContainerHigh = Color(0xFF282A2E);
  static const surfaceContainerHighest = Color(0xFF333539);
  static const surfaceVariant = Color(0xFF333539);

  static const onSurface = Color(0xFFE2E2E8);
  static const onSurfaceVariant = Color(0xFFBACBBC);
  static const onSurfaceMuted = Color(0xFF849587);

  static const outline = Color(0xFF849587);
  static const outlineVariant = Color(0xFF3B4A3F);

  // --- Primary (Electric Mint) ---

  static const primary = Color(0xFFD0FFDC);
  static const onPrimary = Color(0xFF00391E);
  static const primaryContainer = Color(0xFF2AF598);
  static const onPrimaryContainer = Color(0xFF006C3F);
  static const primaryFixed = Color(0xFF57FFA6);
  static const primaryFixedDim = Color(0xFF00E38A);
  static const onPrimaryFixed = Color(0xFF002110);

  /// Main interactive accent — Electric Mint.
  static const accent = primaryFixedDim;
  static const onAccent = onPrimaryFixed;
  static const accentContainer = Color(0xFF00522E);
  static const onAccentContainer = primaryFixed;
  static const accentSurface = Color(0xFF143B2F);

  // --- Secondary (Neon Purple — audio / creative tracks) ---

  static const secondary = Color(0xFFEDB1FF);
  static const onSecondary = Color(0xFF520070);
  static const secondaryContainer = Color(0xFF6E208C);
  static const onSecondaryContainer = Color(0xFFE498FF);

  // --- Tertiary (warm highlights) ---

  static const tertiary = Color(0xFFFFF2DE);
  static const tertiaryContainer = Color(0xFFFFD16D);

  // --- Semantic ---

  static const error = Color(0xFFFFB4AB);
  static const onError = Color(0xFF690005);
  static const success = primaryFixedDim;

  // --- Glassmorphism ---

  static const glassFill = Color(0xB30F1115);
  static const glassBorder = Color(0x0DFFFFFF);
  static const selectionGlow = Color(0x3300E38A);

  // --- Geometry (DESIGN.md: 8px buttons, 16px panels, 4px clips) ---

  static const radiusXs = 4.0;
  static const radiusSm = 8.0;
  static const radiusMd = 12.0;
  static const radiusLg = 16.0;
  static const radiusXl = 24.0;
  static const radius2xl = 28.0;

  // --- Spacing (4 pt base) ---

  static const space0 = 0.0;
  static const space1 = 4.0;
  static const space2 = 8.0;
  static const space3 = 12.0;
  static const space4 = 16.0;
  static const space5 = 20.0;
  static const space6 = 24.0;
  static const space7 = 32.0;
  static const space8 = 48.0;

  static const padXs = space1;
  static const padSm = space2;
  static const padMd = space4;
  static const gutterTool = space3;
  static const gutterWorkspace = 2.0;

  // --- Component sizes ---

  static const chipHeight = 32.0;
  static const controlHeight = 40.0;
  static const fabSize = 56.0;
  static const touchTarget = 44.0;
  static const bottomNavHeight = 56.0;

  static const desktopInspectorWidth = 320.0;
  static const desktopInspectorMinWidth = 280.0;
  static const desktopInspectorMaxWidth = 480.0;

  // --- Breakpoints ---

  static const breakpointPhone = 600.0;
  static const breakpointTablet = 900.0;
  static const breakpointDesktop = 1100.0;
  static const breakpointLarge = 1440.0;

  // --- Sheet / overlay ---

  static const sheetPeekChildSize = 0.38;
  static const sheetExpandedChildSize = 0.72;
  static const sheetMaxChildSize = 1.0;
  static const sheetGrabberWidth = 36.0;
  static const sheetGrabberHeight = 4.0;
  static const mobileTopBarHeight = 52.0;
  static const mobileBottomBarHeight = 64.0;
  static const sheetBlurSigma = 20.0;
  static const timelineHeightMin = 240.0;

  // --- Icons ---

  static const iconSizeInline = 20.0;
  static const iconSizeRow = 24.0;
  static const iconSizePrimary = 28.0;

  // --- Sliders ---

  static const sliderTrackHeight = 4.0;
  static const sliderThumbRadius = 10.0;
  static const sliderValueBubbleWidth = 56.0;
  static const sliderValueBubbleHeight = 26.0;
}
