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

  @override
  Widget build(BuildContext context) {
    final children = [
      const SectionHeader('Brush', subtitle: 'Draw on the image — drag with one finger'),
      ActionChipRow<PaintBrushKind>(
        horizontal: true,
        items: PaintBrushKind.values,
        label: (b) => switch (b) {
          PaintBrushKind.pen => 'Pen',
          PaintBrushKind.marker => 'Marker',
          PaintBrushKind.highlighter => 'Hi-lite',
          PaintBrushKind.neon => 'Neon',
          PaintBrushKind.eraser => 'Eraser',
        },
        selected: _brush,
        onSelected: (v) => setState(() {
          _brush = v;
          _applyToSession();
        }),
      ),
      if (!widget.stripHostedExternally) ...[
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
