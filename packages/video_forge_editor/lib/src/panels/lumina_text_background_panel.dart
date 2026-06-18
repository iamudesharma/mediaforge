import 'package:flutter/material.dart';
import 'package:video_forge_kit/video_forge_kit.dart';

import '../theme/lumina_tokens.dart';
import '../widgets/lumina_slider.dart';
import '../widgets/lumina_style_card.dart';

/// Text Background panel — box style, colors, opacity / radius / padding.
class LuminaTextBackgroundPanel extends StatelessWidget {
  const LuminaTextBackgroundPanel({
    super.key,
    required this.style,
    required this.onPresetSelected,
    required this.onBackgroundColorSelected,
    required this.onOpacityChanged,
    required this.onCornerRadiusChanged,
    required this.onPaddingChanged,
    required this.onToggleBackground,
  });

  final VideoTextOverlayStyle style;
  final ValueChanged<VideoTextLookPreset> onPresetSelected;
  final ValueChanged<Color> onBackgroundColorSelected;
  final ValueChanged<double> onOpacityChanged;
  final ValueChanged<double> onCornerRadiusChanged;
  final ValueChanged<double> onPaddingChanged;
  final VoidCallback onToggleBackground;

  double get _bgOpacity => style.backgroundColor.a;

  @override
  Widget build(BuildContext context) {
    final bgColors = [
      const Color(0xFF1A1C20),
      const Color(0xFF111317),
      LuminaTokens.accent.withValues(alpha: 0.25),
      LuminaTokens.accent.withValues(alpha: 0.5),
      LuminaTokens.primaryFixed.withValues(alpha: 0.35),
      LuminaTokens.secondary.withValues(alpha: 0.25),
      Colors.white.withValues(alpha: 0.15),
      Colors.black.withValues(alpha: 0.6),
      LuminaTokens.surfaceContainerHigh,
      LuminaTokens.surfaceBright,
      LuminaTokens.outlineVariant,
      LuminaTokens.onSurfaceMuted.withValues(alpha: 0.3),
      LuminaTokens.accentContainer.withValues(alpha: 0.8),
      LuminaTokens.secondaryContainer.withValues(alpha: 0.6),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        LuminaPanelTitle(
          'Text Background',
          trailing: Switch(
            value: style.showBackground,
            activeThumbColor: LuminaTokens.accent,
            activeTrackColor: LuminaTokens.accentContainer,
            onChanged: (_) => onToggleBackground(),
          ),
        ),
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
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: LuminaTokens.space3),
        LuminaColorGrid(
          colors: bgColors,
          selected: style.backgroundColor,
          onSelected: onBackgroundColorSelected,
        ),
        const SizedBox(height: LuminaTokens.space3),
        LuminaSlider(
          label: 'Box color',
          value: 100,
          min: 0,
          max: 100,
          divisions: 20,
          displayValue: '100',
          onChanged: (_) {},
        ),
        LuminaSlider(
          label: 'Opacity',
          value: _bgOpacity * 100,
          min: 0,
          max: 100,
          divisions: 20,
          displayValue: '${(_bgOpacity * 100).round()}%',
          onChanged: onOpacityChanged,
        ),
        LuminaSlider(
          label: 'Corner radius',
          value: style.cornerRadius,
          min: 0,
          max: 32,
          divisions: 32,
          displayValue: '${style.cornerRadius.round()}px',
          onChanged: onCornerRadiusChanged,
        ),
        LuminaSlider(
          label: 'Padding',
          value: style.padding,
          min: 0,
          max: 32,
          divisions: 32,
          displayValue: '${style.padding.round()}px',
          onChanged: onPaddingChanged,
        ),
      ],
    );
  }
}
