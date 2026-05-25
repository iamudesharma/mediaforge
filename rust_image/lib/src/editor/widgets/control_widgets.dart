import 'package:flutter/material.dart';

import '../theme/app_typography.dart';
import '../theme/editor_motion.dart';
import '../theme/lumina_tokens.dart';

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: LuminaTokens.gutterTool,
        top: LuminaTokens.padXs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: AppTypography.sectionCaps(context),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

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
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String display;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: LuminaTokens.gutterTool),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: LuminaTokens.onSurface,
                      ),
                ),
              ),
              AnimatedSwitcher(
                duration: EditorMotion.fast,
                child: Text(
                  display,
                  key: ValueKey(display),
                  style: AppTypography.numericValue(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: LuminaTokens.padSm),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ],
      ),
    );
  }
}

class ActionChipRow<T> extends StatelessWidget {
  const ActionChipRow({
    super.key,
    required this.items,
    required this.label,
    required this.selected,
    required this.onSelected,
    this.horizontal = false,
  });

  final List<T> items;
  final String Function(T) label;
  final T selected;
  final ValueChanged<T> onSelected;
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    if (horizontal) {
      return SizedBox(
        height: 40,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(width: LuminaTokens.padSm),
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
      spacing: LuminaTokens.padSm,
      runSpacing: LuminaTokens.padSm,
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(LuminaTokens.radiusLg),
            color: selected
                ? LuminaTokens.primary.withValues(alpha: 0.2)
                : LuminaTokens.surfaceContainerHigh,
            border: Border.all(
              color: selected
                  ? LuminaTokens.primary.withValues(alpha: 0.7)
                  : LuminaTokens.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              shadows: const [],
              color: selected ? LuminaTokens.primary : LuminaTokens.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

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

/// Horizontal filter preset strip (Lumina Filters screen).
class LuminaFilterStrip extends StatelessWidget {
  const LuminaFilterStrip({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
    this.enabled = true,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 88,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(vertical: LuminaTokens.padSm),
        itemCount: labels.length,
        separatorBuilder: (_, _) => const SizedBox(width: LuminaTokens.padSm),
        itemBuilder: (context, i) {
          final selected = i == selectedIndex;
          return GestureDetector(
            onTap: enabled ? () => onSelected(i) : null,
            child: AnimatedContainer(
              duration: EditorMotion.fast,
              width: 72,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(LuminaTokens.radiusMd),
                color: LuminaTokens.surfaceContainerHigh,
                border: Border.all(
                  color: selected
                      ? LuminaTokens.primary
                      : LuminaTokens.outlineVariant,
                  width: selected ? 2 : 1,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.image_outlined,
                    color: selected
                        ? LuminaTokens.primary
                        : LuminaTokens.onSurfaceVariant,
                    size: 28,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    labels[i],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      shadows: const [],
                      color: selected
                          ? LuminaTokens.primary
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
