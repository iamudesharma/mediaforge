import 'package:flutter/material.dart';
import 'package:video_forge_kit/video_forge_kit.dart';

import '../theme/lumina_tokens.dart';
import '../widgets/lumina_slider.dart';
import '../widgets/lumina_style_card.dart';

/// Text Style panel — presets, colors, glow / tracking sliders.
class LuminaTextStylePanel extends StatelessWidget {
  const LuminaTextStylePanel({
    super.key,
    required this.style,
    required this.onPresetSelected,
    required this.onColorSelected,
    required this.onGlowChanged,
    required this.onTrackingChanged,
  });

  final VideoTextOverlayStyle style;
  final ValueChanged<VideoTextLookPreset> onPresetSelected;
  final ValueChanged<Color> onColorSelected;
  final ValueChanged<double> onGlowChanged;
  final ValueChanged<double> onTrackingChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const LuminaPanelTitle('Text Style'),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final (preset, label) in luminaStylePresets)
                Padding(
                  padding: const EdgeInsets.only(right: LuminaTokens.space2),
                  child: LuminaStyleCard(
                    label: label,
                    selected: style.lookPreset == preset,
                    onTap: () => onPresetSelected(preset),
                    preview: Text(
                      'Aa',
                      style: TextStyle(
                        color: style.color,
                        fontSize: 18,
                        fontWeight: preset == VideoTextLookPreset.strong
                            ? FontWeight.w900
                            : FontWeight.w600,
                        fontStyle: preset == VideoTextLookPreset.signature
                            ? FontStyle.italic
                            : FontStyle.normal,
                        shadows: preset == VideoTextLookPreset.neon
                            ? [
                                Shadow(
                                  color: LuminaTokens.accent.withValues(alpha: 0.8),
                                  blurRadius: 8,
                                ),
                              ]
                            : null,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: LuminaTokens.space3),
        LuminaColorGrid(
          colors: videoTextAccentColors,
          selected: style.color,
          onSelected: onColorSelected,
        ),
        const SizedBox(height: LuminaTokens.space3),
        LuminaSlider(
          label: 'Glow intensity',
          value: style.glowIntensity,
          min: 0,
          max: 1,
          divisions: 20,
          displayValue: '${(style.glowIntensity * 100).round()}%',
          onChanged: onGlowChanged,
        ),
        LuminaSlider(
          label: 'Text tracking',
          value: style.letterSpacing,
          min: -1,
          max: 4,
          divisions: 20,
          displayValue: style.letterSpacing.toStringAsFixed(1),
          onChanged: onTrackingChanged,
        ),
      ],
    );
  }
}
