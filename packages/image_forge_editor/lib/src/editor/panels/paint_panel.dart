import 'package:flutter/material.dart';

import '../editor_session.dart';
import '../models/overlay_layer.dart';
import '../theme/lumina_tokens.dart';
import '../widgets/control_widgets.dart';
import '../widgets/lumina_color_picker.dart';

class PaintPanel extends StatefulWidget {
  const PaintPanel({
    super.key,
    required this.session,
    this.scrollController,
    this.stripHostedExternally = false,
  });

  final EditorSession session;
  final ScrollController? scrollController;
  final bool stripHostedExternally;

  @override
  State<PaintPanel> createState() => _PaintPanelState();
}

class _PaintPanelState extends State<PaintPanel> {
  EditorSession get s => widget.session;

  void _applyToSession() {
    s.paintBrush = _brush;
    s.paintColor = _color;
    s.paintStrokeWidth = _size;
    s.paintStrokeOpacity = _opacity;
    s.notifyLayerChanged();
  }

  PaintBrushKind get _brush => s.paintBrush;
  set _brush(PaintBrushKind v) => s.paintBrush = v;

  Color get _color => s.paintColor;
  set _color(Color v) => s.paintColor = v;

  double get _size => s.paintStrokeWidth;
  set _size(double v) => s.paintStrokeWidth = v;

  double get _opacity => s.paintStrokeOpacity;
  set _opacity(double v) => s.paintStrokeOpacity = v;

  EraserMode get _eraserMode => s.eraserMode;
  set _eraserMode(EraserMode v) {
    s.eraserMode = v;
    s.notifyListeners();
  }

  bool get _filled => s.paintShapeFilled;
  set _filled(bool v) {
    s.paintShapeFilled = v;
    s.notifyListeners();
  }

  @override
  Widget build(BuildContext context) {
    final showFilledToggle = _brush == PaintBrushKind.rect ||
        _brush == PaintBrushKind.circle ||
        _brush == PaintBrushKind.hexagon ||
        _brush == PaintBrushKind.polygon;

    final children = [
      const SectionHeader('Brushes', subtitle: 'Draw freehand on the image'),
      ActionChipRow<PaintBrushKind>(
        horizontal: true,
        items: const [
          PaintBrushKind.pen,
          PaintBrushKind.marker,
          PaintBrushKind.highlighter,
          PaintBrushKind.neon,
        ],
        label: (b) => switch (b) {
          PaintBrushKind.pen => 'Pen',
          PaintBrushKind.marker => 'Marker',
          PaintBrushKind.highlighter => 'Hi-lite',
          PaintBrushKind.neon => 'Neon',
          _ => '',
        },
        selected: _brush,
        onSelected: (v) => setState(() {
          _brush = v;
          _applyToSession();
        }),
      ),
      const SizedBox(height: LuminaTokens.padMd),
      const SectionHeader('Vector Shapes', subtitle: 'Add vector shape overlays'),
      ActionChipRow<PaintBrushKind>(
        horizontal: true,
        items: const [
          PaintBrushKind.line,
          PaintBrushKind.arrow,
          PaintBrushKind.doubleArrow,
          PaintBrushKind.rect,
          PaintBrushKind.circle,
          PaintBrushKind.hexagon,
          PaintBrushKind.polygon,
          PaintBrushKind.dashLine,
          PaintBrushKind.dashDotLine,
        ],
        label: (b) => switch (b) {
          PaintBrushKind.line => 'Line',
          PaintBrushKind.arrow => 'Arrow',
          PaintBrushKind.doubleArrow => 'Double Arrow',
          PaintBrushKind.rect => 'Rectangle',
          PaintBrushKind.circle => 'Circle',
          PaintBrushKind.hexagon => 'Hexagon',
          PaintBrushKind.polygon => 'Polygon',
          PaintBrushKind.dashLine => 'Dashed Line',
          PaintBrushKind.dashDotLine => 'Dash-Dot Line',
          _ => '',
        },
        selected: _brush,
        onSelected: (v) => setState(() {
          _brush = v;
          _applyToSession();
        }),
      ),
      const SizedBox(height: LuminaTokens.padMd),
      const SectionHeader('Censors', subtitle: 'Blur or pixelate regions'),
      ActionChipRow<PaintBrushKind>(
        horizontal: true,
        items: const [
          PaintBrushKind.blur,
          PaintBrushKind.pixelate,
        ],
        label: (b) => switch (b) {
          PaintBrushKind.blur => 'Blur Area',
          PaintBrushKind.pixelate => 'Pixelate Area',
          _ => '',
        },
        selected: _brush,
        onSelected: (v) => setState(() {
          _brush = v;
          _applyToSession();
        }),
      ),
      const SizedBox(height: LuminaTokens.padMd),
      if (s.hasUncommittedLayers) ...[
        FilledButton.tonalIcon(
          onPressed: s.busy ? null : () => s.commitLayersToCanvas(),
          icon: const Icon(Icons.check_circle_outline),
          label: const Text('Apply paint to image'),
        ),
        const SizedBox(height: LuminaTokens.padMd),
        Text(
          'Bakes strokes into the photo so Filters and Beauty affect the whole image. Layer undo is cleared.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: LuminaTokens.padMd),
      ],
      const SectionHeader('Tools', subtitle: 'Utility paint operations'),
      Row(
        children: [
          ChoiceChip(
            label: const Text('Eraser'),
            selected: _brush == PaintBrushKind.eraser,
            onSelected: (selected) {
              if (selected) {
                setState(() {
                  _brush = PaintBrushKind.eraser;
                  _applyToSession();
                });
              }
            },
          ),
          if (_brush == PaintBrushKind.eraser) ...[
            const SizedBox(width: LuminaTokens.padMd),
            Text('Mode:', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(width: 8),
            ToggleButtons(
              constraints: const BoxConstraints(minHeight: 32, minWidth: 70),
              borderRadius: BorderRadius.circular(8),
              isSelected: [
                _eraserMode == EraserMode.partial,
                _eraserMode == EraserMode.object,
              ],
              onPressed: (index) {
                setState(() {
                  _eraserMode = index == 0 ? EraserMode.partial : EraserMode.object;
                });
              },
              children: const [
                Text('Partial'),
                Text('Object'),
              ],
            ),
          ],
        ],
      ),
      if (showFilledToggle) ...[
        const SizedBox(height: LuminaTokens.padMd),
        SwitchListTile(
          title: const Text('Fill Shape'),
          subtitle: const Text('Render as a solid color fill instead of outline'),
          value: _filled,
          contentPadding: EdgeInsets.zero,
          onChanged: (v) {
            setState(() {
              _filled = v;
            });
          },
        ),
      ],
      if (!widget.stripHostedExternally && _brush != PaintBrushKind.eraser) ...[
        const SizedBox(height: LuminaTokens.padMd),
        Text('Color', style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 8),
        LuminaColorSwatchRow(
          selected: _color,
          onSelected: (c) => setState(() {
            _color = c;
            _applyToSession();
          }),
        ),
      ],
      LabeledSlider(
        label: 'Size',
        value: _size,
        min: 1,
        max: 48,
        divisions: 47,
        display: _size.round().toString(),
        onChanged: (v) => setState(() {
          _size = v;
          _applyToSession();
        }),
      ),
      if (_brush != PaintBrushKind.eraser)
        LabeledSlider(
          label: 'Opacity',
          value: _opacity,
          min: 0.1,
          max: 1,
          divisions: 9,
          display: _opacity.toStringAsFixed(2),
          onChanged: (v) => setState(() {
            _opacity = v;
            _applyToSession();
          }),
        ),
      OutlinedButton.icon(
        onPressed: s.layerStack.paintStrokes.isEmpty
            ? null
            : () {
                s.pushLayerUndo();
                final strokes = s.layerStack.paintStrokes;
                if (strokes.isNotEmpty) {
                  s.layerStack.layers.remove(strokes.last);
                }
                s.notifyLayerChanged();
              },
        icon: const Icon(Icons.undo),
        label: const Text('Undo last stroke'),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: s.layerStack.paintStrokes.isEmpty
            ? null
            : () {
                s.pushLayerUndo();
                s.layerStack.layers.removeWhere((l) => l is PaintStrokeLayer);
                s.notifyLayerChanged();
              },
        icon: const Icon(Icons.delete_outline),
        label: const Text('Clear all strokes'),
      ),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}
