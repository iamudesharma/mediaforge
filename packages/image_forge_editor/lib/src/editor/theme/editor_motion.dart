import 'package:flutter/animation.dart';

/// Shared motion tokens for the Lumina Darkroom editor UI.
///
/// All curves follow the Material 3 / iOS 18 vocabulary:
///  - [fast] for icon swaps, slider value bubbles, chip selection.
///  - [medium] for tool panel cross-fade, page transitions, sheet slides.
///  - [slow] for hero transitions and large layout shifts.
abstract final class EditorMotion {
  static const fast = Duration(milliseconds: 150);
  static const medium = Duration(milliseconds: 250);
  static const slow = Duration(milliseconds: 400);

  static const sheetEnter = Duration(milliseconds: 320);

  /// Default easing — pairs [Curves.fastOutSlowIn] (M3 "standard easing").
  static const standard = Curves.fastOutSlowIn;

  /// Easing used when content enters (sheets, panel switches).
  static const enter = Curves.easeOutCubic;

  /// Easing used when content exits.
  static const exit = Curves.easeInCubic;

  /// Spring-like overshoot for icon scale taps.
  static const spring = Curves.easeOutBack;

  /// Tight 100 ms snap for slider value bubble visibility.
  static const snap = Duration(milliseconds: 100);
}
