import 'package:flutter/material.dart';

import '../theme/lumina_tokens.dart';

/// Square style preset card (Modern / Bold / Script / Neon).
class LuminaStyleCard extends StatelessWidget {
  const LuminaStyleCard({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.preview,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget? preview;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: LuminaTokens.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(LuminaTokens.radiusSm),
          border: Border.all(
            color: selected ? LuminaTokens.accent : LuminaTokens.outlineVariant,
            width: selected ? 1.5 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: LuminaTokens.selectionGlow,
                    blurRadius: 8,
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (preview != null)
              Expanded(child: Center(child: preview))
            else
              Text(
                label.substring(0, 1),
                style: TextStyle(
                  color: selected
                      ? LuminaTokens.accent
                      : LuminaTokens.onSurface,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(bottom: LuminaTokens.space1),
              child: Text(
                label,
                style: TextStyle(
                  color: selected
                      ? LuminaTokens.accent
                      : LuminaTokens.onSurfaceVariant,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Grid of accent color swatches.
class LuminaColorGrid extends StatelessWidget {
  const LuminaColorGrid({
    super.key,
    required this.colors,
    required this.selected,
    required this.onSelected,
    this.crossAxisCount = 7,
  });

  final List<Color> colors;
  final Color selected;
  final ValueChanged<Color> onSelected;
  final int crossAxisCount;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: LuminaTokens.space2,
        crossAxisSpacing: LuminaTokens.space2,
        childAspectRatio: 1,
      ),
      itemCount: colors.length,
      itemBuilder: (context, i) {
        final c = colors[i];
        final isSelected = c.value == selected.value;
        return GestureDetector(
          onTap: () => onSelected(c),
          child: Container(
            decoration: BoxDecoration(
              color: c,
              borderRadius: BorderRadius.circular(LuminaTokens.radiusXs),
              border: Border.all(
                color: isSelected
                    ? LuminaTokens.accent
                    : LuminaTokens.outlineVariant.withValues(alpha: 0.5),
                width: isSelected ? 2 : 1,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: LuminaTokens.selectionGlow,
                        blurRadius: 6,
                      ),
                    ]
                  : null,
            ),
          ),
        );
      },
    );
  }
}

/// Section title in Lumina panels (label-caps style).
class LuminaPanelTitle extends StatelessWidget {
  const LuminaPanelTitle(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: LuminaTokens.space3),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              color: LuminaTokens.onSurfaceVariant,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.66,
            ),
          ),
          if (trailing != null) ...[
            const Spacer(),
            trailing!,
          ],
        ],
      ),
    );
  }
}
