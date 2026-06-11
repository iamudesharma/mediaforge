import 'package:flutter/material.dart';

import '../panels/tool_panels.dart';
import '../theme/editor_icons.dart';
import '../theme/editor_motion.dart';
import '../theme/lumina_tokens.dart';
import 'frosted_bar.dart';

/// A categorized tool rail for the desktop layout, implemented as a custom
/// scrollable [Column] with section headers. Each section has a 11-pt caps
/// label (Edit / Decorate / Manage), a vertical list of [ToolButton]-style
/// tiles, and a subtle separator between sections.
class CategorizedToolRail extends StatelessWidget {
  const CategorizedToolRail({
    super.key,
    required this.tools,
    required this.selectedTool,
    required this.onSelected,
    required this.sections,
  });

  final List<EditorTool> tools;
  final EditorTool selectedTool;
  final ValueChanged<EditorTool> onSelected;

  /// Ordered list of section definitions. Each section groups the tools
  /// whose [section] tag matches.
  final List<ToolSection> sections;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      child: FrostedBar(
        color: LuminaTokens.surfaceContainerLow.withValues(alpha: 0.7),
        borderBottom: true,
        padding: const EdgeInsets.symmetric(vertical: LuminaTokens.space2),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: LuminaTokens.space2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var s = 0; s < sections.length; s++) ...[
                if (s > 0)
                  const Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: LuminaTokens.space3,
                      vertical: LuminaTokens.space2,
                    ),
                    child: Divider(height: 1, thickness: 1),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    LuminaTokens.space4,
                    LuminaTokens.space2,
                    LuminaTokens.space4,
                    LuminaTokens.space1,
                  ),
                  child: Text(
                    sections[s].title.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.6,
                      color: LuminaTokens.onSurfaceMuted,
                    ),
                  ),
                ),
                for (final tool in sections[s].tools)
                  _RailTile(
                    tool: tool,
                    selected: tool == selectedTool,
                    onTap: () => onSelected(tool),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RailTile extends StatelessWidget {
  const _RailTile({
    required this.tool,
    required this.selected,
    required this.onTap,
  });

  final EditorTool tool;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final filled = EditorIcons.filled(tool);
    final outlined = EditorIcons.outlined(tool);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: LuminaTokens.space2,
        vertical: 2,
      ),
      child: Material(
        color: selected
            ? LuminaTokens.accentContainer
            : Colors.transparent,
        borderRadius: BorderRadius.circular(LuminaTokens.radiusMd),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(LuminaTokens.radiusMd),
          child: AnimatedContainer(
            duration: EditorMotion.fast,
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: LuminaTokens.space3),
            child: Row(
              children: [
                AnimatedSwitcher(
                  duration: EditorMotion.fast,
                  child: Icon(
                    selected ? filled : outlined,
                    key: ValueKey(selected),
                    size: 20,
                    color: selected
                        ? LuminaTokens.onAccentContainer
                        : LuminaTokens.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: LuminaTokens.space3),
                Expanded(
                  child: Text(
                    tool.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: selected
                          ? LuminaTokens.onAccentContainer
                          : LuminaTokens.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ToolSection {
  const ToolSection(this.title, this.tools);

  final String title;
  final List<EditorTool> tools;
}

/// Default tool categorization for the desktop rail.
List<ToolSection> defaultToolSections(List<EditorTool> enabled) {
  final byTag = <_Tag, List<EditorTool>>{};

  for (final tool in enabled) {
    if (tool == EditorTool.export_) continue; // export lives in the top bar
    byTag.putIfAbsent(_tagOf(tool), () => []).add(tool);
  }

  return [
    ToolSection('Edit', byTag[_Tag.edit] ?? const []),
    ToolSection('Decorate', byTag[_Tag.decorate] ?? const []),
    ToolSection('Manage', byTag[_Tag.manage] ?? const []),
  ];
}

enum _Tag { edit, decorate, manage }

_Tag _tagOf(EditorTool tool) {
  switch (tool) {
    case EditorTool.import:
    case EditorTool.transform:
    case EditorTool.adjust:
    case EditorTool.filters:
    case EditorTool.export_:
      return _Tag.edit;
    case EditorTool.stickers:
    case EditorTool.paint:
    case EditorTool.beauty:
    case EditorTool.draw:
      return _Tag.decorate;
    case EditorTool.layers:
    case EditorTool.overlay:
    case EditorTool.advanced:
      return _Tag.manage;
  }
}
