import 'package:flutter/material.dart';

import '../panels/tool_panels.dart';
import 'lumina_tokens.dart';

/// Filled / outlined icon pair registry for each [EditorTool].
///
/// The selected state of every tool button swaps the [IconData] from the
/// `outlined` variant to the `filled` variant. The fill is rendered via
/// `Icon(icon, fill: 1.0)` for Material 3 variable-font icons, falling back
/// to the static `_filled` icon for icons that don't have a variable font.
class EditorIcons {
  EditorIcons._();

  static IconData filled(EditorTool tool) => _filled[tool] ?? tool.icon;

  static IconData outlined(EditorTool tool) => _outlined[tool] ?? tool.icon;

  static const Map<EditorTool, IconData> _filled = <EditorTool, IconData>{
    EditorTool.import: Icons.photo_library_rounded,
    EditorTool.transform: Icons.crop_rounded,
    EditorTool.filters: Icons.auto_awesome_rounded,
    EditorTool.beauty: Icons.face_retouching_natural_rounded,
    EditorTool.adjust: Icons.tune_rounded,
    EditorTool.paint: Icons.brush_rounded,
    EditorTool.stickers: Icons.emoji_emotions_rounded,
    EditorTool.export_: Icons.save_alt_rounded,
    EditorTool.draw: Icons.shape_line_rounded,
    EditorTool.layers: Icons.layers_rounded,
    EditorTool.overlay: Icons.image_rounded,
    EditorTool.advanced: Icons.equalizer_rounded,
  };

  static const Map<EditorTool, IconData> _outlined = <EditorTool, IconData>{
    EditorTool.import: Icons.photo_library_outlined,
    EditorTool.transform: Icons.crop_outlined,
    EditorTool.filters: Icons.auto_awesome_outlined,
    EditorTool.beauty: Icons.face_retouching_natural_outlined,
    EditorTool.adjust: Icons.tune_outlined,
    EditorTool.paint: Icons.brush_outlined,
    EditorTool.stickers: Icons.emoji_emotions_outlined,
    EditorTool.export_: Icons.save_alt_outlined,
    EditorTool.draw: Icons.shape_line_outlined,
    EditorTool.layers: Icons.layers_outlined,
    EditorTool.overlay: Icons.image_outlined,
    EditorTool.advanced: Icons.equalizer_rounded,
  };

  /// Default accent tint for filled icons.
  static Color selectedColor(BuildContext context) => LuminaTokens.accent;

  /// Default muted tint for outlined icons.
  static Color unselectedColor(BuildContext context) =>
      LuminaTokens.onSurfaceVariant;
}
