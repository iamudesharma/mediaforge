import 'package:flutter/material.dart';

import '../theme/app_typography.dart';
import '../theme/editor_motion.dart';
import '../theme/lumina_tokens.dart';
import 'value_chip_slider.dart';

/// Header for a logical group of controls inside the inspector.
///
/// Uses VSCO-style 11 pt caps with 0.4 letter-spacing.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.subtitle, this.trailing});

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: LuminaTokens.space3,
        top: LuminaTokens.space4,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.toUpperCase(),
                  style: AppTypography.sectionCaps(context),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Legacy slider used by some panels (Paint, Beauty, Shapes, Overlay, etc.).
/// Internally uses the [ValueChipSlider] widget so all sliders feel uniform.
class LabeledSlider extends StatelessWidget {
  const LabeledSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.display,
    this.onChanged,
    this.onChangeEnd,
    this.onReset,
    this.resetValue = 0,
    this.bipolar = false,
    this.leading,
    this.trailing,
    this.enabled = true,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String display;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;
  final VoidCallback? onReset;
  final double resetValue;
  final bool bipolar;
  final Widget? leading;
  final Widget? trailing;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return ValueChipSlider(
      label: label,
      value: value,
      min: min,
      max: max,
      divisions: divisions,
      onChanged: onChanged,
      onChangeEnd: onChangeEnd,
      onReset: onReset,
      resetValue: resetValue,
      bipolar: bipolar,
      leading: leading,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            constraints: const BoxConstraints(minWidth: 56),
            alignment: Alignment.centerRight,
            child: Text(
              display,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.numericValue(context),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: LuminaTokens.space2),
            trailing!,
          ],
        ],
      ),
      enabled: enabled,
    );
  }
}

/// Horizontal wrapping of [ChipPill]s. Backwards-compatible shim around
/// [ChipPillWrap] from `chip_pill.dart` for the existing call sites.
class ActionChipRow<T> extends StatelessWidget {
  const ActionChipRow({
    super.key,
    required this.items,
    required this.label,
    required this.selected,
    required this.onSelected,
    this.horizontal = false,
    this.dense = false,
  });

  final List<T> items;
  final String Function(T) label;
  final T selected;
  final ValueChanged<T> onSelected;
  final bool horizontal;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    // Re-export to keep call sites compiling; the actual UI is in
    // [chip_pill.dart]. (Importing here would create a cycle; callers
    // should migrate to ChipPillRow / ChipPillWrap directly.)
    return _LegacyChipRow<T>(
      items: items,
      label: label,
      selected: selected,
      onSelected: onSelected,
      horizontal: horizontal,
      dense: dense,
    );
  }
}

class _LegacyChipRow<T> extends StatelessWidget {
  const _LegacyChipRow({
    required this.items,
    required this.label,
    required this.selected,
    required this.onSelected,
    required this.horizontal,
    required this.dense,
  });

  final List<T> items;
  final String Function(T) label;
  final T selected;
  final ValueChanged<T> onSelected;
  final bool horizontal;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    if (horizontal) {
      return SizedBox(
        height: 40,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          shrinkWrap: true,
          physics: const ClampingScrollPhysics(),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(width: LuminaTokens.space2),
          itemBuilder: (context, i) {
            final item = items[i];
            return _LuminaChip(
              label: label(item),
              selected: item == selected,
              onTap: () => onSelected(item),
            );
          },
        ),
      );
    }
    return Wrap(
      spacing: LuminaTokens.space2,
      runSpacing: LuminaTokens.space2,
      children: [
        for (final item in items)
          _LuminaChip(
            label: label(item),
            selected: item == selected,
            onTap: () => onSelected(item),
          ),
      ],
    );
  }
}

class _LuminaChip extends StatelessWidget {
  const _LuminaChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(LuminaTokens.radiusLg),
        child: AnimatedContainer(
          duration: EditorMotion.fast,
          curve: EditorMotion.spring,
          padding: const EdgeInsets.symmetric(
            horizontal: LuminaTokens.space4,
            vertical: LuminaTokens.space2,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(LuminaTokens.radiusLg),
            color: selected
                ? LuminaTokens.accentContainer
                : LuminaTokens.surfaceContainerHigh.withValues(alpha: 0.7),
            border: Border.all(
              color: selected
                  ? LuminaTokens.accent.withValues(alpha: 0.4)
                  : LuminaTokens.outlineVariant,
              width: selected ? 1.0 : 0.8,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              shadows: const [],
              color: selected
                  ? LuminaTokens.onAccentContainer
                  : LuminaTokens.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

/// Primary action button used at the bottom of inspector panels.
class PrimaryActionButton extends StatelessWidget {
  const PrimaryActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.enabled = true,
    this.secondary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool enabled;
  final bool secondary;

  @override
  Widget build(BuildContext context) {
    if (secondary) {
      return OutlinedButton.icon(
        onPressed: enabled ? onPressed : null,
        icon: Icon(icon, size: 18),
        label: Text(label),
      );
    }
    return FilledButton.icon(
      onPressed: enabled ? onPressed : null,
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}

/// Horizontal filter strip — now powered by a list of [Widget] thumbnails
/// (built upstream) rather than the static placeholder icon. Falls back
/// to a labelled placeholder if no thumbnail is provided for an index.
class LuminaFilterStrip extends StatelessWidget {
  const LuminaFilterStrip({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
    this.thumbnails,
    this.enabled = true,
    this.height = 72,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<Widget>? thumbnails;
  final bool enabled;
  final double height;

  @override
  Widget build(BuildContext context) {
    final cellWidth = height + 8.0;
    // Reserve: thumb (height) + 2 px gap + 14 px label line + 8 px vertical
    // padding inside the ListView + 1.6 px border = height + 25.6.
    final stripHeight = height + 26;
    return SizedBox(
      height: stripHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: labels.length,
        separatorBuilder: (_, _) => const SizedBox(width: LuminaTokens.space2),
        itemBuilder: (context, i) {
          final selected = i == selectedIndex;
          final thumb = (thumbnails != null && i < thumbnails!.length)
              ? thumbnails![i]
              : _PlaceholderThumb(label: labels[i]);
          return GestureDetector(
            onTap: enabled ? () => onSelected(i) : null,
            child: Container(
              width: cellWidth,
              height: stripHeight,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(LuminaTokens.radiusMd),
                border: Border.all(
                  color: selected
                      ? LuminaTokens.accent
                      : LuminaTokens.outlineVariant.withValues(alpha: 0.6),
                  width: selected ? 2.0 : 0.8,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(LuminaTokens.radiusSm),
                    ),
                    child: SizedBox(
                      width: cellWidth,
                      height: height,
                      child: thumb,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    labels[i],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
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
        },
      ),
    );
  }
}

class _PlaceholderThumb extends StatelessWidget {
  const _PlaceholderThumb({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            LuminaTokens.surfaceContainerHigh,
            LuminaTokens.surfaceContainer,
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.image_outlined,
          color: LuminaTokens.onSurfaceMuted,
          size: 20,
        ),
      ),
    );
  }
}
