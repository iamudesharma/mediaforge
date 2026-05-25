import 'package:flutter/animation.dart';

/// Shared motion tokens for the rust_image editor UI.
abstract final class EditorMotion {
  static const fast = Duration(milliseconds: 180);
  static const medium = Duration(milliseconds: 320);
  static const slow = Duration(milliseconds: 480);

  static const standard = Curves.easeOutCubic;
  static const enter = Curves.easeOutCubic;
  static const exit = Curves.easeInCubic;
  static const spring = Curves.easeOutBack;
}
