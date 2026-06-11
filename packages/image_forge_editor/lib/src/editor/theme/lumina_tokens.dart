import 'package:flutter/material.dart';

/// Lumina Darkroom design tokens (Phase 0 of the modernization pass).
///
/// All surface, text, and accent colors are dark-only. The editor chrome is
/// designed to live on top of user photos, where dark surfaces let the photo
/// be the hero. The palette is collapsed to a single mint accent
/// (`#4EDEA3` + containers) with no second accent.
abstract final class LuminaTokens {
  // --- Surfaces (Material 3 surfaceContainer scale, tightened for chrome) ---

  /// Page background (canvas, wide layout scaffold).
  static const canvas = Color(0xFF020617);

  /// App/wide scaffold background.
  static const background = Color(0xFF0B0F1F);

  /// Panel surface base.
  static const surface = Color(0xFF0C1324);
  static const surfaceContainerLowest = Color(0xFF070D1F);
  static const surfaceContainerLow = Color(0xFF121829);
  static const surfaceContainer = Color(0xFF181F33);
  static const surfaceContainerHigh = Color(0xFF20283F);
  static const surfaceContainerHighest = Color(0xFF29314B);
  static const surfaceVariant = Color(0xFF29314B);

  /// Foreground colors on dark surface.
  static const onSurface = Color(0xFFE3E8FF);
  static const onSurfaceVariant = Color(0xFFB2BAD1);
  static const onSurfaceMuted = Color(0xFF7E869E);

  /// Outline / dividers.
  static const outline = Color(0xFF8694B8);
  static const outlineVariant = Color(0xFF2C3654);

  // --- Single mint accent ramp ---

  /// Primary accent — mint.
  static const accent = Color(0xFF4EDEA3);

  /// Legacy alias kept for back-compat with widgets written against
  /// [primary] (compare_hold_button, transformable_layer, etc.).
  static const primary = accent;

  /// Foreground on top of [accent] (dark green-black).
  static const onAccent = Color(0xFF003824);

  /// Legacy alias.
  static const onPrimary = onAccent;

  /// Filled container behind selected tool / pressed states.
  static const accentContainer = Color(0xFF1F6D52);
  static const onAccentContainer = Color(0xFFB6F4D8);

  /// Legacy alias.
  static const primaryContainer = accentContainer;

  /// Subtle accent surface (chips, hover).
  static const accentSurface = Color(0xFF143B2F);

  // --- Legacy secondary (now identical to primary — single-accent palette) ---

  static const secondary = accent;
  static const secondaryContainer = accentContainer;

  // --- Semantic ---

  static const error = Color(0xFFFFB4AB);
  static const success = Color(0xFF6EE7B7);

  // --- Geometry ---

  static const radiusXs = 4.0;
  static const radiusSm = 6.0;
  static const radiusMd = 10.0;
  static const radiusLg = 14.0;
  static const radiusXl = 20.0;
  static const radius2xl = 28.0;

  // --- Spacing scale (4 pt base) ---

  static const space0 = 0.0;
  static const space1 = 4.0;
  static const space2 = 8.0;
  static const space3 = 12.0;
  static const space4 = 16.0;
  static const space5 = 20.0;
  static const space6 = 24.0;
  static const space7 = 32.0;
  static const space8 = 48.0;

  /// Backwards-compatible aliases (some panels still read these names).
  static const padXs = space1;
  static const padSm = space2;
  static const padMd = space4;
  static const gutterTool = space3;

  // --- Component sizes ---

  static const chipHeight = 32.0;
  static const controlHeight = 40.0;
  static const fabSize = 56.0;
  static const touchTarget = 44.0;

  /// Width of the desktop/macOS properties inspector panel.
  static const desktopInspectorWidth = 360.0;
  static const desktopInspectorMinWidth = 280.0;
  static const desktopInspectorMaxWidth = 480.0;

  // --- Breakpoints (single source of truth) ---

  /// Form factor breakpoints (logical pixels).
  static const breakpointPhone = 600.0;
  static const breakpointTablet = 900.0;
  static const breakpointDesktop = 1100.0;
  static const breakpointLarge = 1440.0;

  // --- Sheet / overlay metrics ---

  static const sheetPeekChildSize = 0.38;
  static const sheetExpandedChildSize = 0.72;
  static const sheetMaxChildSize = 1.0;

  /// Drag handle width / height (sheet grabber).
  static const sheetGrabberWidth = 36.0;
  static const sheetGrabberHeight = 4.0;

  /// Top / bottom bar height on mobile.
  static const mobileTopBarHeight = 52.0;
  static const mobileBottomBarHeight = 64.0;

  static const sheetBlurSigma = 20.0;

  // --- Icons ---

  static const iconSizeInline = 20.0;
  static const iconSizeRow = 24.0;
  static const iconSizePrimary = 28.0;

  // --- Sliders ---

  static const sliderTrackHeight = 4.0;
  static const sliderThumbRadius = 11.0;
  static const sliderValueBubbleWidth = 56.0;
  static const sliderValueBubbleHeight = 26.0;
}
