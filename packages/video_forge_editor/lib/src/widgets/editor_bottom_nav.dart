import 'package:flutter/material.dart';

import '../theme/app_typography.dart';
import '../theme/lumina_tokens.dart';

/// Lumina Edit bottom navigation — Media, Text, Sticker, Music, More.
enum EditorNavTool { media, text, sticker, music, more }

class EditorBottomNav extends StatelessWidget {
  const EditorBottomNav({
    super.key,
    required this.active,
    required this.onChanged,
    this.hasMusic = false,
  });

  final EditorNavTool active;
  final ValueChanged<EditorNavTool> onChanged;
  final bool hasMusic;

  static const _items = <EditorNavTool, (IconData, IconData, String)>{
    EditorNavTool.media: (
      Icons.movie_filter_outlined,
      Icons.movie_filter,
      'Media',
    ),
    EditorNavTool.text: (
      Icons.title_outlined,
      Icons.title,
      'Text',
    ),
    EditorNavTool.sticker: (
      Icons.emoji_emotions_outlined,
      Icons.emoji_emotions,
      'Sticker',
    ),
    EditorNavTool.music: (
      Icons.music_note_outlined,
      Icons.music_note,
      'Music',
    ),
    EditorNavTool.more: (
      Icons.more_horiz,
      Icons.more_horiz,
      'More',
    ),
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: LuminaTokens.surfaceContainerLow.withValues(alpha: 0.95),
        border: const Border(
          top: BorderSide(color: LuminaTokens.glassBorder, width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: LuminaTokens.bottomNavHeight,
          child: Row(
            children: EditorNavTool.values.map((tool) {
              final selected = active == tool;
              final icons = _items[tool]!;
              final highlighted =
                  tool == EditorNavTool.music && hasMusic && !selected;
              return Expanded(
                child: _NavItem(
                  icon: selected || highlighted ? icons.$2 : icons.$1,
                  label: icons.$3,
                  selected: selected,
                  highlighted: highlighted,
                  onTap: () => onChanged(tool),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected || highlighted
        ? LuminaTokens.accent
        : LuminaTokens.onSurfaceVariant;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: LuminaTokens.iconSizeRow),
            const SizedBox(height: 2),
            Text(
              label,
              style: AppTypography.navLabel(context, selected: selected),
            ),
            const SizedBox(height: 4),
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: selected ? 20 : 0,
              height: 2,
              decoration: BoxDecoration(
                color: LuminaTokens.accent,
                borderRadius: BorderRadius.circular(1),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: LuminaTokens.selectionGlow,
                          blurRadius: 8,
                        ),
                      ]
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
