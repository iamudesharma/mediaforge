import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_forge_editor/src/image_forge_editor.dart';

import '../crop_controller.dart';
import '../draw_placement.dart';
import '../editor_session.dart';
import '../models/layer_transform.dart';
import '../models/overlay_layer.dart';
import '../overlay_placement.dart';
import '../image_forge_editor_config.dart';
import '../services/filter_descriptor.dart';
import '../services/mood_filter_names.dart';
import '../services/image_source_picker.dart';
import '../services/rust_worker.dart';
import '../theme/lumina_tokens.dart';
import '../layout/mobile_tool_sheet.dart';
import '../widgets/control_widgets.dart';
import '../widgets/editor_animations.dart';
import 'blank_canvas_sheet.dart';
import 'layers_panel.dart';
import 'paint_panel.dart';
import 'beauty_panel.dart';
import 'stickers_panel.dart';

enum EditorTool {
  import,
  transform,
  filters,
  beauty,
  adjust,
  paint,
  stickers,
  export_,
  draw,
  layers,
  overlay,
  advanced,
}

extension EditorToolX on EditorTool {
  String get label => switch (this) {
        EditorTool.import => 'Import',
        EditorTool.transform => 'Transform',
        EditorTool.filters => 'Filters',
        EditorTool.beauty => 'Beauty',
        EditorTool.adjust => 'Adjust',
        EditorTool.paint => 'Paint',
        EditorTool.stickers => 'Stickers',
        EditorTool.export_ => 'Export',
        EditorTool.draw => 'Shapes',
        EditorTool.layers => 'Layers',
        EditorTool.overlay => 'Overlay',
        EditorTool.advanced => 'Advanced',
      };

  /// Lumina bottom-nav label (DESIGN.md).
  String get mobileNavLabel => switch (this) {
        EditorTool.import => 'Import',
        EditorTool.transform => 'Crop',
        EditorTool.filters => 'Filters',
        EditorTool.beauty => 'Beauty',
        EditorTool.adjust => 'Adjust',
        EditorTool.paint => 'Paint',
        EditorTool.stickers => 'Stickers',
        EditorTool.export_ => 'Export',
        EditorTool.draw => 'Shapes',
        EditorTool.layers => 'Layers',
        EditorTool.overlay => 'Overlay',
        EditorTool.advanced => 'Advanced',
      };

  IconData get icon => switch (this) {
        EditorTool.import => Icons.photo_library_outlined,
        EditorTool.transform => Icons.crop_rotate,
        EditorTool.filters => Icons.auto_awesome,
        EditorTool.beauty => Icons.face_retouching_natural,
        EditorTool.adjust => Icons.tune,
        EditorTool.paint => Icons.brush_outlined,
        EditorTool.stickers => Icons.emoji_emotions_outlined,
        EditorTool.export_ => Icons.save_alt_outlined,
        EditorTool.draw => Icons.interests_outlined,
        EditorTool.layers => Icons.layers_outlined,
        EditorTool.overlay => Icons.image_outlined,
        EditorTool.advanced => Icons.memory_outlined,
      };

  /// Lumina nav icons (reference screens).
  IconData get navIcon => switch (this) {
        EditorTool.import => Icons.photo_library_outlined,
        EditorTool.transform => Icons.crop,
        EditorTool.filters => Icons.photo_filter_outlined,
        EditorTool.beauty => Icons.face_retouching_natural,
        EditorTool.adjust => Icons.tune,
        EditorTool.paint => Icons.brush_outlined,
        EditorTool.stickers => Icons.emoji_emotions_outlined,
        EditorTool.export_ => Icons.save_alt_outlined,
        EditorTool.draw => Icons.interests_outlined,
        EditorTool.layers => Icons.layers_outlined,
        EditorTool.overlay => Icons.image_outlined,
        EditorTool.advanced => Icons.equalizer,
      };

  /// Export uses top-bar pill on mobile; import is in bottom nav.
  bool get showInBottomNav => this != EditorTool.export_;

  /// Layers live on the canvas (top-left) on phone — not in bottom nav.
  bool get showInMobileBottomNav =>
      showInBottomNav && this != EditorTool.layers;

  /// Context strip above bottom nav (filters, adjust, crop, paint, stickers).
  bool get hasMobileContextStrip => switch (this) {
        EditorTool.filters ||
        EditorTool.beauty ||
        EditorTool.adjust ||
        EditorTool.transform ||
        EditorTool.paint ||
        EditorTool.stickers =>
          true,
        _ => false,
      };
}

class ToolPanelHost extends StatelessWidget {
  const ToolPanelHost({
    super.key,
    required this.tool,
    required this.session,
    required this.config,
    this.drawPlacement,
    this.cropController,
    this.overlayPlacement,
    this.scrollController,
    this.compact = false,
    this.stripHostedExternally = false,
    this.stickersTabIndex = 0,
    this.onStickersTabChanged,
    this.onBlankCanvas,
    this.selectedAdjustKind = AdjustControlKind.brightness,
    this.onAdjustKindChanged,
  });

  final EditorTool tool;
  final EditorSession session;
  final RustImageEditorConfig config;
  final DrawPlacementController? drawPlacement;
  final CropController? cropController;
  final OverlayPlacementController? overlayPlacement;
  final ScrollController? scrollController;
  final bool compact;
  final bool stripHostedExternally;
  final int stickersTabIndex;
  final ValueChanged<int>? onStickersTabChanged;
  final VoidCallback? onBlankCanvas;
  final AdjustControlKind selectedAdjustKind;
  final ValueChanged<AdjustControlKind>? onAdjustKindChanged;

  Widget _panel() => switch (tool) {
        EditorTool.import => ImportPanel(
            session: session,
            allowBlankCanvas: config.allowBlankCanvas,
            onBlankCanvas: onBlankCanvas,
          ),
        EditorTool.transform => TransformPanel(
            session: session,
            crop: cropController!,
            stripHostedExternally: stripHostedExternally,
          ),
        EditorTool.filters => FiltersPanel(
            session: session,
            stripHostedExternally: stripHostedExternally,
          ),
        EditorTool.beauty => BeautyPanel(
            session: session,
            stripHostedExternally: stripHostedExternally,
          ),
        EditorTool.adjust => AdjustPanel(
            session: session,
            selectedKind: selectedAdjustKind,
            onSelectedKindChanged: onAdjustKindChanged,
            compactStripMode: stripHostedExternally,
          ),
        EditorTool.paint => PaintPanel(
            session: session,
            scrollController: scrollController,
            stripHostedExternally: stripHostedExternally,
          ),
        EditorTool.stickers => StickersPanel(
            session: session,
            scrollController: scrollController,
            stripHostedExternally: stripHostedExternally,
            tabIndex: stickersTabIndex,
            onTabChanged: onStickersTabChanged,
          ),
        EditorTool.export_ => ExportPanel(session: session, config: config),
        EditorTool.draw => ShapesPanel(
            session: session,
            placement: drawPlacement!,
          ),
        EditorTool.layers => LayersPanel(session: session, compact: compact),
        EditorTool.overlay => OverlayPanel(
            session: session,
            placement: overlayPlacement!,
          ),
        EditorTool.advanced => AdvancedPanel(session: session),
      };

  @override
  Widget build(BuildContext context) {
    if (compact) {
      // MobileToolSheet owns the scroll view (DraggableScrollableSheet controller).
      return AnimatedPanelSwitcher(
        switchKey: tool,
        child: _panel(),
      );
    }

    final padding = const EdgeInsets.fromLTRB(16, 8, 16, 24);
    return AnimatedPanelSwitcher(
      switchKey: tool,
      child: SingleChildScrollView(
        controller: scrollController,
        primary: scrollController == null,
        padding: padding,
        physics: const ClampingScrollPhysics(),
        child: _panel(),
      ),
    );
  }
}

// --- Import ---

class ImportPanel extends StatelessWidget {
  const ImportPanel({
    super.key,
    required this.session,
    this.allowBlankCanvas = true,
    this.onBlankCanvas,
  });

  final EditorSession session;
  final bool allowBlankCanvas;
  final VoidCallback? onBlankCanvas;

  Future<void> _pickFile(BuildContext context) async {
    try {
      final bytes = await ImageSourcePicker.pickImageBytes();
      if (bytes == null) return;
      if (!context.mounted) return;
      await session.loadSource(bytes);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open image: $e')),
      );
    }
  }

  Future<void> _pickCamera(BuildContext context) async {
    try {
      final bytes = await ImageSourcePicker.pickFromCamera();
      if (bytes == null) return;
      if (!context.mounted) return;
      await session.loadSource(bytes);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Camera unavailable: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final gpu = session.gpuInfo;
    final isDesktop = ImageSourcePicker.isDesktop;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          'Source',
          subtitle: isDesktop
              ? 'Opens the native file picker (macOS sandbox enabled)'
              : 'Gallery or camera — edits update preview live',
        ),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: session.busy ? null : () => _pickFile(context),
                icon: Icon(isDesktop ? Icons.folder_open : Icons.photo_library),
                label: Text(isDesktop ? 'Open file…' : 'Gallery'),
              ),
            ),
            if (ImageSourcePicker.supportsCamera) ...[
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: session.busy ? null : () => _pickCamera(context),
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Camera'),
                ),
              ),
            ],
          ],
        ),
        if (allowBlankCanvas) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: session.busy
                ? null
                : () {
                    if (onBlankCanvas != null) {
                      onBlankCanvas!();
                    } else {
                      BlankCanvasSheet.show(context, session);
                    }
                  },
            icon: const Icon(Icons.crop_portrait_outlined),
            label: const Text('Create blank canvas'),
          ),
        ],
        const SizedBox(height: 16),
        const SectionHeader('Image info'),
        _InfoTile(label: 'Dimensions', value: session.dimensionsLabel),
        _InfoTile(label: 'File size', value: session.sizeLabel),
        if (session.lastDuration != null)
          _InfoTile(
            label: 'Last op',
            value: '${session.lastDuration!.inMilliseconds} ms',
          ),
        if (gpu != null) ...[
          const SizedBox(height: 8),
          _InfoTile(
            label: 'GPU compute',
            value: gpu.available ? '${gpu.api} · ${gpu.device}' : 'Unavailable (CPU only)',
          ),
        ],
        const SizedBox(height: 16),
        PrimaryActionButton(
          icon: Icons.refresh,
          label: 'Reset to original',
          enabled: session.hasImage && !session.busy,
          onPressed: session.resetToSource,
        ),
        const SizedBox(height: 8),
        PrimaryActionButton(
          icon: Icons.search,
          label: 'Re-probe metadata',
          enabled: session.hasImage && !session.busy,
          onPressed: () async {
            final b = session.displayBytes;
            if (b == null) return;
            session.reprobe();
          },
        ),
      ],
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: Theme.of(context).textTheme.bodySmall),
      subtitle: Text(value),
    );
  }
}

// --- Transform ---

class TransformPanel extends StatefulWidget {
  const TransformPanel({
    super.key,
    required this.session,
    required this.crop,
    this.stripHostedExternally = false,
  });

  final EditorSession session;
  final CropController crop;
  final bool stripHostedExternally;

  @override
  State<TransformPanel> createState() => _TransformPanelState();
}

class _TransformPanelState extends State<TransformPanel> {
  int _width = 1024;
  int _height = 1024;
  int _thumbEdge = 512;
  ResizeAlgorithm _algorithm = ResizeAlgorithm.lanczos3;
  int? _lastInfoWidth;

  EditorSession get s => widget.session;
  CropController get c => widget.crop;

  void _maybeSyncFromInfo() {
    final info = s.imageInfo;
    if (info == null || info.width == _lastInfoWidth) return;
    _lastInfoWidth = info.width;
    _width = info.width;
    _height = info.height;
  }

  @override
  void initState() {
    super.initState();
    c.addListener(_onCropChanged);
  }

  @override
  void dispose() {
    c.removeListener(_onCropChanged);
    super.dispose();
  }

  void _onCropChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    _maybeSyncFromInfo();

    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.stripHostedExternally) ...[
          ActionChipRow<CropAspect>(
            horizontal: true,
            items: CropAspect.values,
            label: (a) => a.label,
            selected: c.aspect,
            onSelected: s.busy ? (_) {} : c.setAspect,
          ),
          const SizedBox(height: LuminaTokens.padMd),
        ],
        const SectionHeader('Resize'),
        LabeledSlider(
          label: 'Width',
          value: _width.toDouble(),
          min: 64,
          max: 4096,
          divisions: 40,
          display: '$_width px',
          onChanged: s.busy ? null : (v) => setState(() => _width = v.round()),
        ),
        LabeledSlider(
          label: 'Height',
          value: _height.toDouble(),
          min: 64,
          max: 4096,
          divisions: 40,
          display: '$_height px',
          onChanged: s.busy ? null : (v) => setState(() => _height = v.round()),
        ),
        const SectionHeader('Algorithm'),
        ActionChipRow<ResizeAlgorithm>(
          items: ResizeAlgorithm.values,
          label: (a) => a.name,
          selected: _algorithm,
          onSelected: s.busy ? (_) {} : (v) => setState(() => _algorithm = v),
        ),
        const SizedBox(height: 8),
        PrimaryActionButton(
          icon: Icons.aspect_ratio,
          label: 'Apply resize',
          enabled: s.hasImage && !s.blocking,
          onPressed: () => s.runBytes(
            'Resize',
            (input) => RustWorker.bytesTransform(
              bytes: input,
              op: 'resize',
              params: {
                'width': _width,
                'height': _height,
                'algorithm': _algorithm.index,
                'format': s.outputFormat.index,
                'quality': s.quality,
                'backend': s.backend.index,
              },
            ),
          ),
        ),
        const SizedBox(height: 16),
        const SectionHeader('Thumbnail'),
        LabeledSlider(
          label: 'Max edge',
          value: _thumbEdge.toDouble(),
          min: 128,
          max: 2048,
          divisions: 30,
          display: '$_thumbEdge px',
          onChanged: s.busy ? null : (v) => setState(() => _thumbEdge = v.round()),
        ),
        PrimaryActionButton(
          icon: Icons.photo_size_select_small,
          label: 'Create thumbnail',
          enabled: s.hasImage && !s.blocking,
          onPressed: () => s.runBytes(
            'Thumbnail',
            (input) => RustWorker.bytesTransform(
              bytes: input,
              op: 'thumbnail',
              params: {
                'maxEdge': _thumbEdge,
                'format': s.outputFormat.index,
                'quality': s.quality,
                'backend': s.backend.index,
              },
            ),
          ),
        ),
        const SizedBox(height: 16),
        const SectionHeader(
          'Crop',
          subtitle: 'Adjust on preview, then tap Done (top) or Apply crop',
        ),
        LabeledSlider(
          label: 'X',
          value: c.cropX.toDouble(),
          min: 0,
          max: (s.imageInfo?.width ?? 1000).toDouble(),
          divisions: 40,
          display: '${c.cropX}',
          onChanged: s.busy
              ? null
              : (v) => c.setCropRect(v.round(), c.cropY, c.cropW, c.cropH),
        ),
        LabeledSlider(
          label: 'Y',
          value: c.cropY.toDouble(),
          min: 0,
          max: (s.imageInfo?.height ?? 1000).toDouble(),
          divisions: 40,
          display: '${c.cropY}',
          onChanged: s.busy
              ? null
              : (v) => c.setCropRect(c.cropX, v.round(), c.cropW, c.cropH),
        ),
        LabeledSlider(
          label: 'Width',
          value: c.cropW.toDouble(),
          min: 32,
          max: (s.imageInfo?.width ?? 1000).toDouble(),
          divisions: 40,
          display: '${c.cropW}',
          onChanged: s.busy
              ? null
              : (v) => c.setCropRect(c.cropX, c.cropY, v.round(), c.cropH),
        ),
        LabeledSlider(
          label: 'Height',
          value: c.cropH.toDouble(),
          min: 32,
          max: (s.imageInfo?.height ?? 1000).toDouble(),
          divisions: 40,
          display: '${c.cropH}',
          onChanged: s.busy
              ? null
              : (v) => c.setCropRect(c.cropX, c.cropY, c.cropW, v.round()),
        ),
        PrimaryActionButton(
          icon: Icons.crop,
          label: 'Apply crop',
          enabled: s.hasImage && !s.blocking,
          onPressed: () => s.applyCrop(crop: c),
        ),
        const SizedBox(height: 16),
        const SectionHeader('Straighten', subtitle: 'Live preview on canvas · commits rotation'),
        LabeledSlider(
          label: 'Angle',
          value: c.straightenDegrees,
          min: -15,
          max: 15,
          divisions: 60,
          display: '${c.straightenDegrees.toStringAsFixed(1)}°',
          onChanged: s.busy ? null : (v) => c.setStraightenDegrees(v),
        ),
        PrimaryActionButton(
          icon: Icons.check,
          label: 'Apply straighten',
          enabled: s.hasImage && !s.blocking && c.straightenDegrees.abs() > 0.05,
          onPressed: () => s.applyStraighten(crop: c),
        ),
        const SizedBox(height: 16),
        const SectionHeader('Rotate & flip'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final r in Rotation.values)
              FilledButton.tonal(
                onPressed: s.hasImage && !s.busy
                    ? () => s.runBytes(
                          'Rotate',
                          (input) => RustWorker.bytesTransform(
                            bytes: input,
                            op: 'rotate',
                            params: {
                              'rotation': r.index,
                              'format': s.outputFormat.index,
                              'quality': s.quality,
                            },
                          ),
                        )
                    : null,
                child: Text(_rotationLabel(r)),
              ),
          ],
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: s.hasImage && !s.busy
              ? () => s.runBytes(
                    'Fix EXIF',
                    (input) => RustWorker.bytesTransform(
                      bytes: input,
                      op: 'fixExif',
                      params: {
                        'format': s.outputFormat.index,
                        'quality': s.quality,
                      },
                    ),
                  )
              : null,
          icon: const Icon(Icons.screen_rotation),
          label: const Text('Fix EXIF orientation'),
        ),
      ],
    );
      },
    );
  }

  String _rotationLabel(Rotation r) => switch (r) {
        Rotation.rotate90 => '90°',
        Rotation.rotate180 => '180°',
        Rotation.rotate270 => '270°',
        Rotation.flipHorizontal => 'Flip H',
        Rotation.flipVertical => 'Flip V',
      };
}

// --- Filters ---

class FiltersPanel extends StatefulWidget {
  const FiltersPanel({
    super.key,
    required this.session,
    this.stripHostedExternally = false,
  });

  final EditorSession session;
  final bool stripHostedExternally;

  @override
  State<FiltersPanel> createState() => _FiltersPanelState();
}

class _FiltersPanelState extends State<FiltersPanel> {
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

  @override
  Widget build(BuildContext context) {
    final presetLabels = ['Original', ..._presets.map(_presetName)];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.stripHostedExternally) ...[
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
            const SizedBox(height: LuminaTokens.padMd),
            LabeledSlider(
              label: 'Filter intensity',
              value: _presetStrength,
              min: 0,
              max: 100,
              divisions: 20,
              display: '${_presetStrength.round()}%',
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
            ),
          ],
          const SizedBox(height: LuminaTokens.padMd),
          const SectionHeader('Mood grades'),
          LuminaFilterStrip(
            labels: [
              'Original',
              ..._moods.map(moodFilterDisplayName),
            ],
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
            const SizedBox(height: LuminaTokens.padMd),
            LabeledSlider(
              label: 'Mood intensity',
              value: _moodStrength,
              min: 0,
              max: 100,
              divisions: 20,
              display: '${_moodStrength.round()}%',
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
            ),
          ],
          const SizedBox(height: LuminaTokens.padMd),
        ],
        const SectionHeader('Effects'),
        _EffectButton(
          session: session,
          label: 'Blur',
          icon: Icons.blur_on,
          filter: const ImageFilter.blur(radius: 4),
        ),
        _EffectButton(
          session: session,
          label: 'Sharpen',
          icon: Icons.details,
          filter: const ImageFilter.sharpen(),
        ),
        _EffectButton(
          session: session,
          label: 'Oil paint',
          icon: Icons.brush,
          filter: const ImageFilter.oil(radius: 4, intensity: 120),
        ),
        _EffectButton(
          session: session,
          label: 'Frosted glass',
          icon: Icons.texture,
          filter: const ImageFilter.frostedGlass(),
        ),
        _EffectButton(
          session: session,
          label: 'Pixelize',
          icon: Icons.grid_on,
          filter: const ImageFilter.pixelize(size: 8),
        ),
        _EffectButton(
          session: session,
          label: 'Solarize',
          icon: Icons.wb_sunny_outlined,
          filter: const ImageFilter.solarize(),
        ),
      ],
    );
  }

  static String _presetName(FilterPreset p) {
    final n = p.name;
    return n[0].toUpperCase() + n.substring(1);
  }
}

class _EffectButton extends StatelessWidget {
  const _EffectButton({
    required this.session,
    required this.label,
    required this.icon,
    required this.filter,
  });

  final EditorSession session;
  final String label;
  final IconData icon;
  final ImageFilter filter;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: OutlinedButton.icon(
        onPressed: session.hasImage
            ? () => session.applyFilter(
                  label: label,
                  descriptor: FilterDescriptor.fromImageFilter(filter),
                )
            : null,
        icon: Icon(icon),
        label: Text(label),
      ),
    );
  }
}

// --- Adjust ---

/// Primary adjust controls shown in the mobile context strip.
enum AdjustControlKind {
  brightness,
  contrast,
  saturation,
  hue,
  warmth,
}

extension AdjustControlKindX on AdjustControlKind {
  String get stripLabel => switch (this) {
        AdjustControlKind.brightness => 'Bright',
        AdjustControlKind.contrast => 'Contrast',
        AdjustControlKind.saturation => 'Saturate',
        AdjustControlKind.hue => 'Hue',
        AdjustControlKind.warmth => 'Warmth',
      };

  String get panelTitle => switch (this) {
        AdjustControlKind.brightness => 'Brightness',
        AdjustControlKind.contrast => 'Contrast',
        AdjustControlKind.saturation => 'Saturation',
        AdjustControlKind.hue => 'Hue rotate',
        AdjustControlKind.warmth => 'Warmth',
      };
}

class AdjustPanel extends StatefulWidget {
  const AdjustPanel({
    super.key,
    required this.session,
    this.selectedKind = AdjustControlKind.brightness,
    this.onSelectedKindChanged,
    this.compactStripMode = false,
  });

  final EditorSession session;
  final AdjustControlKind selectedKind;
  final ValueChanged<AdjustControlKind>? onSelectedKindChanged;
  final bool compactStripMode;

  @override
  State<AdjustPanel> createState() => _AdjustPanelState();
}

class _AdjustPanelState extends State<AdjustPanel> {
  double _brightness = 20;
  double _contrast = 1.1;
  double _saturation = 1.2;
  double _hue = 30;
  double _warmth = 0;
  double _fade = 0;
  double _vignette = 0;
  double _highlights = 0;
  double _shadows = 0;
  double _structure = 0;
  bool _showMoreAdjustments = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    if (widget.compactStripMode) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.selectedKind.panelTitle,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: LuminaTokens.onSurface,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            'Live preview while dragging · commits on release',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: LuminaTokens.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: LuminaTokens.padSm),
          _sliderForKind(widget.selectedKind, s),
          if (_showMoreAdjustments) ...[
            const SizedBox(height: LuminaTokens.padSm),
            ..._moreSliders(s),
          ] else
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() => _showMoreAdjustments = true),
                child: const Text('More adjustments'),
              ),
            ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(
          'Tonal',
          subtitle: 'Live preview while dragging · commits on release',
        ),
        LabeledSlider(
          label: 'Brightness',
          value: _brightness,
          min: -100,
          max: 100,
          divisions: 40,
          display: _brightness.round().toString(),
          onChanged: s.hasImage
              ? (v) {
                  setState(() => _brightness = v);
                  _preview(s, FilterDescriptor.brightness(amount: v.round()));
                }
              : null,
          onChangeEnd: s.hasImage
              ? (_) => _commit(s, FilterDescriptor.brightness(amount: _brightness.round()))
              : null,
        ),
        LabeledSlider(
          label: 'Contrast',
          value: _contrast,
          min: 0.2,
          max: 2.5,
          divisions: 23,
          display: _contrast.toStringAsFixed(2),
          onChanged: s.hasImage
              ? (v) {
                  setState(() => _contrast = v);
                  _preview(s, FilterDescriptor.contrast(amount: v));
                }
              : null,
          onChangeEnd: s.hasImage
              ? (_) => _commit(s, FilterDescriptor.contrast(amount: _contrast))
              : null,
        ),
        LabeledSlider(
          label: 'Saturation',
          value: _saturation,
          min: 0,
          max: 2.5,
          divisions: 25,
          display: _saturation.toStringAsFixed(2),
          onChanged: s.hasImage
              ? (v) {
                  setState(() => _saturation = v);
                  _preview(s, FilterDescriptor.saturation(amount: v));
                }
              : null,
          onChangeEnd: s.hasImage
              ? (_) => _commit(s, FilterDescriptor.saturation(amount: _saturation))
              : null,
        ),
        LabeledSlider(
          label: 'Hue rotate',
          value: _hue,
          min: -180,
          max: 180,
          divisions: 36,
          display: '${_hue.round()}°',
          onChanged: s.hasImage
              ? (v) {
                  setState(() => _hue = v);
                  _preview(s, FilterDescriptor.hueRotate(degrees: v));
                }
              : null,
          onChangeEnd: s.hasImage
              ? (_) => _commit(s, FilterDescriptor.hueRotate(degrees: _hue))
              : null,
        ),
        const SizedBox(height: LuminaTokens.padMd),
        const SectionHeader('Color & mood'),
        LabeledSlider(
          label: 'Warmth',
          value: _warmth,
          min: -100,
          max: 100,
          divisions: 40,
          display: _warmth.round().toString(),
          onChanged: s.hasImage
              ? (v) {
                  setState(() => _warmth = v);
                  _preview(s, FilterDescriptor.warmth(amount: v));
                }
              : null,
          onChangeEnd: s.hasImage
              ? (_) => _commit(s, FilterDescriptor.warmth(amount: _warmth))
              : null,
        ),
        LabeledSlider(
          label: 'Fade',
          value: _fade,
          min: 0,
          max: 1,
          divisions: 20,
          display: _fade.toStringAsFixed(2),
          onChanged: s.hasImage
              ? (v) {
                  setState(() => _fade = v);
                  _preview(s, FilterDescriptor.fade(amount: v));
                }
              : null,
          onChangeEnd: s.hasImage
              ? (_) => _commit(s, FilterDescriptor.fade(amount: _fade))
              : null,
        ),
        LabeledSlider(
          label: 'Vignette',
          value: _vignette,
          min: 0,
          max: 1,
          divisions: 20,
          display: _vignette.toStringAsFixed(2),
          onChanged: s.hasImage
              ? (v) {
                  setState(() => _vignette = v);
                  _preview(s, FilterDescriptor.vignette(amount: v));
                }
              : null,
          onChangeEnd: s.hasImage
              ? (_) => _commit(s, FilterDescriptor.vignette(amount: _vignette))
              : null,
        ),
        const SizedBox(height: LuminaTokens.padMd),
        const SectionHeader('Tone depth', subtitle: 'Highlights, shadows, clarity'),
        LabeledSlider(
          label: 'Highlights',
          value: _highlights,
          min: -100,
          max: 100,
          divisions: 40,
          display: _highlights.round().toString(),
          onChanged: s.hasImage
              ? (v) {
                  setState(() => _highlights = v);
                  _preview(s, FilterDescriptor.highlights(amount: v));
                }
              : null,
          onChangeEnd: s.hasImage
              ? (_) => _commit(s, FilterDescriptor.highlights(amount: _highlights))
              : null,
        ),
        LabeledSlider(
          label: 'Shadows',
          value: _shadows,
          min: -100,
          max: 100,
          divisions: 40,
          display: _shadows.round().toString(),
          onChanged: s.hasImage
              ? (v) {
                  setState(() => _shadows = v);
                  _preview(s, FilterDescriptor.shadows(amount: v));
                }
              : null,
          onChangeEnd: s.hasImage
              ? (_) => _commit(s, FilterDescriptor.shadows(amount: _shadows))
              : null,
        ),
        LabeledSlider(
          label: 'Structure',
          value: _structure,
          min: -100,
          max: 100,
          divisions: 40,
          display: _structure.round().toString(),
          onChanged: s.hasImage
              ? (v) {
                  setState(() => _structure = v);
                  _preview(s, FilterDescriptor.structure(amount: v));
                }
              : null,
          onChangeEnd: s.hasImage
              ? (_) => _commit(s, FilterDescriptor.structure(amount: _structure))
              : null,
        ),
      ],
    );
  }

  Widget _sliderForKind(AdjustControlKind kind, EditorSession s) {
    return switch (kind) {
      AdjustControlKind.brightness => LabeledSlider(
          label: 'Brightness',
          value: _brightness,
          min: -100,
          max: 100,
          divisions: 40,
          display: _brightness.round().toString(),
          onChanged: s.hasImage
              ? (v) {
                  setState(() => _brightness = v);
                  _preview(s, FilterDescriptor.brightness(amount: v.round()));
                }
              : null,
          onChangeEnd: s.hasImage
              ? (_) => _commit(s, FilterDescriptor.brightness(amount: _brightness.round()))
              : null,
        ),
      AdjustControlKind.contrast => LabeledSlider(
          label: 'Contrast',
          value: _contrast,
          min: 0.2,
          max: 2.5,
          divisions: 23,
          display: _contrast.toStringAsFixed(2),
          onChanged: s.hasImage
              ? (v) {
                  setState(() => _contrast = v);
                  _preview(s, FilterDescriptor.contrast(amount: v));
                }
              : null,
          onChangeEnd: s.hasImage
              ? (_) => _commit(s, FilterDescriptor.contrast(amount: _contrast))
              : null,
        ),
      AdjustControlKind.saturation => LabeledSlider(
          label: 'Saturation',
          value: _saturation,
          min: 0,
          max: 2.5,
          divisions: 25,
          display: _saturation.toStringAsFixed(2),
          onChanged: s.hasImage
              ? (v) {
                  setState(() => _saturation = v);
                  _preview(s, FilterDescriptor.saturation(amount: v));
                }
              : null,
          onChangeEnd: s.hasImage
              ? (_) => _commit(s, FilterDescriptor.saturation(amount: _saturation))
              : null,
        ),
      AdjustControlKind.hue => LabeledSlider(
          label: 'Hue rotate',
          value: _hue,
          min: -180,
          max: 180,
          divisions: 36,
          display: '${_hue.round()}°',
          onChanged: s.hasImage
              ? (v) {
                  setState(() => _hue = v);
                  _preview(s, FilterDescriptor.hueRotate(degrees: v));
                }
              : null,
          onChangeEnd: s.hasImage
              ? (_) => _commit(s, FilterDescriptor.hueRotate(degrees: _hue))
              : null,
        ),
      AdjustControlKind.warmth => LabeledSlider(
          label: 'Warmth',
          value: _warmth,
          min: -100,
          max: 100,
          divisions: 40,
          display: _warmth.round().toString(),
          onChanged: s.hasImage
              ? (v) {
                  setState(() => _warmth = v);
                  _preview(s, FilterDescriptor.warmth(amount: v));
                }
              : null,
          onChangeEnd: s.hasImage
              ? (_) => _commit(s, FilterDescriptor.warmth(amount: _warmth))
              : null,
        ),
    };
  }

  List<Widget> _moreSliders(EditorSession s) {
    return [
      LabeledSlider(
        label: 'Fade',
        value: _fade,
        min: 0,
        max: 1,
        divisions: 20,
        display: _fade.toStringAsFixed(2),
        onChanged: s.hasImage
            ? (v) {
                setState(() => _fade = v);
                _preview(s, FilterDescriptor.fade(amount: v));
              }
            : null,
        onChangeEnd: s.hasImage
            ? (_) => _commit(s, FilterDescriptor.fade(amount: _fade))
            : null,
      ),
      LabeledSlider(
        label: 'Vignette',
        value: _vignette,
        min: 0,
        max: 1,
        divisions: 20,
        display: _vignette.toStringAsFixed(2),
        onChanged: s.hasImage
            ? (v) {
                setState(() => _vignette = v);
                _preview(s, FilterDescriptor.vignette(amount: v));
              }
            : null,
        onChangeEnd: s.hasImage
            ? (_) => _commit(s, FilterDescriptor.vignette(amount: _vignette))
            : null,
      ),
      LabeledSlider(
        label: 'Highlights',
        value: _highlights,
        min: -100,
        max: 100,
        divisions: 40,
        display: _highlights.round().toString(),
        onChanged: s.hasImage
            ? (v) {
                setState(() => _highlights = v);
                _preview(s, FilterDescriptor.highlights(amount: v));
              }
            : null,
        onChangeEnd: s.hasImage
            ? (_) => _commit(s, FilterDescriptor.highlights(amount: _highlights))
            : null,
      ),
      LabeledSlider(
        label: 'Shadows',
        value: _shadows,
        min: -100,
        max: 100,
        divisions: 40,
        display: _shadows.round().toString(),
        onChanged: s.hasImage
            ? (v) {
                setState(() => _shadows = v);
                _preview(s, FilterDescriptor.shadows(amount: v));
              }
            : null,
        onChangeEnd: s.hasImage
            ? (_) => _commit(s, FilterDescriptor.shadows(amount: _shadows))
            : null,
      ),
      LabeledSlider(
        label: 'Structure',
        value: _structure,
        min: -100,
        max: 100,
        divisions: 40,
        display: _structure.round().toString(),
        onChanged: s.hasImage
            ? (v) {
                setState(() => _structure = v);
                _preview(s, FilterDescriptor.structure(amount: v));
              }
            : null,
        onChangeEnd: s.hasImage
            ? (_) => _commit(s, FilterDescriptor.structure(amount: _structure))
            : null,
      ),
    ];
  }

  void _preview(EditorSession session, FilterDescriptor descriptor) {
    session.applyFilter(
      label: 'Preview',
      descriptor: descriptor,
      livePreview: true,
      fromBase: true,
    );
  }

  void _commit(EditorSession session, FilterDescriptor descriptor) {
    session.cancelDebounced();
    session.applyFilter(
      label: 'Adjust',
      descriptor: descriptor,
      saveUndo: true,
      fromBase: true,
    );
  }
}

// --- Export / compress ---

class ExportPanel extends StatefulWidget {
  const ExportPanel({
    super.key,
    required this.session,
    required this.config,
  });

  final EditorSession session;
  final RustImageEditorConfig config;

  @override
  State<ExportPanel> createState() => _ExportPanelState();
}

class _ExportPanelState extends State<ExportPanel> {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.session.editorChromeListenable,
      builder: (context, _) {
        final s = widget.session;
        return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Output format'),
        ActionChipRow<OutputFormat>(
          items: OutputFormat.values,
          label: (f) => f.name.toUpperCase(),
          selected: s.outputFormat,
          onSelected: s.busy ? (_) {} : s.setOutputFormat,
        ),
        const SizedBox(height: 12),
        LabeledSlider(
          label: 'Quality',
          value: s.quality.toDouble(),
          min: 10,
          max: 100,
          divisions: 18,
          display: '${s.quality}',
          onChanged: s.busy ? null : (v) => s.setQuality(v.round()),
        ),
        const SizedBox(height: 8),
        PrimaryActionButton(
          icon: Icons.compress,
          label: 'Compress / re-encode',
          enabled: s.hasImage && !s.busy,
          onPressed: () => s.runBytes(
            'Compress',
            (input) => RustWorker.bytesTransform(
              bytes: input,
              op: 'compress',
              params: {
                'format': s.outputFormat.index,
                'quality': s.quality,
              },
            ),
          ),
        ),
        const SizedBox(height: 16),
        const SectionHeader('Processing backend'),
        ActionChipRow<ProcessingBackend>(
          items: ProcessingBackend.values,
          label: (b) => b.name,
          selected: s.backend,
          onSelected: s.busy ? (_) {} : s.setBackend,
        ),
        const SizedBox(height: 20),
        PrimaryActionButton(
          icon: Icons.check_circle_outline,
          label: 'Export image',
          enabled: s.hasImage && !s.busy,
          onPressed: () async {
            final messenger = ScaffoldMessenger.maybeOf(context);
            final msg = await s.exportAndSave(
              customSave: widget.config.onExport,
            );
            if (!context.mounted) return;
            messenger?.showSnackBar(SnackBar(content: Text(msg)));
          },
        ),
      ],
        );
      },
    );
  }
}

// --- Shapes (line + circle; captions use Stickers → Text) ---

class ShapesPanel extends StatefulWidget {
  const ShapesPanel({
    super.key,
    required this.session,
    required this.placement,
  });

  final EditorSession session;
  final DrawPlacementController placement;

  @override
  State<ShapesPanel> createState() => _ShapesPanelState();
}

class _ShapesPanelState extends State<ShapesPanel> {
  DrawPlacementController get p => widget.placement;
  EditorSession get s => widget.session;

  @override
  Widget build(BuildContext context) {
    final maxW = p.imageWidth.toDouble();
    final maxH = p.imageHeight.toDouble();

    return ListenableBuilder(
      listenable: p,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionHeader(
              'Place on image',
              subtitle: 'Drag on the preview (pan disabled). Pinch to zoom.',
            ),
            ActionChipRow<DrawPlaceKind>(
              items: DrawPlaceKind.values,
              label: (k) => switch (k) {
                DrawPlaceKind.line => 'Line',
                DrawPlaceKind.circle => 'Circle',
              },
              selected: p.kind,
              onSelected: p.setKind,
            ),
            const SizedBox(height: 12),
            ...switch (p.kind) {
              DrawPlaceKind.line => _lineControls(maxW, maxH),
              DrawPlaceKind.circle => _circleControls(maxW, maxH),
            },
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: s.busy ? null : _addArrowSticker,
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Add arrow sticker'),
            ),
            const SizedBox(height: 12),
            PrimaryActionButton(
              icon: Icons.check,
              label: 'Apply to image',
              enabled: s.hasImage && !s.blocking,
              onPressed: _apply,
            ),
          ],
        );
      },
    );
  }

  void _addArrowSticker() {
    final info = s.imageInfo;
    final cx = (info?.width ?? 400) / 2;
    final cy = (info?.height ?? 600) / 2;
    s.pushLayerUndo();
    s.layerStack.add(
      StickerLayer(
        id: newLayerId(),
        transform: LayerTransform(
          centerX: cx,
          centerY: cy,
          scale: 1.4,
        ),
        assetKey: 'arrow',
      ),
    );
    s.notifyLayerChanged();
  }

  List<Widget> _lineControls(double maxW, double maxH) {
    return [
      LabeledSlider(
        label: 'Start X',
        value: p.lineX0.toDouble(),
        min: 0,
        max: maxW,
        divisions: 40,
        display: '${p.lineX0}',
        onChanged: s.blocking ? null : (v) => p.setLineStart(v.round(), p.lineY0),
      ),
      LabeledSlider(
        label: 'Start Y',
        value: p.lineY0.toDouble(),
        min: 0,
        max: maxH,
        divisions: 40,
        display: '${p.lineY0}',
        onChanged: s.blocking ? null : (v) => p.setLineStart(p.lineX0, v.round()),
      ),
      LabeledSlider(
        label: 'End X',
        value: p.lineX1.toDouble(),
        min: 0,
        max: maxW,
        divisions: 40,
        display: '${p.lineX1}',
        onChanged: s.blocking ? null : (v) => p.setLineEnd(v.round(), p.lineY1),
      ),
      LabeledSlider(
        label: 'End Y',
        value: p.lineY1.toDouble(),
        min: 0,
        max: maxH,
        divisions: 40,
        display: '${p.lineY1}',
        onChanged: s.blocking ? null : (v) => p.setLineEnd(p.lineX1, v.round()),
      ),
    ];
  }

  List<Widget> _circleControls(double maxW, double maxH) {
    return [
      LabeledSlider(
        label: 'Center X',
        value: p.circleX.toDouble(),
        min: 0,
        max: maxW,
        divisions: 40,
        display: '${p.circleX}',
        onChanged: s.blocking ? null : (v) => p.setCircleCenter(v.round(), p.circleY),
      ),
      LabeledSlider(
        label: 'Center Y',
        value: p.circleY.toDouble(),
        min: 0,
        max: maxH,
        divisions: 40,
        display: '${p.circleY}',
        onChanged: s.blocking ? null : (v) => p.setCircleCenter(p.circleX, v.round()),
      ),
      LabeledSlider(
        label: 'Radius',
        value: p.circleRadius.toDouble(),
        min: 8,
        max: maxW / 2,
        divisions: 40,
        display: '${p.circleRadius}',
        onChanged: s.blocking ? null : (v) => p.setCircleRadius(v.round()),
      ),
    ];
  }

  void _apply() {
    switch (p.kind) {
      case DrawPlaceKind.line:
        s.runDraw(
          label: 'Line',
          work: (buf) => RustWorker.drawLine(
            buffer: buf,
            line: DrawLine(
              x0: p.lineX0,
              y0: p.lineY0,
              x1: p.lineX1,
              y1: p.lineY1,
              colorR: 0,
              colorG: 212,
              colorB: 170,
              colorA: 255,
            ),
            previewMaxEdge: EditorPipelineDefaults.previewMaxEdge,
            previewQuality: EditorSession.previewQuality,
            encodePreviewJpeg: !s.useRgbaPreview,
          ),
        );
      case DrawPlaceKind.circle:
        s.runDraw(
          label: 'Circle',
          work: (buf) => RustWorker.drawCircle(
            buffer: buf,
            circle: DrawCircle(
              centerX: p.circleX,
              centerY: p.circleY,
              radius: p.circleRadius,
              colorR: 255,
              colorG: 80,
              colorB: 120,
              colorA: 200,
            ),
            previewMaxEdge: EditorPipelineDefaults.previewMaxEdge,
            previewQuality: EditorSession.previewQuality,
            encodePreviewJpeg: !s.useRgbaPreview,
          ),
        );
    }
  }
}

// --- Overlay ---

class OverlayPanel extends StatefulWidget {
  const OverlayPanel({
    super.key,
    required this.session,
    required this.placement,
  });

  final EditorSession session;
  final OverlayPlacementController placement;

  @override
  State<OverlayPanel> createState() => _OverlayPanelState();
}

class _OverlayPanelState extends State<OverlayPanel> {
  Uint8List? _overlayBytes;

  OverlayPlacementController get p => widget.placement;

  @override
  void initState() {
    super.initState();
    p.addListener(_syncFromPlacement);
  }

  @override
  void dispose() {
    p.removeListener(_syncFromPlacement);
    super.dispose();
  }

  void _syncFromPlacement() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final maxW = (s.imageInfo?.width ?? 800).toDouble();
    final maxH = (s.imageInfo?.height ?? 1200).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Second image', subtitle: 'Watermark / sticker layer'),
        OutlinedButton.icon(
          onPressed: s.busy
              ? null
              : () async {
                  try {
                    final bytes = await ImageSourcePicker.pickImageBytes();
                    if (bytes == null) return;
                    final info = RustImageEditor.probe(bytes);
                    if (!mounted) return;
                    setState(() => _overlayBytes = bytes);
                    s.overlayStickerBytes = bytes;
                    p.setOverlaySize(info.width, info.height);
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Overlay pick failed: $e')),
                    );
                  }
                },
          icon: const Icon(Icons.add_photo_alternate),
          label: Text(_overlayBytes == null ? 'Pick overlay image' : 'Overlay selected'),
        ),
        const SizedBox(height: 8),
        Text(
          'Drag on the preview to position',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 12),
        LabeledSlider(
          label: 'X offset',
          value: p.x.toDouble(),
          min: 0,
          max: maxW,
          divisions: 50,
          display: '${p.x}',
          onChanged: s.busy
              ? null
              : (v) {
                  p.setPosition(v.round(), p.y);
                  s.scheduleOverlayLivePreview(p);
                },
        ),
        LabeledSlider(
          label: 'Y offset',
          value: p.y.toDouble(),
          min: 0,
          max: maxH,
          divisions: 50,
          display: '${p.y}',
          onChanged: s.busy
              ? null
              : (v) {
                  p.setPosition(p.x, v.round());
                  s.scheduleOverlayLivePreview(p);
                },
        ),
        if (_overlayBytes != null) ...[
          LabeledSlider(
            label: 'Overlay width',
            value: p.overlayWidth.toDouble(),
            min: OverlayPlacementController.minOverlayEdge.toDouble(),
            max: maxW,
            divisions: 40,
            display: '${p.overlayWidth}',
            onChanged: s.busy
                ? null
                : (v) {
                    p.setOverlaySize(v.round(), p.overlayHeight);
                    s.scheduleOverlayLivePreview(p);
                  },
          ),
          LabeledSlider(
            label: 'Overlay height',
            value: p.overlayHeight.toDouble(),
            min: OverlayPlacementController.minOverlayEdge.toDouble(),
            max: maxH,
            divisions: 40,
            display: '${p.overlayHeight}',
            onChanged: s.busy
                ? null
                : (v) {
                    p.setOverlaySize(p.overlayWidth, v.round());
                    s.scheduleOverlayLivePreview(p);
                  },
          ),
        ],
        const SectionHeader('Blend mode'),
        ActionChipRow<BlendMode>(
          items: BlendMode.values,
          label: (b) => b.name,
          selected: s.overlayBlendMode,
          onSelected: s.busy
              ? (_) {}
              : (v) {
                  setState(() => s.overlayBlendMode = v);
                  s.scheduleOverlayLivePreview(p);
                },
        ),
        const SizedBox(height: 8),
        PrimaryActionButton(
          icon: Icons.layers,
          label: 'Composite overlay',
          enabled: s.hasImage && _overlayBytes != null && !s.busy,
          onPressed: () {
            final overlay = _overlayBytes!;
            s.overlayStickerBytes = overlay;
            s.runOverlay(
              label: 'Overlay',
              work: (buf) {
                p.normalize();
                return RustWorker.overlayComposite(
                  base: buf,
                  overlayBytes: overlay,
                  x: p.x,
                  y: p.y,
                  blendMode: s.overlayBlendMode,
                  overlayWidth: p.overlayWidth,
                  overlayHeight: p.overlayHeight,
                  previewMaxEdge: EditorPipelineDefaults.previewMaxEdge,
                  previewQuality: EditorSession.previewQuality,
                  encodePreviewJpeg: !s.useRgbaPreview,
                );
              },
            );
          },
        ),
      ],
    );
  }
}

// --- Advanced ---

class AdvancedPanel extends StatefulWidget {
  const AdvancedPanel({super.key, required this.session});

  final EditorSession session;

  @override
  State<AdvancedPanel> createState() => _AdvancedPanelState();
}

class _AdvancedPanelState extends State<AdvancedPanel> {
  String? _blurHash;
  int _rgbaW = 800;
  int _rgbaH = 800;

  @override
  Widget build(BuildContext context) {
    final s = widget.session;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('RGBA pipeline', subtitle: 'Decode once, chain edits, encode'),
        if (s.rgbaPipeline)
          Chip(
            avatar: const Icon(Icons.check_circle, size: 18),
            label: Text('Active · ${s.rgbaBuffer?.width}×${s.rgbaBuffer?.height}'),
          ),
        const SizedBox(height: 8),
        PrimaryActionButton(
          icon: Icons.hub,
          label: 'Enable RGBA pipeline',
          enabled: s.hasImage && !s.busy,
          onPressed: () => s.enableRgbaPipeline(),
        ),
        LabeledSlider(
          label: 'RGBA resize width',
          value: _rgbaW.toDouble(),
          min: 64,
          max: 2048,
          divisions: 30,
          display: '$_rgbaW',
          onChanged: s.busy ? null : (v) => setState(() => _rgbaW = v.round()),
        ),
        LabeledSlider(
          label: 'RGBA resize height',
          value: _rgbaH.toDouble(),
          min: 64,
          max: 2048,
          divisions: 30,
          display: '$_rgbaH',
          onChanged: s.busy ? null : (v) => setState(() => _rgbaH = v.round()),
        ),
        PrimaryActionButton(
          icon: Icons.straighten,
          label: 'RGBA resize',
          enabled: s.hasImage && !s.busy,
          onPressed: () => s.runRgbaResize(
            label: 'RGBA resize',
            width: _rgbaW,
            height: _rgbaH,
          ),
        ),
        const SizedBox(height: 16),
        const SectionHeader('Progressive decode'),
        PrimaryActionButton(
          icon: Icons.low_priority,
          label: 'Show progressive preview',
          enabled: s.hasImage && !s.busy,
          onPressed: () => s.showProgressivePreview(),
        ),
        const SizedBox(height: 16),
        const SectionHeader('BlurHash'),
        PrimaryActionButton(
          icon: Icons.tag,
          label: 'Encode BlurHash',
          enabled: s.hasImage && !s.busy,
          onPressed: () async {
            final hash = await s.encodeBlurHash();
            if (!mounted || hash == null) return;
            setState(() => _blurHash = hash);
          },
        ),
        if (_blurHash != null) ...[
          const SizedBox(height: 8),
          SelectableText(_blurHash!, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          PrimaryActionButton(
            icon: Icons.image,
            label: 'Decode BlurHash to image',
            enabled: !s.busy,
            onPressed: () => s.runBytes(
              'BlurHash decode',
              (input) => RustWorker.bytesTransform(
                bytes: input,
                op: 'blurHashDecode',
                params: {
                  'hash': _blurHash!,
                  'width': s.imageInfo?.width ?? 400,
                  'height': s.imageInfo?.height ?? 400,
                  'format': s.outputFormat.index,
                  'quality': s.quality,
                },
              ),
              saveUndo: true,
            ),
          ),
        ],
        const SizedBox(height: 16),
        const SectionHeader('Batch resize demo'),
        PrimaryActionButton(
          icon: Icons.collections,
          label: 'Batch: 256 & 512 thumbs',
          enabled: s.hasImage && !s.busy,
          onPressed: () => s.runBatchResizeDemo(),
        ),
        const SizedBox(height: 8),
        Builder(
          builder: (context) {
            final stats = RustImageEditor.poolStats();
            return Text(
              'Buffer pool: ${stats.$1} buffers · ${stats.$2} bytes',
              style: Theme.of(context).textTheme.bodySmall,
            );
          },
        ),
      ],
    );
  }
}
