import 'package:flutter/material.dart';
import 'package:video_forge_kit/video_forge_kit.dart';

import '../theme/lumina_tokens.dart';
import '../widgets/lumina_slider.dart';
import '../widgets/lumina_style_card.dart';

/// Text Animation panel — Fade / Typewriter / Bounce / Slide In / Glitch.
class LuminaTextAnimationPanel extends StatelessWidget {
  const LuminaTextAnimationPanel({
    super.key,
    required this.style,
    required this.previewLabel,
    required this.replayToken,
    required this.onAnimationSelected,
    required this.onDurationScaleChanged,
  });

  final VideoTextOverlayStyle style;
  final String previewLabel;
  final int replayToken;
  final ValueChanged<VideoTextAnimation> onAnimationSelected;
  final ValueChanged<double> onDurationScaleChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const LuminaPanelTitle('Text Animation'),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 5,
            mainAxisSpacing: LuminaTokens.space2,
            crossAxisSpacing: LuminaTokens.space2,
            childAspectRatio: 0.72,
          ),
          itemCount: luminaTextAnimations.length,
          itemBuilder: (context, i) {
            final (anim, label) = luminaTextAnimations[i];
            final selected = style.animation == anim;
            return GestureDetector(
              onTap: () => onAnimationSelected(anim),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                decoration: BoxDecoration(
                  color: LuminaTokens.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(LuminaTokens.radiusSm),
                  border: Border.all(
                    color: selected
                        ? LuminaTokens.accent
                        : LuminaTokens.outlineVariant,
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
                    _AnimationIcon(animation: anim, selected: selected),
                    const SizedBox(height: LuminaTokens.space1),
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: selected
                            ? LuminaTokens.accent
                            : LuminaTokens.onSurfaceVariant,
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: LuminaTokens.space3),
        Center(
          child: AnimatedVideoTextOverlayContent(
            spec: VideoTextOverlaySpec(label: previewLabel, style: style),
            replayToken: replayToken,
          ),
        ),
        const SizedBox(height: LuminaTokens.space3),
        LuminaSlider(
          label: 'Duration',
          value: style.animationDurationScale,
          min: 0.5,
          max: 2,
          divisions: 15,
          displayValue: style.animationDurationScale < 1 ? 'Slow' : style.animationDurationScale > 1.2 ? 'Fast' : 'Normal',
          onChanged: onDurationScaleChanged,
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: const [
            Text('Slow', style: TextStyle(color: LuminaTokens.onSurfaceMuted, fontSize: 11)),
            Text('Fast', style: TextStyle(color: LuminaTokens.onSurfaceMuted, fontSize: 11)),
          ],
        ),
      ],
    );
  }
}

class _AnimationIcon extends StatelessWidget {
  const _AnimationIcon({required this.animation, required this.selected});

  final VideoTextAnimation animation;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final color = selected ? LuminaTokens.accent : LuminaTokens.onSurfaceVariant;
    return switch (animation) {
      VideoTextAnimation.fadeScale => Icon(Icons.blur_on, color: color, size: 22),
      VideoTextAnimation.typewriter => Text('T|', style: TextStyle(color: color, fontWeight: FontWeight.w700)),
      VideoTextAnimation.bounce => Icon(Icons.sports_basketball_outlined, color: color, size: 22),
      VideoTextAnimation.slideIn => Icon(Icons.fast_forward, color: color, size: 22),
      VideoTextAnimation.glitch => Text('TT', style: TextStyle(color: color, fontWeight: FontWeight.w900)),
      _ => Icon(Icons.animation, color: color, size: 22),
    };
  }
}
