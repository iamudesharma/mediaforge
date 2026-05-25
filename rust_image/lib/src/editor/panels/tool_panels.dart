import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:rust_image/src/rust_image_editor.dart';

import '../draw_placement.dart';
import '../editor_session.dart';
import '../overlay_placement.dart';
import '../rust_image_editor_config.dart';
import '../services/filter_descriptor.dart';
import '../services/image_source_picker.dart';
import '../services/rust_worker.dart';
import '../theme/lumina_tokens.dart';
import '../widgets/control_widgets.dart';
import '../widgets/editor_animations.dart';
import 'blank_canvas_sheet.dart';
import 'paint_panel.dart';
import 'stickers_panel.dart';

enum EditorTool {
  import,
  transform,
  filters,
  adjust,
  paint,
  stickers,
  export_,
  draw,
  overlay,
  advanced,
}

extension EditorToolX on EditorTool {
  String get label => switch (this) {
        EditorTool.import => 'Import',
        EditorTool.transform => 'Transform',
        EditorTool.filters => 'Filters',
        EditorTool.adjust => 'Adjust',
        EditorTool.paint => 'Paint',
        EditorTool.stickers => 'Stickers',
        EditorTool.export_ => 'Export',
        EditorTool.draw => 'Draw',
        EditorTool.overlay => 'Overlay',
        EditorTool.advanced => 'Advanced',
      };

  /// Lumina bottom-nav label (DESIGN.md).
  String get mobileNavLabel => switch (this) {
        EditorTool.import => 'Import',
        EditorTool.transform => 'Crop',
        EditorTool.filters => 'Filters',
        EditorTool.adjust => 'Adjust',
        EditorTool.paint => 'Paint',
        EditorTool.stickers => 'Stickers',
        EditorTool.export_ => 'Export',
        EditorTool.draw => 'Draw',
        EditorTool.overlay => 'Overlay',
        EditorTool.advanced => 'Advanced',
      };

  IconData get icon => switch (this) {
        EditorTool.import => Icons.photo_library_outlined,
        EditorTool.transform => Icons.crop_rotate,
        EditorTool.filters => Icons.auto_awesome,
        EditorTool.adjust => Icons.tune,
        EditorTool.paint => Icons.brush_outlined,
        EditorTool.stickers => Icons.emoji_emotions_outlined,
        EditorTool.export_ => Icons.save_alt_outlined,
        EditorTool.draw => Icons.draw_outlined,
        EditorTool.overlay => Icons.layers_outlined,
        EditorTool.advanced => Icons.memory_outlined,
      };

  /// Lumina nav icons (reference screens).
  IconData get navIcon => switch (this) {
        EditorTool.import => Icons.photo_library_outlined,
        EditorTool.transform => Icons.crop,
        EditorTool.filters => Icons.photo_filter_outlined,
        EditorTool.adjust => Icons.tune,
        EditorTool.paint => Icons.brush_outlined,
        EditorTool.stickers => Icons.emoji_emotions_outlined,
        EditorTool.export_ => Icons.save_alt_outlined,
        EditorTool.draw => Icons.draw_outlined,
        EditorTool.overlay => Icons.layers_outlined,
        EditorTool.advanced => Icons.equalizer,
      };

  /// Export uses top-bar pill; import opens from top bar on mobile.
  bool get showInBottomNav =>
      this != EditorTool.export_ && this != EditorTool.import;
}

class ToolPanelHost extends StatelessWidget {
  const ToolPanelHost({
    super.key,
    required this.tool,
    required this.session,
    required this.config,
    this.drawPlacement,
    this.overlayPlacement,
    this.scrollController,
    this.compact = false,
  });

  final EditorTool tool;
  final EditorSession session;
  final RustImageEditorConfig config;
  final DrawPlacementController? drawPlacement;
  final OverlayPlacementController? overlayPlacement;
  final ScrollController? scrollController;
  final bool compact;

  bool get _ownsScroll =>
      compact &&
      scrollController != null &&
      (tool == EditorTool.stickers || tool == EditorTool.paint);

  Widget _panel() => switch (tool) {
        EditorTool.import => ImportPanel(
            session: session,
            allowBlankCanvas: config.allowBlankCanvas,
          ),
        EditorTool.transform => TransformPanel(session: session),
        EditorTool.filters => FiltersPanel(session: session),
        EditorTool.adjust => AdjustPanel(session: session),
        EditorTool.paint => PaintPanel(
            session: session,
            scrollController: scrollController,
          ),
        EditorTool.stickers => StickersPanel(
            session: session,
            scrollController: scrollController,
          ),
        EditorTool.export_ => ExportPanel(session: session, config: config),
        EditorTool.draw => DrawPanel(
            session: session,
            placement: drawPlacement!,
          ),
        EditorTool.overlay => OverlayPanel(
            session: session,
            placement: overlayPlacement!,
          ),
        EditorTool.advanced => AdvancedPanel(session: session),
      };

  @override
  Widget build(BuildContext context) {
    final padding = compact
        ? const EdgeInsets.fromLTRB(12, 0, 12, 16)
        : const EdgeInsets.fromLTRB(16, 8, 16, 24);

    final child = _ownsScroll
        ? Padding(padding: padding, child: _panel())
        : SingleChildScrollView(
            controller: scrollController,
            primary: scrollController == null,
            padding: padding,
            child: _panel(),
          );

    return AnimatedPanelSwitcher(
      switchKey: tool,
      child: child,
    );
  }
}

// --- Import ---

class ImportPanel extends StatelessWidget {
  const ImportPanel({
    super.key,
    required this.session,
    this.allowBlankCanvas = true,
  });

  final EditorSession session;
  final bool allowBlankCanvas;

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
                : () => BlankCanvasSheet.show(context, session),
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
  const TransformPanel({super.key, required this.session});

  final EditorSession session;

  @override
  State<TransformPanel> createState() => _TransformPanelState();
}

class _TransformPanelState extends State<TransformPanel> {
  int _width = 1024;
  int _height = 1024;
  int _thumbEdge = 512;
  int _cropX = 0;
  int _cropY = 0;
  int _cropW = 400;
  int _cropH = 400;
  ResizeAlgorithm _algorithm = ResizeAlgorithm.lanczos3;
  int? _lastInfoWidth;
  String _aspect = 'Free';

  EditorSession get s => widget.session;

  void _maybeSyncFromInfo() {
    final info = s.imageInfo;
    if (info == null || info.width == _lastInfoWidth) return;
    _lastInfoWidth = info.width;
    _width = info.width;
    _height = info.height;
    _cropW = (info.width * 0.8).round().clamp(1, info.width);
    _cropH = (info.height * 0.8).round().clamp(1, info.height);
    _cropX = ((info.width - _cropW) / 2).round();
    _cropY = ((info.height - _cropH) / 2).round();
  }

  void _applyAspect(String aspect) {
    final info = s.imageInfo;
    if (info == null) return;
    final w = info.width;
    final h = info.height;
    switch (aspect) {
      case '1:1':
        final side = w < h ? w : h;
        _cropW = side;
        _cropH = side;
      case '4:3':
        _cropW = w;
        _cropH = (w * 3 / 4).round().clamp(1, h);
      case '16:9':
        _cropW = w;
        _cropH = (w * 9 / 16).round().clamp(1, h);
      case '3:2':
        _cropW = w;
        _cropH = (w * 2 / 3).round().clamp(1, h);
      default:
        _cropW = (w * 0.8).round().clamp(1, w);
        _cropH = (h * 0.8).round().clamp(1, h);
    }
    _cropX = ((w - _cropW) / 2).round().clamp(0, w - _cropW);
    _cropY = ((h - _cropH) / 2).round().clamp(0, h - _cropH);
  }

  @override
  Widget build(BuildContext context) {
    _maybeSyncFromInfo();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ActionChipRow<String>(
          horizontal: true,
          items: const ['Free', '1:1', '4:3', '16:9', '3:2'],
          label: (a) => a,
          selected: _aspect,
          onSelected: s.busy
              ? (_) {}
              : (a) {
                  setState(() {
                    _aspect = a;
                    _applyAspect(a);
                  });
                },
        ),
        const SizedBox(height: LuminaTokens.padMd),
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
        const SectionHeader('Crop'),
        LabeledSlider(
          label: 'X',
          value: _cropX.toDouble(),
          min: 0,
          max: (s.imageInfo?.width ?? 1000).toDouble(),
          divisions: 40,
          display: '$_cropX',
          onChanged: s.busy ? null : (v) => setState(() => _cropX = v.round()),
        ),
        LabeledSlider(
          label: 'Y',
          value: _cropY.toDouble(),
          min: 0,
          max: (s.imageInfo?.height ?? 1000).toDouble(),
          divisions: 40,
          display: '$_cropY',
          onChanged: s.busy ? null : (v) => setState(() => _cropY = v.round()),
        ),
        LabeledSlider(
          label: 'Width',
          value: _cropW.toDouble(),
          min: 32,
          max: (s.imageInfo?.width ?? 1000).toDouble(),
          divisions: 40,
          display: '$_cropW',
          onChanged: s.busy ? null : (v) => setState(() => _cropW = v.round()),
        ),
        LabeledSlider(
          label: 'Height',
          value: _cropH.toDouble(),
          min: 32,
          max: (s.imageInfo?.height ?? 1000).toDouble(),
          divisions: 40,
          display: '$_cropH',
          onChanged: s.busy ? null : (v) => setState(() => _cropH = v.round()),
        ),
        PrimaryActionButton(
          icon: Icons.crop,
          label: 'Apply crop',
          enabled: s.hasImage && !s.blocking,
          onPressed: () => s.runBytes(
            'Crop',
            (input) => RustWorker.bytesTransform(
              bytes: input,
              op: 'crop',
              params: {
                'x': _cropX,
                'y': _cropY,
                'width': _cropW,
                'height': _cropH,
                'format': s.outputFormat.index,
                'quality': s.quality,
              },
            ),
          ),
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
  const FiltersPanel({super.key, required this.session});

  final EditorSession session;

  @override
  State<FiltersPanel> createState() => _FiltersPanelState();
}

class _FiltersPanelState extends State<FiltersPanel> {
  static const _presets = FilterPreset.values;
  int _selectedPreset = 0;

  EditorSession get session => widget.session;

  @override
  Widget build(BuildContext context) {
    final presetLabels = ['Original', ..._presets.map(_presetName)];

    return Column(
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
              descriptor: FilterDescriptor.preset(_presets[i - 1]),
            );
          },
        ),
        const SizedBox(height: LuminaTokens.padMd),
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

class AdjustPanel extends StatefulWidget {
  const AdjustPanel({super.key, required this.session});

  final EditorSession session;

  @override
  State<AdjustPanel> createState() => _AdjustPanelState();
}

class _AdjustPanelState extends State<AdjustPanel> {
  double _brightness = 20;
  double _contrast = 1.1;
  double _saturation = 1.2;
  double _hue = 30;

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
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
      ],
    );
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
  }
}

// --- Draw ---

class DrawPanel extends StatefulWidget {
  const DrawPanel({
    super.key,
    required this.session,
    required this.placement,
  });

  final EditorSession session;
  final DrawPlacementController placement;

  @override
  State<DrawPanel> createState() => _DrawPanelState();
}

class _DrawPanelState extends State<DrawPanel> {
  late final TextEditingController _textCtrl;

  DrawPlacementController get p => widget.placement;
  EditorSession get s => widget.session;

  @override
  void initState() {
    super.initState();
    _textCtrl = TextEditingController(text: p.text);
    p.addListener(_onPlacementChanged);
  }

  @override
  void dispose() {
    p.removeListener(_onPlacementChanged);
    _textCtrl.dispose();
    super.dispose();
  }

  void _onPlacementChanged() {
    if (_textCtrl.text != p.text) {
      _textCtrl.text = p.text;
    }
    setState(() {});
  }

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
                DrawPlaceKind.text => 'Text',
                DrawPlaceKind.line => 'Line',
                DrawPlaceKind.circle => 'Circle',
              },
              selected: p.kind,
              onSelected: p.setKind,
            ),
            const SizedBox(height: 12),
            ...switch (p.kind) {
              DrawPlaceKind.text => _textControls(maxW, maxH),
              DrawPlaceKind.line => _lineControls(maxW, maxH),
              DrawPlaceKind.circle => _circleControls(maxW, maxH),
            },
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

  List<Widget> _textControls(double maxW, double maxH) {
    return [
      TextField(
        controller: _textCtrl,
        decoration: const InputDecoration(
          labelText: 'Text',
          border: OutlineInputBorder(),
        ),
        onChanged: p.setText,
      ),
      LabeledSlider(
        label: 'X',
        value: p.textX.toDouble(),
        min: 0,
        max: maxW,
        divisions: maxW > 0 ? maxW.clamp(1, 80).toInt() : 1,
        display: '${p.textX}',
        onChanged: s.blocking ? null : (v) => p.setTextPos(v.round(), p.textY),
      ),
      LabeledSlider(
        label: 'Y',
        value: p.textY.toDouble(),
        min: 0,
        max: maxH,
        divisions: maxH > 0 ? maxH.clamp(1, 80).toInt() : 1,
        display: '${p.textY}',
        onChanged: s.blocking ? null : (v) => p.setTextPos(p.textX, v.round()),
      ),
      LabeledSlider(
        label: 'Font size',
        value: p.fontSize,
        min: 12,
        max: 120,
        divisions: 27,
        display: p.fontSize.round().toString(),
        onChanged: s.blocking ? null : p.setFontSize,
      ),
    ];
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
    p.setText(_textCtrl.text);
    switch (p.kind) {
      case DrawPlaceKind.text:
        s.runDraw(
          label: 'Text',
          work: (buf) => RustWorker.drawText(
            buffer: buf,
            overlay: TextOverlay(
              text: p.text,
              x: p.textX,
              y: p.textY,
              fontSize: p.fontSize,
              colorR: 255,
              colorG: 255,
              colorB: 255,
              colorA: 255,
            ),
            previewMaxEdge: EditorPipelineDefaults.previewMaxEdge,
            previewQuality: EditorSession.previewQuality,
            encodePreviewJpeg: !s.useRgbaPreview,
          ),
        );
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
          min: -200,
          max: maxW,
          divisions: 50,
          display: '${p.x}',
          onChanged: s.busy
              ? null
              : (v) {
                  p.setPosition(v.round(), p.y);
                  s.scheduleOverlayLivePreview(x: p.x, y: p.y);
                },
        ),
        LabeledSlider(
          label: 'Y offset',
          value: p.y.toDouble(),
          min: -200,
          max: maxH,
          divisions: 50,
          display: '${p.y}',
          onChanged: s.busy
              ? null
              : (v) {
                  p.setPosition(p.x, v.round());
                  s.scheduleOverlayLivePreview(x: p.x, y: p.y);
                },
        ),
        const SectionHeader('Blend mode'),
        ActionChipRow<BlendMode>(
          items: BlendMode.values,
          label: (b) => b.name,
          selected: s.overlayBlendMode,
          onSelected: s.busy
              ? (_) {}
              : (v) {
                  setState(() => s.overlayBlendMode = v);
                  s.scheduleOverlayLivePreview(x: p.x, y: p.y);
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
              work: (buf) => RustWorker.overlayComposite(
                base: buf,
                overlayBytes: overlay,
                x: p.x,
                y: p.y,
                blendMode: s.overlayBlendMode,
                previewMaxEdge: EditorPipelineDefaults.previewMaxEdge,
                previewQuality: EditorSession.previewQuality,
                encodePreviewJpeg: !s.useRgbaPreview,
              ),
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
