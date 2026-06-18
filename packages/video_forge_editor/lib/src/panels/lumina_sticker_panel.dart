import 'package:flutter/material.dart';

import '../theme/lumina_tokens.dart';
import '../widgets/lumina_style_card.dart';

/// Inline sticker picker for Lumina Edit bottom panel.
class LuminaStickerPanel extends StatefulWidget {
  const LuminaStickerPanel({
    super.key,
    required this.onEmojiSelected,
  });

  final ValueChanged<String> onEmojiSelected;

  static const _categories = <String, List<String>>{
    'Trending': ['✨', '🔥', '😂', '❤️', '👍', '🎉', '💯', '🙌', '😍', '🥳'],
    'Reaction': ['😎', '🤩', '😭', '🤔', '👀', '💀', '🙏', '👏'],
    'Shapes': ['⭐', '💫', '🔶', '🔷', '⭕', '❌', '✅', '➡️'],
    'Meme': ['🐱', '🐶', '🍕', '☕', '🎮', '📸', '🌙', '⚡'],
  };

  @override
  State<LuminaStickerPanel> createState() => _LuminaStickerPanelState();
}

class _LuminaStickerPanelState extends State<LuminaStickerPanel> {
  String _category = 'Trending';
  String _query = '';

  List<String> get _emojis {
    final all = <String>[];
    for (final list in LuminaStickerPanel._categories.values) {
      all.addAll(list);
    }
    final pool = LuminaStickerPanel._categories[_category] ?? all;
    if (_query.isEmpty) return pool;
    return pool.where((e) => e.contains(_query)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const LuminaPanelTitle('Stickers & Emojis'),
        TextField(
          style: const TextStyle(color: LuminaTokens.onSurface),
          decoration: InputDecoration(
            hintText: 'Search stickers & emojis',
            prefixIcon: const Icon(Icons.search, color: LuminaTokens.onSurfaceMuted),
            filled: true,
            fillColor: LuminaTokens.surfaceContainerHigh,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(LuminaTokens.radiusSm),
              borderSide: BorderSide.none,
            ),
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: LuminaTokens.space2),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: LuminaStickerPanel._categories.keys.map((cat) {
              final selected = _category == cat;
              return Padding(
                padding: const EdgeInsets.only(right: LuminaTokens.space2),
                child: FilterChip(
                  label: Text(cat),
                  selected: selected,
                  onSelected: (_) => setState(() => _category = cat),
                  selectedColor: LuminaTokens.accentContainer,
                  checkmarkColor: LuminaTokens.accent,
                  labelStyle: TextStyle(
                    color: selected
                        ? LuminaTokens.accent
                        : LuminaTokens.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                  backgroundColor: LuminaTokens.surfaceContainerHigh,
                  side: BorderSide(
                    color: selected
                        ? LuminaTokens.accent
                        : LuminaTokens.outlineVariant,
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: LuminaTokens.space3),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 6,
            mainAxisSpacing: LuminaTokens.space2,
            crossAxisSpacing: LuminaTokens.space2,
          ),
          itemCount: _emojis.length,
          itemBuilder: (context, i) {
            final emoji = _emojis[i];
            return Material(
              color: LuminaTokens.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(LuminaTokens.radiusXs),
              child: InkWell(
                borderRadius: BorderRadius.circular(LuminaTokens.radiusXs),
                onTap: () {
                  debugPrint('[StickerPanel] selected $emoji');
                  widget.onEmojiSelected(emoji);
                },
                child: Center(
                  child: Text(emoji, style: const TextStyle(fontSize: 28)),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
