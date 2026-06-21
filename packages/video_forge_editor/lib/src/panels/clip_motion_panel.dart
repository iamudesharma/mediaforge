import 'package:flutter/material.dart';
import 'package:video_forge_kit/video_forge_kit.dart';

import '../theme/lumina_tokens.dart';

/// Keyframe motion presets (Ken Burns, pan).
class ClipMotionPanel extends StatelessWidget {
  const ClipMotionPanel({
    super.key,
    required this.durationMs,
    required this.currentEffects,
    required this.onPresetSelected,
  });

  final int durationMs;
  final ClipEffects currentEffects;
  final ValueChanged<ClipEffects> onPresetSelected;

  @override
  Widget build(BuildContext context) {
    final dur = durationMs > 0 ? durationMs : 3000;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Motion',
          style: TextStyle(
            color: LuminaTokens.onSurface,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: LuminaTokens.space2),
        Wrap(
          spacing: LuminaTokens.space2,
          runSpacing: LuminaTokens.space2,
          children: [
            _PresetChip(
              label: 'Zoom in',
              icon: Icons.zoom_in,
              onTap: () {
                final preset = ClipEffectsKit.kenBurnsZoomIn(durationMs: dur);
                final fx = ClipEffectsKit.mergeMotionPreset(currentEffects, preset);
                debugPrint('[ClipEffects] motion preset=zoom_in dur=${dur}ms');
                onPresetSelected(fx);
              },
            ),
            _PresetChip(
              label: 'Zoom out',
              icon: Icons.zoom_out,
              onTap: () {
                final preset = ClipEffectsKit.kenBurnsZoomIn(
                  durationMs: dur,
                  fromScale: 1.35,
                  toScale: 1.0,
                );
                final fx = ClipEffectsKit.mergeMotionPreset(currentEffects, preset);
                debugPrint('[ClipEffects] motion preset=zoom_out dur=${dur}ms');
                onPresetSelected(fx);
              },
            ),
            _PresetChip(
              label: 'Pan →',
              icon: Icons.swipe_right,
              onTap: () {
                final preset = ClipEffectsKit.panLeftToRight(durationMs: dur);
                final fx = ClipEffectsKit.mergeMotionPreset(currentEffects, preset);
                debugPrint('[ClipEffects] motion preset=pan_lr dur=${dur}ms');
                onPresetSelected(fx);
              },
            ),
          ],
        ),
      ],
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, size: 16, color: LuminaTokens.accent),
      label: Text(label),
      onPressed: onTap,
      backgroundColor: LuminaTokens.surfaceContainerHigh,
      labelStyle: const TextStyle(
        color: LuminaTokens.onSurface,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
