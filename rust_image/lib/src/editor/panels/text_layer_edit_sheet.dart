import 'package:flutter/material.dart';

import '../editor_session.dart';
import '../models/overlay_layer.dart';
import '../services/layer_rasterizer.dart';
import '../widgets/control_widgets.dart';

/// Edit an existing [TextLayer] (Sprint 10 — replaces double-tap delete).
class TextLayerEditSheet extends StatefulWidget {
  const TextLayerEditSheet({
    super.key,
    required this.session,
    required this.layer,
  });

  final EditorSession session;
  final TextLayer layer;

  static Future<void> show(
    BuildContext context, {
    required EditorSession session,
    required TextLayer layer,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: TextLayerEditSheet(session: session, layer: layer),
      ),
    );
  }

  @override
  State<TextLayerEditSheet> createState() => _TextLayerEditSheetState();
}

class _TextLayerEditSheetState extends State<TextLayerEditSheet> {
  late final TextEditingController _textCtrl;
  late double _fontSize;
  late Color _textColor;
  late TextBackgroundStyle _bgStyle;
  late Color _bgColor;

  @override
  void initState() {
    super.initState();
    final l = widget.layer;
    _textCtrl = TextEditingController(text: l.text);
    _fontSize = l.fontSize;
    _textColor = l.color;
    _bgStyle = l.backgroundStyle;
    _bgColor = l.backgroundColor;
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    final l = widget.layer;
    l.transform; // keep reference
    // TextLayer fields are final — replace layer in stack
    final stack = widget.session.layerStack;
    final i = stack.layers.indexWhere((x) => x.id == l.id);
    if (i < 0) return;

    final updated = TextLayer(
      id: l.id,
      transform: l.transform.copyWith(),
      visible: l.visible,
      text: _textCtrl.text.trim().isEmpty ? l.text : _textCtrl.text,
      fontSize: _fontSize,
      color: _textColor,
      backgroundStyle: _bgStyle,
      backgroundColor: _bgColor,
      padding: l.padding,
      cornerRadius: l.cornerRadius,
    );
    widget.session.pushLayerUndo();
    stack.layers[i] = updated;
    stack.select(updated.id);
    updated.cachedPixels = null;
    updated.cachedWidth = 0;
    updated.cachedHeight = 0;
    await LayerRasterizer.cacheLayerBitmap(updated);
    widget.session.notifyLayerChanged();
    if (mounted) Navigator.pop(context);
  }

  void _delete() {
    widget.session.pushLayerUndo();
    widget.session.layerStack.remove(widget.layer.id);
    widget.session.notifyLayerChanged();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Edit text', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(
              controller: _textCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Caption',
                border: OutlineInputBorder(),
              ),
            ),
            LabeledSlider(
              label: 'Font size',
              value: _fontSize,
              min: 12,
              max: 120,
              divisions: 27,
              display: _fontSize.round().toString(),
              onChanged: (v) => setState(() => _fontSize = v),
            ),
            const SizedBox(height: 8),
            Text('Text color', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                Colors.white,
                Colors.black,
                const Color(0xFF4EDEA3),
                Colors.yellow,
                Colors.red,
              ].map((c) {
                return GestureDetector(
                  onTap: () => setState(() => _textColor = c),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _textColor == c ? Colors.white : Colors.grey,
                        width: 2,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            const SectionHeader('Background'),
            ActionChipRow<TextBackgroundStyle>(
              items: TextBackgroundStyle.values,
              label: (s) => switch (s) {
                TextBackgroundStyle.none => 'None',
                TextBackgroundStyle.solid => 'Solid',
                TextBackgroundStyle.rounded => 'Rounded',
              },
              selected: _bgStyle,
              onSelected: (v) => setState(() => _bgStyle = v),
            ),
            if (_bgStyle != TextBackgroundStyle.none) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  const Color(0xE6000000),
                  const Color(0xE6FFFFFF),
                  const Color(0xE6FF4081),
                ].map((c) {
                  return GestureDetector(
                    onTap: () => setState(() => _bgColor = c),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _bgColor == c ? Colors.white : Colors.grey,
                          width: 2,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(onPressed: _apply, child: const Text('Apply')),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete text layer'),
            ),
          ],
        ),
      ),
    );
  }
}
