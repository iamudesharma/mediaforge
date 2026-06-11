import 'package:flutter/material.dart';

import '../theme/editor_motion.dart';
import '../theme/lumina_tokens.dart';

/// Rounded 32-px pill chip with accent background when selected and
/// translucent surface when not. Replaces the older [ActionChipRow] and
/// [ChoiceChip] usages with a single consistent visual.
class ChipPill extends StatelessWidget {
  const ChipPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.enabled = true,
    this.dense = false,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool enabled;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final bg = selected
        ? LuminaTokens.accentContainer
        : LuminaTokens.surfaceContainerHigh.withValues(alpha: 0.7);
    final borderColor = selected
        ? LuminaTokens.accent.withValues(alpha: 0.4)
        : LuminaTokens.outlineVariant;
    final fg = selected
        ? LuminaTokens.onAccentContainer
        : (enabled ? LuminaTokens.onSurface : LuminaTokens.onSurfaceMuted);

    final paddingH = dense ? LuminaTokens.space3 : LuminaTokens.space4;
    final height = dense ? 28.0 : LuminaTokens.chipHeight;

    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(LuminaTokens.radiusLg),
          child: AnimatedContainer(
            duration: EditorMotion.fast,
            curve: EditorMotion.standard,
            height: height,
            padding: EdgeInsets.symmetric(horizontal: paddingH),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(LuminaTokens.radiusLg),
              border: Border.all(
                color: borderColor,
                width: selected ? 1.0 : 0.8,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 14, color: fg),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: fg,
                    height: 1.0,
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

/// Horizontal scrolling row of [ChipPill]s with single-select.
class ChipPillRow<T> extends StatelessWidget {
  const ChipPillRow({
    super.key,
    required this.items,
    required this.label,
    required this.selected,
    required this.onSelected,
    this.icon,
    this.dense = false,
  });

  final List<T> items;
  final String Function(T) label;
  final IconData? Function(T)? icon;
  final T selected;
  final ValueChanged<T>? onSelected;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: dense ? 36 : LuminaTokens.chipHeight + 4,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        physics: const ClampingScrollPhysics(),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: LuminaTokens.space2),
        itemBuilder: (context, i) {
          final item = items[i];
          return ChipPill(
            label: label(item),
            selected: item == selected,
            onTap: onSelected == null ? null : () => onSelected!(item),
            icon: icon?.call(item),
            dense: dense,
          );
        },
      ),
    );
  }
}

/// Wrap-based row of [ChipPill]s for short lists.
class ChipPillWrap<T> extends StatelessWidget {
  const ChipPillWrap({
    super.key,
    required this.items,
    required this.label,
    required this.selected,
    required this.onSelected,
    this.icon,
    this.dense = false,
  });

  final List<T> items;
  final String Function(T) label;
  final IconData? Function(T)? icon;
  final T selected;
  final ValueChanged<T>? onSelected;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: LuminaTokens.space2,
      runSpacing: LuminaTokens.space2,
      children: [
        for (final item in items)
          ChipPill(
            label: label(item),
            selected: item == selected,
            onTap: onSelected == null ? null : () => onSelected!(item),
            icon: icon?.call(item),
            dense: dense,
          ),
      ],
    );
  }
}
