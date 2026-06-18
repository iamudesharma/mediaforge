import 'package:flutter/material.dart';

import '../theme/app_typography.dart';
import '../theme/lumina_tokens.dart';

/// Mint-glow slider used in Lumina Edit panels.
class LuminaSlider extends StatelessWidget {
  const LuminaSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.displayValue,
    this.divisions,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final String? displayValue;
  final int? divisions;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: LuminaTokens.onSurfaceVariant,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Text(
              displayValue ?? value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1),
              style: AppTypography.numericValue(context),
            ),
          ],
        ),
        const SizedBox(height: LuminaTokens.space1),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: LuminaTokens.sliderTrackHeight,
            activeTrackColor: LuminaTokens.accent,
            inactiveTrackColor: LuminaTokens.surfaceContainerHigh,
            thumbColor: Colors.white,
            overlayColor: LuminaTokens.selectionGlow,
            thumbShape: const RoundSliderThumbShape(
              enabledThumbRadius: LuminaTokens.sliderThumbRadius,
            ),
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
