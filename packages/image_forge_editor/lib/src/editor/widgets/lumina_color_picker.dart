import 'package:flutter/material.dart';

import '../theme/lumina_tokens.dart';

/// Default swatches for paint / text (Lumina palette + basics).
const kLuminaDefaultColorPresets = [
  Color(0xFF4EDEA3),
  Colors.white,
  Colors.black,
  Color(0xFFFFD54F),
  Color(0xFFFF5252),
  Color(0xFF448AFF),
  Color(0xFFE040FB),
];

/// Row of preset circles plus a custom color picker button.
class LuminaColorSwatchRow extends StatelessWidget {
  const LuminaColorSwatchRow({
    super.key,
    required this.selected,
    required this.onSelected,
    this.presets = kLuminaDefaultColorPresets,
    this.swatchSize = 32,
  });

  final Color selected;
  final ValueChanged<Color> onSelected;
  final List<Color> presets;
  final double swatchSize;

  @override
  Widget build(BuildContext context) {
    final matchesPreset = presets.any(
      (c) => c.toARGB32() == selected.toARGB32(),
    );

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final c in presets)
          _Swatch(
            color: c,
            size: swatchSize,
            selected: selected.toARGB32() == c.toARGB32(),
            onTap: () => onSelected(c),
          ),
        _CustomSwatch(
          color: selected,
          size: swatchSize,
          highlighted: !matchesPreset,
          onTap: () async {
            final picked = await showLuminaColorPicker(
              context,
              initial: selected,
            );
            if (picked != null) onSelected(picked);
          },
        ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.size,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final double size;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Color',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? LuminaTokens.primary : LuminaTokens.outlineVariant,
              width: selected ? 2.5 : 1,
            ),
          ),
        ),
      ),
    );
  }
}

class _CustomSwatch extends StatelessWidget {
  const _CustomSwatch({
    required this.color,
    required this.size,
    required this.highlighted,
    required this.onTap,
  });

  final Color color;
  final double size;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Custom color',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: highlighted ? LuminaTokens.primary : LuminaTokens.outlineVariant,
              width: highlighted ? 2.5 : 1,
            ),
            gradient: const SweepGradient(
              colors: [
                Colors.red,
                Colors.yellow,
                Colors.green,
                Colors.cyan,
                Colors.blue,
                Colors.purple,
                Colors.red,
              ],
            ),
          ),
          child: Center(
            child: Container(
              width: size * 0.45,
              height: size * 0.45,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white24),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Modal color picker (HSV sliders + hex preview).
Future<Color?> showLuminaColorPicker(
  BuildContext context, {
  required Color initial,
}) {
  return showModalBottomSheet<Color>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: LuminaTokens.surfaceContainer,
    builder: (ctx) => _ColorPickerSheet(initial: initial),
  );
}

class _ColorPickerSheet extends StatefulWidget {
  const _ColorPickerSheet({required this.initial});

  final Color initial;

  @override
  State<_ColorPickerSheet> createState() => _ColorPickerSheetState();
}

class _ColorPickerSheetState extends State<_ColorPickerSheet> {
  late HSVColor _hsv;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.initial);
  }

  Color get _color => _hsv.toColor();

  @override
  Widget build(BuildContext context) {
    final hex =
        '#${_color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'PICK COLOR',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    letterSpacing: 0.8,
                    color: LuminaTokens.onSurface,
                  ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: _color,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: LuminaTokens.outlineVariant),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    hex,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: LuminaTokens.primary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _SliderRow(
              label: 'Hue',
              value: _hsv.hue,
              max: 360,
              display: '${_hsv.hue.round()}°',
              onChanged: (v) => setState(() => _hsv = _hsv.withHue(v)),
            ),
            _SliderRow(
              label: 'Saturation',
              value: _hsv.saturation,
              max: 1,
              display: '${(_hsv.saturation * 100).round()}%',
              onChanged: (v) => setState(() => _hsv = _hsv.withSaturation(v)),
            ),
            _SliderRow(
              label: 'Brightness',
              value: _hsv.value,
              max: 1,
              display: '${(_hsv.value * 100).round()}%',
              onChanged: (v) => setState(() => _hsv = _hsv.withValue(v)),
            ),
            _SliderRow(
              label: 'Opacity',
              value: _hsv.alpha,
              max: 1,
              display: '${(_hsv.alpha * 100).round()}%',
              onChanged: (v) => setState(() => _hsv = _hsv.withAlpha(v)),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.pop(context, _color),
              child: const Text('Use color'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.max,
    required this.display,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double max;
  final String display;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: LuminaTokens.onSurfaceVariant,
                  ),
            ),
          ),
          Expanded(
            child: Slider(
              value: value.clamp(0, max),
              min: 0,
              max: max,
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(
              display,
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: LuminaTokens.primary,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
