import 'package:flutter/material.dart';

import '../models/layer_transform.dart';
import '../models/overlay_layer.dart';
import '../models/text_style_draft.dart';
import '../services/text_paint_style.dart';
import '../theme/lumina_tokens.dart';
import 'control_widgets.dart';
import 'lumina_color_picker.dart';

/// Preset looks for sticker / text tools.
enum TextLookPreset {
  solidWhite,
  solidBlack,
  solidMint,
  gradientSunset,
  gradientOcean,
  gradientFire,
  gradientMint,
  gradientViolet,
}

enum EditorTextFont { system, serif, mono, script }

extension EditorTextFontX on EditorTextFont {
  String get label => switch (this) {
        EditorTextFont.system => 'Default',
        EditorTextFont.serif => 'Serif',
        EditorTextFont.mono => 'Mono',
        EditorTextFont.script => 'Script',
      };

  String? get family => switch (this) {
        EditorTextFont.system => null,
        EditorTextFont.serif => 'serif',
        EditorTextFont.mono => 'monospace',
        EditorTextFont.script => 'cursive',
      };

  static EditorTextFont fromFamily(String? f) => switch (f) {
        'serif' => EditorTextFont.serif,
        'monospace' => EditorTextFont.mono,
        'cursive' => EditorTextFont.script,
        _ => EditorTextFont.system,
      };
}

extension TextLookPresetX on TextLookPreset {
  String get label => switch (this) {
        TextLookPreset.solidWhite => 'White',
        TextLookPreset.solidBlack => 'Black',
        TextLookPreset.solidMint => 'Mint',
        TextLookPreset.gradientSunset => 'Sunset',
        TextLookPreset.gradientOcean => 'Ocean',
        TextLookPreset.gradientFire => 'Fire',
        TextLookPreset.gradientMint => 'Mint grad',
        TextLookPreset.gradientViolet => 'Violet',
      };

  TextStyleDraft apply(TextStyleDraft current) => switch (this) {
        TextLookPreset.solidWhite => current.copyWith(
            fillMode: TextFillMode.solid,
            color: Colors.white,
          ),
        TextLookPreset.solidBlack => current.copyWith(
            fillMode: TextFillMode.solid,
            color: Colors.black,
          ),
        TextLookPreset.solidMint => current.copyWith(
            fillMode: TextFillMode.solid,
            color: LuminaTokens.primary,
          ),
        TextLookPreset.gradientSunset => current.copyWith(
            fillMode: TextFillMode.gradient,
            color: const Color(0xFFFF9800),
            gradientEnd: const Color(0xFFE91E63),
            gradientAngleDeg: 0,
          ),
        TextLookPreset.gradientOcean => current.copyWith(
            fillMode: TextFillMode.gradient,
            color: const Color(0xFF26C6DA),
            gradientEnd: const Color(0xFF1565C0),
            gradientAngleDeg: 90,
          ),
        TextLookPreset.gradientFire => current.copyWith(
            fillMode: TextFillMode.gradient,
            color: const Color(0xFFFFEB3B),
            gradientEnd: const Color(0xFFD32F2F),
            gradientAngleDeg: 45,
          ),
        TextLookPreset.gradientMint => current.copyWith(
            fillMode: TextFillMode.gradient,
            color: LuminaTokens.primary,
            gradientEnd: const Color(0xFF00695C),
            gradientAngleDeg: 0,
          ),
        TextLookPreset.gradientViolet => current.copyWith(
            fillMode: TextFillMode.gradient,
            color: const Color(0xFFCE93D8),
            gradientEnd: const Color(0xFF512DA8),
            gradientAngleDeg: 135,
          ),
      };

  bool matches(TextStyleDraft d) {
    final t = apply(TextStyleDraft(fontSize: d.fontSize));
    if (t.fillMode != d.fillMode) return false;
    if (t.color.toARGB32() != d.color.toARGB32()) return false;
    if (t.fillMode == TextFillMode.gradient &&
        t.gradientEnd.toARGB32() != d.gradientEnd.toARGB32()) {
      return false;
    }
    return true;
  }
}

/// Shared text styling UI: presets, color picker, Advanced (gradient + font).
class TextStyleControls extends StatefulWidget {
  const TextStyleControls({
    super.key,
    required this.value,
    required this.onChanged,
    this.showFontSize = true,
  });

  final TextStyleDraft value;
  final ValueChanged<TextStyleDraft> onChanged;
  final bool showFontSize;

  @override
  State<TextStyleControls> createState() => _TextStyleControlsState();
}

class _TextStyleControlsState extends State<TextStyleControls> {
  bool _advancedOpen = false;

  TextStyleDraft get _v => widget.value;

  void _update(TextStyleDraft next) => widget.onChanged(next);

  TextLookPreset? get _activePreset {
    for (final p in TextLookPreset.values) {
      if (p.matches(_v)) return p;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final presetForChip = _activePreset ?? TextLookPreset.solidWhite;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _StylePreview(draft: _v),
        const SizedBox(height: LuminaTokens.padSm),
        const SectionHeader('Style presets'),
        ActionChipRow<TextLookPreset>(
          horizontal: true,
          items: TextLookPreset.values,
          label: (p) => p.label,
          selected: presetForChip,
          onSelected: (p) => _update(p.apply(_v)),
        ),
        const SizedBox(height: LuminaTokens.padSm),
        Text(
          _v.fillMode == TextFillMode.gradient ? 'Gradient start' : 'Text color',
          style: Theme.of(context).textTheme.labelMedium,
        ),
        const SizedBox(height: 8),
        LuminaColorSwatchRow(
          selected: _v.color,
          onSelected: (c) => _update(_v.copyWith(color: c)),
        ),
        if (_v.fillMode == TextFillMode.gradient) ...[
          const SizedBox(height: 12),
          Text(
            'Gradient end',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 8),
          LuminaColorSwatchRow(
            selected: _v.gradientEnd,
            presets: const [
              Color(0xFFE91E63),
              Color(0xFF1565C0),
              Color(0xFFD32F2F),
              Color(0xFF512DA8),
              Color(0xFFFFD54F),
              Colors.white,
            ],
            onSelected: (c) => _update(_v.copyWith(gradientEnd: c)),
          ),
        ],
        if (widget.showFontSize) ...[
          const SizedBox(height: 8),
          LabeledSlider(
            label: 'Font size',
            value: _v.fontSize,
            min: 12,
            max: 120,
            divisions: 27,
            display: _v.fontSize.round().toString(),
            onChanged: (v) => _update(_v.copyWith(fontSize: v)),
          ),
        ],
        const SizedBox(height: 8),
        Material(
          color: LuminaTokens.surfaceContainerLow,
          borderRadius: BorderRadius.circular(LuminaTokens.radiusMd),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              ListTile(
                dense: true,
                title: const Text('Advanced'),
                subtitle: Text(
                  _advancedOpen
                      ? 'Gradient angle, font family, weight & style'
                      : 'Font & gradient details',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                trailing: Icon(
                  _advancedOpen ? Icons.expand_less : Icons.expand_more,
                  color: LuminaTokens.onSurfaceVariant,
                ),
                onTap: () => setState(() => _advancedOpen = !_advancedOpen),
              ),
              if (_advancedOpen)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SectionHeader('Fill'),
                      ActionChipRow<TextFillMode>(
                        horizontal: true,
                        items: TextFillMode.values,
                        label: (m) =>
                            m == TextFillMode.solid ? 'Solid' : 'Gradient',
                        selected: _v.fillMode,
                        onSelected: (m) => _update(_v.copyWith(fillMode: m)),
                      ),
                      if (_v.fillMode == TextFillMode.gradient) ...[
                        const SizedBox(height: 8),
                        LabeledSlider(
                          label: 'Gradient angle',
                          value: _v.gradientAngleDeg,
                          min: 0,
                          max: 360,
                          divisions: 36,
                          display: '${_v.gradientAngleDeg.round()}°',
                          onChanged: (v) =>
                              _update(_v.copyWith(gradientAngleDeg: v)),
                        ),
                      ],
                      const SectionHeader('Font'),
                      ActionChipRow<EditorTextFont>(
                        horizontal: true,
                        items: EditorTextFont.values,
                        label: (f) => f.label,
                        selected: EditorTextFontX.fromFamily(_v.fontFamily),
                        onSelected: (f) => _update(
                          _v.copyWith(
                            fontFamily: f.family,
                            clearFontFamily: f == EditorTextFont.system,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ActionChipRow<FontWeight>(
                        horizontal: true,
                        items: const [
                          FontWeight.w400,
                          FontWeight.w600,
                          FontWeight.w800,
                        ],
                        label: (w) {
                          if (w == FontWeight.w800) return 'Bold';
                          if (w == FontWeight.w600) return 'Semi';
                          return 'Regular';
                        },
                        selected: _v.fontWeight,
                        onSelected: (w) => _update(_v.copyWith(fontWeight: w)),
                      ),
                      const SizedBox(height: 8),
                      ActionChipRow<FontStyle>(
                        horizontal: true,
                        items: FontStyle.values,
                        label: (s) =>
                            s == FontStyle.italic ? 'Italic' : 'Normal',
                        selected: _v.fontStyle,
                        onSelected: (s) => _update(_v.copyWith(fontStyle: s)),
                      ),
                      const SizedBox(height: 12),
                      _StylePreview(draft: _v),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StylePreview extends StatelessWidget {
  const _StylePreview({required this.draft});

  final TextStyleDraft draft;

  @override
  Widget build(BuildContext context) {
    final layer = draft.toLayer(
      id: 'preview',
      transform: const LayerTransform(),
      text: 'Preview',
      backgroundStyle: TextBackgroundStyle.none,
    );
    final style = textPaintStyle(
      layer,
      layoutWidth: 160,
      layoutHeight: 56,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: LuminaTokens.canvas,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: LuminaTokens.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        child: Center(
          child: Text('Preview', style: style.copyWith(fontSize: 28)),
        ),
      ),
    );
  }
}
