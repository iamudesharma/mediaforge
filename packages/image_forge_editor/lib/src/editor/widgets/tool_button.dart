import 'package:flutter/material.dart';

import '../panels/tool_panels.dart';
import '../theme/editor_icons.dart';
import '../theme/editor_motion.dart';
import '../theme/lumina_tokens.dart';

/// 44×44 tool button with filled/outlined icon swap and 2-px accent
/// underline on the selected state. Used in the mobile bottom bar and
/// the desktop "More" grid.
class ToolButton extends StatelessWidget {
  const ToolButton({
    super.key,
    required this.tool,
    required this.selected,
    required this.onTap,
    this.showLabel = false,
    this.compact = false,
    this.tooltip,
    this.enabled = true,
  });

  final EditorTool tool;
  final bool selected;
  final VoidCallback onTap;
  final bool showLabel;
  final bool compact;

  /// Override the tooltip message (defaults to [EditorTool.mobileNavLabel]).
  final String? tooltip;

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final filled = EditorIcons.filled(tool);
    final outlined = EditorIcons.outlined(tool);
    final iconData = selected ? filled : outlined;
    final iconColor = selected
        ? LuminaTokens.accent
        : (enabled ? LuminaTokens.onSurfaceVariant : LuminaTokens.onSurfaceMuted);

    final size = compact ? 40.0 : 44.0;
    final iconSize = compact ? LuminaTokens.iconSizeInline : LuminaTokens.iconSizeRow;

    final child = SizedBox(
      width: size,
      height: size,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(LuminaTokens.radiusMd),
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedScale(
                scale: selected ? 1.06 : 1.0,
                duration: EditorMotion.fast,
                curve: EditorMotion.spring,
                child: Icon(iconData, size: iconSize, color: iconColor),
              ),
              if (selected)
                Positioned(
                  bottom: 2,
                  child: Container(
                    width: 16,
                    height: 2,
                    decoration: BoxDecoration(
                      color: LuminaTokens.accent,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    final t = Tooltip(
      message: tooltip ?? tool.mobileNavLabel,
      child: child,
    );

    if (showLabel) {
      return Tooltip(
        message: tooltip ?? tool.mobileNavLabel,
        child: SizedBox(
          width: 80,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              child,
              const SizedBox(height: 4),
              Text(
                tool.mobileNavLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected
                      ? LuminaTokens.accent
                      : LuminaTokens.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return t;
  }
}
