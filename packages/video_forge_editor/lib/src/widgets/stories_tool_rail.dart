import 'package:flutter/material.dart';

import '../theme/lumina_tokens.dart';

enum StoriesTool { text, sticker, music, sound, more }

/// Instagram Stories–style vertical tool rail (right side, icon + label).
class StoriesToolRail extends StatelessWidget {
  const StoriesToolRail({
    super.key,
    required this.onToolSelected,
    this.soundMuted = false,
    this.hasMusic = false,
  });

  final ValueChanged<StoriesTool> onToolSelected;
  final bool soundMuted;
  final bool hasMusic;

  static const _tools = <StoriesTool, (IconData, String)>{
    StoriesTool.text: (Icons.title, 'Text'),
    StoriesTool.sticker: (Icons.emoji_emotions_outlined, 'Sticker'),
    StoriesTool.music: (Icons.music_note_outlined, 'Music'),
    StoriesTool.sound: (Icons.volume_up_outlined, 'Sound'),
    StoriesTool.more: (Icons.more_horiz, 'More'),
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final entry in _tools.entries)
          _RailItem(
            icon: entry.key == StoriesTool.sound && soundMuted
                ? Icons.volume_off_outlined
                : entry.key == StoriesTool.music && hasMusic
                    ? Icons.music_note
                    : entry.value.$1,
            label: entry.value.$2,
            highlighted: entry.key == StoriesTool.music && hasMusic,
            onTap: () => onToolSelected(entry.key),
          ),
      ],
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: LuminaTokens.space3),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(LuminaTokens.radiusLg),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: LuminaTokens.onSurface,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  shadows: const [
                    Shadow(
                      color: Colors.black54,
                      blurRadius: 4,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: LuminaTokens.space2),
              Container(
                width: LuminaTokens.touchTarget,
                height: LuminaTokens.touchTarget,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: highlighted
                      ? LuminaTokens.accentContainer.withValues(alpha: 0.85)
                      : Colors.black.withValues(alpha: 0.35),
                  border: Border.all(
                    color: highlighted
                        ? LuminaTokens.accent
                        : Colors.white.withValues(alpha: 0.2),
                    width: highlighted ? 1.5 : 1,
                  ),
                ),
                child: Icon(
                  icon,
                  color: highlighted ? LuminaTokens.accent : LuminaTokens.onSurface,
                  size: LuminaTokens.iconSizeRow,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
