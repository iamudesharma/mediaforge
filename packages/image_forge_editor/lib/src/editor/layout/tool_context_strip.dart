import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_forge/image_forge.dart';

import '../editor_session.dart';
import '../panels/tool_panels.dart';
import '../services/filter_descriptor.dart';
import '../services/mood_filter_names.dart';
import '../theme/lumina_tokens.dart';
import '../widgets/chip_pill.dart';
import '../widgets/control_widgets.dart';
import '../widgets/lumina_color_picker.dart';
import '../widgets/value_chip_slider.dart';

/// Per-tool context strip — only used for tools whose controls are short
/// enough to fit above the bottom nav without a full sheet (Filters and
/// Paint, today).
class ToolContextStrip extends StatelessWidget {
  const ToolContextStrip({
    super.key,
    required this.tool,
    required this.session,
    this.stickersTabIndex = 0,
    this.onStickersTabChanged,
    this.adjustKind = AdjustControlKind.brightness,
    this.onAdjustKindChanged,
  });

  final EditorTool tool;
  final EditorSession session;
  final int stickersTabIndex;
  final ValueChanged<int>? onStickersTabChanged;
  final AdjustControlKind adjustKind;
  final ValueChanged<AdjustControlKind>? onAdjustKindChanged;

  @override
  Widget build(BuildContext context) {
    return switch (tool) {
      EditorTool.filters => _FiltersStrip(session: session),
      EditorTool.paint => _PaintColorStrip(session: session),
      EditorTool.stickers => _StickersTabStrip(
          tabIndex: stickersTabIndex,
          onTabChanged: onStickersTabChanged,
        ),
      _ => const SizedBox.shrink(),
    };
  }
}

class _FiltersStrip extends StatefulWidget {
  const _FiltersStrip({required this.session});

  final EditorSession session;

  @override
  State<_FiltersStrip> createState() => _FiltersStripState();
}

class _FiltersStripState extends State<_FiltersStrip> {
  static const _presets = FilterPreset.values;
  static const _moods = MoodFilterPreset.values;
  int _selectedPreset = 0;
  double _presetStrength = 100;
  int _selectedMood = 0;
  double _moodStrength = 100;

  EditorSession get session => widget.session;

  FilterDescriptor? get _activePresetDescriptor {
    if (_selectedPreset <= 0) return null;
    return FilterDescriptor.preset(
      _presets[_selectedPreset - 1],
      strength: _presetStrength / 100,
    );
  }

  MoodFilterPreset? get _activeMoodPreset {
    if (_selectedMood <= 0) return null;
    return _moods[_selectedMood - 1];
  }

  static String _presetName(FilterPreset p) {
    final n = p.name;
    return n[0].toUpperCase() + n.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    final presetLabels = ['Original', ..._presets.map(_presetName)];
    final moodLabels = ['Original', ..._moods.map(moodFilterDisplayName)];

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: LuminaTokens.space3,
        vertical: LuminaTokens.space2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LuminaFilterStrip(
            labels: presetLabels,
            selectedIndex: _selectedPreset,
            enabled: session.hasImage && !session.busy,
            onSelected: (i) {
              setState(() => _selectedPreset = i);
              if (i == 0) return;
              session.applyFilter(
                label: 'Preset',
                descriptor: FilterDescriptor.preset(
                  _presets[i - 1],
                  strength: _presetStrength / 100,
                ),
              );
            },
          ),
          if (_selectedPreset > 0) ...[
            const SizedBox(height: LuminaTokens.space3),
            ValueChipSlider(
              label: 'Intensity',
              value: _presetStrength,
              min: 0,
              max: 100,
              divisions: 20,
              formatter: (v) => '${v.round()}%',
              onChanged: session.hasImage && !session.busy
                  ? (v) {
                      setState(() => _presetStrength = v);
                      final d = _activePresetDescriptor;
                      if (d == null) return;
                      session.applyFilter(
                        label: 'Preview',
                        descriptor: d,
                        livePreview: true,
                        fromBase: true,
                      );
                    }
                  : null,
              onChangeEnd: session.hasImage && !session.busy
                  ? (_) {
                      final d = _activePresetDescriptor;
                      if (d == null) return;
                      session.cancelDebounced();
                      session.applyFilter(
                        label: 'Preset',
                        descriptor: d,
                        saveUndo: true,
                        fromBase: true,
                      );
                    }
                  : null,
              enabled: session.hasImage && !session.busy,
            ),
          ],
          const SizedBox(height: LuminaTokens.space3),
          LuminaFilterStrip(
            labels: moodLabels,
            selectedIndex: _selectedMood,
            enabled: session.hasImage && !session.busy,
            onSelected: (i) {
              setState(() => _selectedMood = i);
              unawaited(
                session.setMoodFilter(
                  preset: i == 0 ? null : _moods[i - 1],
                  strength: _moodStrength / 100,
                  commit: true,
                ),
              );
            },
          ),
          if (_selectedMood > 0) ...[
            const SizedBox(height: LuminaTokens.space3),
            ValueChipSlider(
              label: 'Intensity',
              value: _moodStrength,
              min: 0,
              max: 100,
              divisions: 20,
              formatter: (v) => '${v.round()}%',
              onChanged: session.hasImage && !session.busy
                  ? (v) {
                      setState(() => _moodStrength = v);
                      final p = _activeMoodPreset;
                      if (p == null) return;
                      unawaited(
                        session.setMoodFilter(
                          preset: p,
                          strength: _moodStrength / 100,
                          livePreview: true,
                        ),
                      );
                    }
                  : null,
              onChangeEnd: session.hasImage && !session.busy
                  ? (_) {
                      final p = _activeMoodPreset;
                      if (p == null) return;
                      unawaited(
                        session.setMoodFilter(
                          preset: p,
                          strength: _moodStrength / 100,
                          commit: true,
                        ),
                      );
                    }
                  : null,
              enabled: session.hasImage && !session.busy,
            ),
          ],
        ],
      ),
    );
  }
}

class _PaintColorStrip extends StatefulWidget {
  const _PaintColorStrip({required this.session});

  final EditorSession session;

  @override
  State<_PaintColorStrip> createState() => _PaintColorStripState();
}

class _PaintColorStripState extends State<_PaintColorStrip> {
  EditorSession get s => widget.session;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: LuminaTokens.space3,
        vertical: LuminaTokens.space2,
      ),
      child: LuminaColorSwatchRow(
        swatchSize: 28,
        selected: s.paintColor,
        onSelected: (c) {
          s.paintColor = c;
          s.notifyLayerChanged();
          setState(() {});
        },
      ),
    );
  }
}

class _StickersTabStrip extends StatelessWidget {
  const _StickersTabStrip({
    required this.tabIndex,
    this.onTabChanged,
  });

  final int tabIndex;
  final ValueChanged<int>? onTabChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: LuminaTokens.space3,
        vertical: LuminaTokens.space2,
      ),
      child: ChipPillRow<int>(
        items: const [0, 1, 2],
        label: (i) => ['Emoji', 'Stickers', 'Text'][i],
        selected: tabIndex,
        onSelected: onTabChanged,
      ),
    );
  }
}

