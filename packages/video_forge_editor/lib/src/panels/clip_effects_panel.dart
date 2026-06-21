import 'package:flutter/material.dart';
import 'package:video_forge_kit/video_forge_kit.dart';

import '../theme/lumina_tokens.dart';

/// Speed, zoom, and rotate controls for the source clip.
///
/// [onPreview] fires on every slider tick (cheap). [onCommit] fires for discrete
/// actions and when the slider is released.
class ClipEffectsPanel extends StatefulWidget {
  const ClipEffectsPanel({
    super.key,
    required this.effects,
    required this.onPreview,
    required this.onCommit,
    required this.onReset,
    this.clipDurationMs = 0,
  });

  final ClipEffects effects;
  final ValueChanged<ClipEffects> onPreview;
  final ValueChanged<ClipEffects> onCommit;
  final VoidCallback onReset;
  final int clipDurationMs;

  @override
  State<ClipEffectsPanel> createState() => _ClipEffectsPanelState();
}

class _ClipEffectsPanelState extends State<ClipEffectsPanel> {
  static const _speedPresets = [0.5, 0.75, 1.0, 1.5, 2.0];
  static const _rampPresets = [0.5, 2.0];

  late ClipEffects _draft;

  @override
  void initState() {
    super.initState();
    _draft = widget.effects;
  }

  void _preview(ClipEffects next) {
    setState(() => _draft = next);
    widget.onPreview(next);
  }

  void _commit(ClipEffects next) {
    setState(() => _draft = next);
    widget.onCommit(next);
  }

  @override
  Widget build(BuildContext context) {
    final effects = _draft;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Text(
              'Clip effects',
              style: TextStyle(
                color: LuminaTokens.onSurface,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            TextButton(onPressed: widget.onReset, child: const Text('Reset')),
          ],
        ),
        const SizedBox(height: LuminaTokens.space2),
        const Text(
          'Speed',
          style: TextStyle(
            color: LuminaTokens.onSurfaceVariant,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: LuminaTokens.space1),
        Wrap(
          spacing: LuminaTokens.space2,
          children: _speedPresets.map((rate) {
            final selected = (effects.speed - rate).abs() < 0.01 &&
                effects.speedSegments.isEmpty;
            return ChoiceChip(
              label: Text('${rate}x'),
              selected: selected,
              onSelected: (_) {
                debugPrint('[ClipEffects] speed=$rate');
                _commit(ClipEffectsKit.withSpeed(effects, rate));
              },
              selectedColor: LuminaTokens.accentContainer,
              labelStyle: TextStyle(
                color: selected
                    ? LuminaTokens.accent
                    : LuminaTokens.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            );
          }).toList(),
        ),
        if (widget.clipDurationMs > 0) ...[
          const SizedBox(height: LuminaTokens.space2),
          const Text(
            'Speed ramp (whole clip)',
            style: TextStyle(
              color: LuminaTokens.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: LuminaTokens.space1),
          Wrap(
            spacing: LuminaTokens.space2,
            children: [
              ActionChip(
                label: const Text('Normal'),
                onPressed: () {
                  _commit(
                    ClipEffectsKit.withFullClipSpeedRamp(
                      effects,
                      widget.clipDurationMs,
                      rate: 1.0,
                    ),
                  );
                },
              ),
              ..._rampPresets.map((rate) {
                return ActionChip(
                  label: Text('${rate}x ramp'),
                  onPressed: () {
                    debugPrint(
                      '[ClipEffects] speed_ramp=$rate dur=${widget.clipDurationMs}',
                    );
                    _commit(
                      ClipEffectsKit.withFullClipSpeedRamp(
                        effects,
                        widget.clipDurationMs,
                        rate: rate,
                      ),
                    );
                  },
                );
              }),
            ],
          ),
        ],
        const SizedBox(height: LuminaTokens.space3),
        const Text(
          'Zoom',
          style: TextStyle(
            color: LuminaTokens.onSurfaceVariant,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        Slider(
          value: effects.base.scale.clamp(1.0, 3.0),
          min: 1,
          max: 3,
          divisions: 20,
          label: '${effects.base.scale.toStringAsFixed(2)}x',
          onChanged: (v) {
            _preview(ClipEffectsKit.copyWithBase(_draft, scale: v));
          },
          onChangeEnd: (v) {
            _commit(ClipEffectsKit.copyWithBase(_draft, scale: v));
          },
        ),
        const SizedBox(height: LuminaTokens.space2),
        const Text(
          'Rotate',
          style: TextStyle(
            color: LuminaTokens.onSurfaceVariant,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        Wrap(
          spacing: LuminaTokens.space2,
          children: [0, 90, 180, 270].map((deg) {
            final selected = (effects.base.rotation - deg).abs() < 0.5;
            return ChoiceChip(
              label: Text('${deg}°'),
              selected: selected,
              onSelected: (_) {
                debugPrint('[ClipEffects] rotation=$deg');
                _commit(
                  ClipEffectsKit.copyWithBase(
                    effects,
                    rotation: deg.toDouble(),
                  ),
                );
              },
              selectedColor: LuminaTokens.accentContainer,
            );
          }).toList(),
        ),
      ],
    );
  }
}
