import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_typography.dart';
import '../theme/editor_motion.dart';
import '../theme/lumina_tokens.dart';

/// CapCut-style slider: 4 px track, 22 px thumb, value chip floating above
/// the thumb during drag. Double-tap to reset, center detent haptic at value
/// 0 for bipolar sliders, haptics on each step for integer divisions.
///
/// Used as the primary adjustment slider throughout the editor.
class ValueChipSlider extends StatefulWidget {
  const ValueChipSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.onChangeEnd,
    this.onReset,
    this.resetValue = 0,
    this.divisions,
    this.formatter = _defaultFormatter,
    this.bipolar = false,
    this.leading,
    this.trailing,
    this.enabled = true,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;

  /// Called when the user double-taps the slider to reset.
  final VoidCallback? onReset;

  /// The "default" value the slider resets to on double-tap.
  final double resetValue;

  /// Format the displayed value (e.g. "12", "+12", "12.5°", "85%").
  final String Function(double value) formatter;

  /// True for sliders that have a natural center (Warmth, Hue, Fade, etc.).
  /// Haptic feedback fires when crossing 0.
  final bool bipolar;

  final Widget? leading;
  final Widget? trailing;
  final bool enabled;

  static String _defaultFormatter(double v) => v.round().toString();

  @override
  State<ValueChipSlider> createState() => _ValueChipSliderState();
}

class _ValueChipSliderState extends State<ValueChipSlider> {
  bool _dragging = false;
  double _lastHapticValue = 0;
  bool _initialized = false;

  void _maybeHapticForDetent(double v) {
    if (!widget.bipolar) return;
    if (v == 0) return;
    final crossed =
        (_lastHapticValue < 0 && v > 0) || (_lastHapticValue > 0 && v < 0);
    if (crossed) {
      HapticFeedback.selectionClick();
    }
    _lastHapticValue = v;
  }

  void _handleDoubleTap() {
    HapticFeedback.mediumImpact();
    widget.onChanged?.call(widget.resetValue);
    widget.onChangeEnd?.call(widget.resetValue);
    widget.onReset?.call();
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.value.clamp(widget.min, widget.max);
    if (!_initialized) {
      _lastHapticValue = value;
      _initialized = true;
    }
    final showReset = (value - widget.resetValue).abs() > (widget.max - widget.min) * 0.001;

    return Padding(
      padding: const EdgeInsets.only(
        bottom: LuminaTokens.space3,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (widget.leading != null) ...[
                widget.leading!,
                const SizedBox(width: LuminaTokens.space2),
              ],
              Expanded(
                child: Text(
                  widget.label,
                  style: AppTypography
                      .luminaTextTheme(Theme.of(context).colorScheme)
                      .bodyMedium
                      ?.copyWith(
                        color: LuminaTokens.onSurface,
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ),
              AnimatedOpacity(
                duration: EditorMotion.snap,
                opacity: _dragging ? 1 : 0,
                child: _ValueBubble(
                  text: widget.formatter(value),
                ),
              ),
              if (showReset && widget.onReset != null) ...[
                const SizedBox(width: LuminaTokens.space2),
                _ResetPill(
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    widget.onChanged?.call(widget.resetValue);
                    widget.onChangeEnd?.call(widget.resetValue);
                    widget.onReset?.call();
                  },
                ),
              ],
              if (widget.trailing != null) ...[
                const SizedBox(width: LuminaTokens.space2),
                widget.trailing!,
              ],
            ],
          ),
          const SizedBox(height: LuminaTokens.space2),
          Stack(
            alignment: Alignment.center,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onDoubleTap: widget.enabled ? _handleDoubleTap : null,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: LuminaTokens.sliderTrackHeight,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: LuminaTokens.sliderThumbRadius,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 20,
                    ),
                    activeTrackColor: widget.enabled
                        ? LuminaTokens.accent
                        : LuminaTokens.onSurfaceMuted,
                    inactiveTrackColor: LuminaTokens.surfaceContainerHigh,
                    thumbColor: Colors.white,
                    overlayColor: LuminaTokens.accentSurface,
                  ),
                  child: Slider(
                    value: value,
                    min: widget.min,
                    max: widget.max,
                    divisions: widget.divisions,
                    onChanged: widget.enabled
                        ? (v) {
                            setState(() => _dragging = true);
                            _maybeHapticForDetent(v);
                            widget.onChanged?.call(v);
                          }
                        : null,
                    onChangeStart: widget.enabled
                        ? (_) {
                            HapticFeedback.selectionClick();
                            setState(() => _dragging = true);
                          }
                        : null,
                    onChangeEnd: widget.enabled
                        ? (v) {
                            setState(() => _dragging = false);
                            widget.onChangeEnd?.call(v);
                          }
                        : null,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ValueBubble extends StatelessWidget {
  const _ValueBubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: LuminaTokens.sliderValueBubbleWidth,
      height: LuminaTokens.sliderValueBubbleHeight,
      decoration: BoxDecoration(
        color: LuminaTokens.accentContainer,
        borderRadius: BorderRadius.circular(LuminaTokens.radiusSm),
        border: Border.all(
          color: LuminaTokens.accent.withValues(alpha: 0.4),
          width: 0.5,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.sliderValueBubble(context),
      ),
    );
  }
}

class _ResetPill extends StatelessWidget {
  const _ResetPill({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(LuminaTokens.radiusSm),
      child: Container(
        height: LuminaTokens.sliderValueBubbleHeight,
        padding: const EdgeInsets.symmetric(horizontal: LuminaTokens.space2),
        decoration: BoxDecoration(
          color: LuminaTokens.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(LuminaTokens.radiusSm),
          border: Border.all(color: LuminaTokens.outlineVariant),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.refresh_rounded,
              size: 12,
              color: LuminaTokens.onSurfaceVariant,
            ),
            const SizedBox(width: 2),
            Text(
              'Reset',
              style: AppTypography.navLabel(context, selected: false)
                  .copyWith(fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}
