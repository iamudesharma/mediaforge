import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rust_image/src/rust_image_editor.dart';

import '../crop_controller.dart';
import '../editor_session.dart';
import '../panels/tool_panels.dart';
import '../services/filter_descriptor.dart';
import '../services/mood_filter_names.dart';
import '../services/rust_worker.dart';
import '../theme/lumina_tokens.dart';
import '../widgets/control_widgets.dart';
import '../widgets/lumina_color_picker.dart';

/// Primary tool controls shown above the bottom nav (Instagram-style strip).
class ToolContextStrip extends StatelessWidget {
  const ToolContextStrip({
    super.key,
    required this.tool,
    required this.session,
    this.cropController,
    this.stickersTabIndex = 0,
    this.onStickersTabChanged,
    this.adjustKind = AdjustControlKind.brightness,
    this.onAdjustKindChanged,
  });

  final EditorTool tool;
  final EditorSession session;
  final CropController? cropController;
  final int stickersTabIndex;
  final ValueChanged<int>? onStickersTabChanged;
  final AdjustControlKind adjustKind;
  final ValueChanged<AdjustControlKind>? onAdjustKindChanged;

  @override
  Widget build(BuildContext context) {
    return switch (tool) {
        EditorTool.filters => _FiltersStrip(session: session),
        EditorTool.adjust => _AdjustStrip(
            selected: adjustKind,
            onSelected: onAdjustKindChanged,
          ),
        EditorTool.transform when cropController != null =>
          _TransformStrip(session: session, crop: cropController!),
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
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Presets',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 4),
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
          const SizedBox(height: 8),
          Text(
            'Mood grades',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 4),
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
        ],
      ),
    );
  }
}

class _AdjustStrip extends StatelessWidget {
  const _AdjustStrip({
    required this.selected,
    this.onSelected,
  });

  final AdjustControlKind selected;
  final ValueChanged<AdjustControlKind>? onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: ActionChipRow<AdjustControlKind>(
        horizontal: true,
        items: AdjustControlKind.values,
        label: (k) => k.stripLabel,
        selected: selected,
        onSelected: onSelected ?? (_) {},
      ),
    );
  }
}

class _TransformStrip extends StatelessWidget {
  const _TransformStrip({required this.session, required this.crop});

  final EditorSession session;
  final CropController crop;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: crop,
      builder: (context, _) {
        final s = session;
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: ActionChipRow<CropAspect>(
                  horizontal: true,
                  items: CropAspect.values,
                  label: (a) => a.label,
                  selected: crop.aspect,
                  onSelected: s.busy ? (_) {} : crop.setAspect,
                ),
              ),
              IconButton(
                tooltip: 'Rotate 90° CCW',
                onPressed: s.hasImage && !s.busy
                    ? () => s.runBytes(
                          'Rotate',
                          (input) => RustWorker.bytesTransform(
                            bytes: input,
                            op: 'rotate',
                            params: {
                              'rotation': Rotation.rotate270.index,
                              'format': s.outputFormat.index,
                              'quality': s.quality,
                            },
                          ),
                        )
                    : null,
                icon: const Icon(Icons.rotate_left, size: 22),
              ),
              IconButton(
                tooltip: 'Rotate 90° CW',
                onPressed: s.hasImage && !s.busy
                    ? () => s.runBytes(
                          'Rotate',
                          (input) => RustWorker.bytesTransform(
                            bytes: input,
                            op: 'rotate',
                            params: {
                              'rotation': Rotation.rotate90.index,
                              'format': s.outputFormat.index,
                              'quality': s.quality,
                            },
                          ),
                        )
                    : null,
                icon: const Icon(Icons.rotate_right, size: 22),
              ),
            ],
          ),
        );
      },
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
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          for (final e in [(0, 'Emoji'), (1, 'Stickers'), (2, 'Text')])
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(e.$2),
                selected: tabIndex == e.$1,
                onSelected: onTabChanged == null
                    ? null
                    : (_) => onTabChanged!(e.$1),
              ),
            ),
        ],
      ),
    );
  }
}
