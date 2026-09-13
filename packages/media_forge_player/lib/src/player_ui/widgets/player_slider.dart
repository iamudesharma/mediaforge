import 'package:flutter/material.dart';

/// Compact labelled slider used for volume (and settings scalars).
class PlayerSlider extends StatelessWidget {
  const PlayerSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.onChangeEnd,
    this.min = 0,
    this.max = 1,
    this.semanticLabel,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  final double min;
  final double max;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 3,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
        activeTrackColor: Theme.of(context).colorScheme.primary,
        inactiveTrackColor: Colors.white24,
        thumbColor: Colors.white,
      ),
      child: Slider(
        min: min,
        max: max,
        value: value.clamp(min, max),
        onChanged: onChanged,
        onChangeEnd: onChangeEnd,
        semanticFormatterCallback: semanticLabel == null
            ? null
            : (_) => semanticLabel!,
      ),
    );
  }
}
