import 'package:flutter/material.dart';
import 'package:video_forge_kit/video_forge_kit.dart';

import '../theme/lumina_tokens.dart';
import '../widgets/frosted_bar.dart';
import 'lumina_text_animation_panel.dart';
import 'lumina_text_background_panel.dart';
import 'lumina_text_style_panel.dart';

enum TextEditTab { style, background, animation }

/// Lumina Edit bottom chrome when a text overlay is selected.
class TextOverlayEditChrome extends StatefulWidget {
  const TextOverlayEditChrome({
    super.key,
    required this.overlay,
    required this.videoDurationMs,
    required this.replayToken,
    required this.onPresetSelected,
    required this.onStyleChanged,
    required this.onAnimationSelected,
    required this.onToggleBackground,
    required this.onTimingChanged,
    required this.onDone,
  });

  final VideoOverlayItem overlay;
  final int videoDurationMs;
  final int replayToken;
  final ValueChanged<VideoTextLookPreset> onPresetSelected;
  final ValueChanged<VideoTextOverlayStyle> onStyleChanged;
  final ValueChanged<VideoTextAnimation> onAnimationSelected;
  final VoidCallback onToggleBackground;
  final void Function(int startMs, int endMs) onTimingChanged;
  final VoidCallback onDone;

  @override
  State<TextOverlayEditChrome> createState() => _TextOverlayEditChromeState();
}

class _TextOverlayEditChromeState extends State<TextOverlayEditChrome> {
  TextEditTab _tab = TextEditTab.style;

  VideoTextOverlayStyle get _style =>
      widget.overlay.resolvedTextSpec?.style ?? VideoTextOverlayStyle.defaults;

  void _patchStyle(VideoTextOverlayStyle style) {
    widget.onStyleChanged(style);
  }

  @override
  Widget build(BuildContext context) {
    final spec = widget.overlay.resolvedTextSpec;
    if (spec == null) return const SizedBox.shrink();

    return FrostedBar(
      borderTop: true,
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.48,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  LuminaTokens.space3,
                  LuminaTokens.space2,
                  LuminaTokens.space2,
                  0,
                ),
                child: Row(
                  children: [
                    _TabChip(
                      label: 'Style',
                      selected: _tab == TextEditTab.style,
                      onTap: () => setState(() => _tab = TextEditTab.style),
                    ),
                    _TabChip(
                      label: 'Background',
                      selected: _tab == TextEditTab.background,
                      onTap: () =>
                          setState(() => _tab = TextEditTab.background),
                    ),
                    _TabChip(
                      label: 'Animation',
                      selected: _tab == TextEditTab.animation,
                      onTap: () =>
                          setState(() => _tab = TextEditTab.animation),
                    ),
                    const Spacer(),
                    TextButton(onPressed: widget.onDone, child: const Text('Done')),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(LuminaTokens.space3),
                  child: switch (_tab) {
                    TextEditTab.style => LuminaTextStylePanel(
                        style: _style,
                        onPresetSelected: widget.onPresetSelected,
                        onColorSelected: (c) =>
                            _patchStyle(_style.copyWith(color: c)),
                        onGlowChanged: (v) =>
                            _patchStyle(_style.copyWith(glowIntensity: v)),
                        onTrackingChanged: (v) =>
                            _patchStyle(_style.copyWith(letterSpacing: v)),
                      ),
                    TextEditTab.background => LuminaTextBackgroundPanel(
                        style: _style,
                        onPresetSelected: widget.onPresetSelected,
                        onBackgroundColorSelected: (c) => _patchStyle(
                          _style.copyWith(
                            backgroundColor: c.withValues(alpha: _style.backgroundColor.a),
                            showBackground: true,
                            backgroundStyle: VideoTextBackgroundStyle.rounded,
                          ),
                        ),
                        onOpacityChanged: (v) => _patchStyle(
                          _style.copyWith(
                            backgroundColor: _style.backgroundColor
                                .withValues(alpha: v / 100),
                          ),
                        ),
                        onCornerRadiusChanged: (v) =>
                            _patchStyle(_style.copyWith(cornerRadius: v)),
                        onPaddingChanged: (v) =>
                            _patchStyle(_style.copyWith(padding: v)),
                        onToggleBackground: widget.onToggleBackground,
                      ),
                    TextEditTab.animation => LuminaTextAnimationPanel(
                        style: _style,
                        previewLabel: spec.label,
                        replayToken: widget.replayToken,
                        onAnimationSelected: widget.onAnimationSelected,
                        onDurationScaleChanged: (v) => _patchStyle(
                          _style.copyWith(animationDurationScale: v),
                        ),
                      ),
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  LuminaTokens.space3,
                  0,
                  LuminaTokens.space3,
                  LuminaTokens.space2,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Visible ${TimelineFormat.clock(widget.overlay.startMs)} → ${TimelineFormat.clock(widget.overlay.endMs)}',
                      style: const TextStyle(
                        color: LuminaTokens.onSurfaceMuted,
                        fontSize: 11,
                        fontFamily: 'Menlo',
                      ),
                    ),
                    RangeSlider(
                      values: RangeValues(
                        widget.overlay.startMs.toDouble(),
                        widget.overlay.endMs.toDouble().clamp(
                          widget.overlay.startMs + 200,
                          widget.videoDurationMs.toDouble(),
                        ),
                      ),
                      min: 0,
                      max: widget.videoDurationMs > 0
                          ? widget.videoDurationMs.toDouble()
                          : 1000,
                      activeColor: LuminaTokens.accent,
                      onChanged: (r) => widget.onTimingChanged(
                        r.start.round(),
                        r.end.round(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: LuminaTokens.space1),
      child: Material(
        color: selected
            ? LuminaTokens.accentContainer.withValues(alpha: 0.5)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(LuminaTokens.radiusSm),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(LuminaTokens.radiusSm),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: LuminaTokens.space2,
              vertical: LuminaTokens.space1,
            ),
            child: Text(
              label,
              style: TextStyle(
                color: selected
                    ? LuminaTokens.accent
                    : LuminaTokens.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
