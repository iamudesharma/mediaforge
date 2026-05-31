import 'package:flutter/material.dart';

import '../panels/tool_panels.dart';
import '../theme/editor_motion.dart';
import '../theme/lumina_tokens.dart';

/// Scrollable sidebar tool list (replaces [NavigationRail] when many tools overflow).
class EditorToolRail extends StatelessWidget {
  const EditorToolRail({
    super.key,
    required this.tools,
    required this.selectedTool,
    required this.onSelected,
    required this.extended,
  });

  static const railKey = Key('editor_tool_rail');

  final List<EditorTool> tools;
  final EditorTool selectedTool;
  final ValueChanged<EditorTool> onSelected;
  final bool extended;

  @override
  Widget build(BuildContext context) {
    final railTheme = Theme.of(context).navigationRailTheme;
    final width = extended ? 200.0 : 80.0;
    final bg = railTheme.backgroundColor ?? LuminaTokens.surfaceContainerLow;

    return Material(
      key: railKey,
      color: bg,
      child: SizedBox(
        width: width,
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: LuminaTokens.padSm),
          itemCount: tools.length,
          itemBuilder: (context, i) {
            final tool = tools[i];
            final selected = tool == selectedTool;
            return _EditorToolRailTile(
              tool: tool,
              selected: selected,
              extended: extended,
              indicatorColor: railTheme.indicatorColor ??
                  LuminaTokens.primary.withValues(alpha: 0.15),
              onTap: () => onSelected(tool),
            );
          },
        ),
      ),
    );
  }
}

class _EditorToolRailTile extends StatelessWidget {
  const _EditorToolRailTile({
    required this.tool,
    required this.selected,
    required this.extended,
    required this.indicatorColor,
    required this.onTap,
  });

  final EditorTool tool;
  final bool selected;
  final bool extended;
  final Color indicatorColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final icon = _AnimatedRailIcon(icon: tool.icon, selected: selected);
    final content = extended
        ? Row(
            children: [
              const SizedBox(width: 12),
              icon,
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  tool.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected
                        ? LuminaTokens.primary
                        : LuminaTokens.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
          )
        : Tooltip(
            message: tool.label,
            child: Center(child: icon),
          );

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: LuminaTokens.padSm,
        vertical: 2,
      ),
      child: Material(
        color: selected ? indicatorColor : Colors.transparent,
        borderRadius: BorderRadius.circular(LuminaTokens.radiusMd),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(LuminaTokens.radiusMd),
          child: SizedBox(
            height: 56,
            child: content,
          ),
        ),
      ),
    );
  }
}

class _AnimatedRailIcon extends StatelessWidget {
  const _AnimatedRailIcon({required this.icon, required this.selected});

  final IconData icon;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: selected ? 1.12 : 1,
      duration: EditorMotion.fast,
      curve: EditorMotion.spring,
      child: Icon(icon),
    );
  }
}
