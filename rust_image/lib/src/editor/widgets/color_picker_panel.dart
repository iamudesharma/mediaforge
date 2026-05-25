import 'package:flutter/material.dart';

import '../theme/lumina_tokens.dart';

/// Compact HSV sliders for custom blank-canvas / accent colors.
class ColorPickerPanel extends StatelessWidget {
  const ColorPickerPanel({
    super.key,
    required this.color,
    required this.onChanged,
  });

  final Color color;
  final ValueChanged<Color> onChanged;

  @override
  Widget build(BuildContext context) {
    final hsv = HSVColor.fromColor(color);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 48,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(LuminaTokens.radiusMd),
            border: Border.all(color: LuminaTokens.outlineVariant),
          ),
        ),
        const SizedBox(height: 12),
        _SliderRow(
          label: 'Hue',
          value: hsv.hue,
          max: 360,
          onChanged: (v) => onChanged(hsv.withHue(v).toColor()),
        ),
        _SliderRow(
          label: 'Saturation',
          value: hsv.saturation,
          max: 1,
          onChanged: (v) => onChanged(hsv.withSaturation(v).toColor()),
        ),
        _SliderRow(
          label: 'Brightness',
          value: hsv.value,
          max: 1,
          onChanged: (v) => onChanged(hsv.withValue(v).toColor()),
        ),
      ],
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: Slider(
              value: value.clamp(0, max),
              min: 0,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
