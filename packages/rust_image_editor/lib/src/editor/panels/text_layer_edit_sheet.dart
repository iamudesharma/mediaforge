import 'package:flutter/material.dart';

import '../editor_session.dart';
import '../models/overlay_layer.dart';
import '../models/text_style_draft.dart';
import '../services/layer_rasterizer.dart';
import '../widgets/control_widgets.dart';
import '../widgets/lumina_color_picker.dart';
import '../widgets/text_style_controls.dart';

/// Edit an existing [TextLayer] (Sprint 10 — replaces double-tap delete).
class TextLayerEditSheet extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return TextLayerEditPanel(session: session, layer: layer);
  }
}

/// Applies draft fields to a [TextLayer] and writes into [LayerStack] by id.
TextLayer? replaceTextLayerInStack({
  required EditorSession session,
  required String layerId,
  required TextStyleDraft style,
  required String text,
  required TextBackgroundStyle backgroundStyle,
  required Color backgroundColor,
}) {
  final stack = session.layerStack;
  final i = stack.layers.indexWhere((x) => x.id == layerId);
  if (i < 0) return null;
  final base = stack.layers[i];
  if (base is! TextLayer) return null;

  var updated = style.mergeInto(base);
  final trimmed = text.trim();
  updated = TextLayer(
    id: updated.id,
    transform: updated.transform.copyWith(),
    visible: updated.visible,
    text: trimmed.isEmpty ? base.text : text,
    fontSize: updated.fontSize,
    color: updated.color,
    fillMode: updated.fillMode,
    gradientEnd: updated.gradientEnd,
    gradientAngleDeg: updated.gradientAngleDeg,
    fontWeight: updated.fontWeight,
    fontStyle: updated.fontStyle,
    fontFamily: updated.fontFamily,
    backgroundStyle: backgroundStyle,
    backgroundColor: backgroundColor,
    padding: updated.padding,
    cornerRadius: updated.cornerRadius,
  );
  LayerRasterizer.invalidateCache(updated);
  stack.layers[i] = updated;
  stack.bumpRevision();
  stack.select(updated.id);
  session.notifyLayerChanged();
  return updated;
}

/// Inline / modal body for text layer editing — live updates on the canvas.
class TextLayerEditPanel extends StatefulWidget {
  const TextLayerEditPanel({
    super.key,
    required this.session,
    required this.layer,
    this.onDismiss,
  });

  final EditorSession session;
  final TextLayer layer;
  final VoidCallback? onDismiss;

  @override
  State<TextLayerEditPanel> createState() => _TextLayerEditPanelState();
}

class _TextLayerEditPanelState extends State<TextLayerEditPanel> {
  late final TextEditingController _textCtrl;
  late TextStyleDraft _style;
  late TextBackgroundStyle _bgStyle;
  late Color _bgColor;
  bool _undoPushed = false;

  String get _layerId => widget.layer.id;

  void _dismiss() {
    if (widget.onDismiss != null) {
      widget.onDismiss!();
    } else if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  void initState() {
    super.initState();
    final l = widget.layer;
    _textCtrl = TextEditingController(text: l.text);
    _style = TextStyleDraft.fromLayer(l);
    _bgStyle = l.backgroundStyle;
    _bgColor = l.backgroundColor;
    _textCtrl.addListener(_onDraftChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncLiveToCanvas());
  }

  @override
  void didUpdateWidget(covariant TextLayerEditPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.layer.id != widget.layer.id) {
      final l = widget.layer;
      _textCtrl.text = l.text;
      _style = TextStyleDraft.fromLayer(l);
      _bgStyle = l.backgroundStyle;
      _bgColor = l.backgroundColor;
      _syncLiveToCanvas();
    }
  }

  @override
  void dispose() {
    _textCtrl.removeListener(_onDraftChanged);
    _textCtrl.dispose();
    super.dispose();
  }

  void _onDraftChanged() => _syncLiveToCanvas();

  void _ensureUndoSnapshot() {
    if (_undoPushed) return;
    widget.session.pushLayerUndo();
    _undoPushed = true;
  }

  void _syncLiveToCanvas() {
    final i = widget.session.layerStack.layers.indexWhere((x) => x.id == _layerId);
    if (i < 0) return;
    _ensureUndoSnapshot();
    replaceTextLayerInStack(
      session: widget.session,
      layerId: _layerId,
      style: _style,
      text: _textCtrl.text,
      backgroundStyle: _bgStyle,
      backgroundColor: _bgColor,
    );
  }

  void _onStyleChanged(TextStyleDraft d) {
    setState(() => _style = d);
    _syncLiveToCanvas();
  }

  void _onBackgroundStyleChanged(TextBackgroundStyle v) {
    setState(() => _bgStyle = v);
    _syncLiveToCanvas();
  }

  void _onBackgroundColorChanged(Color c) {
    setState(() => _bgColor = c);
    _syncLiveToCanvas();
  }

  Future<void> _apply() async {
    _syncLiveToCanvas();
    _dismiss();
  }

  void _delete() {
    widget.session.pushLayerUndo();
    widget.session.layerStack.remove(_layerId);
    widget.session.notifyLayerChanged();
    _dismiss();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          24 + MediaQuery.paddingOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Edit text',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (widget.onDismiss != null)
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _dismiss,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Changes update on the image as you edit',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _textCtrl,
              maxLines: 3,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Caption',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextStyleControls(
              value: _style,
              onChanged: _onStyleChanged,
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
              onSelected: _onBackgroundStyleChanged,
            ),
            if (_bgStyle != TextBackgroundStyle.none) ...[
              const SizedBox(height: 8),
              Text(
                'Background color',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(height: 8),
              LuminaColorSwatchRow(
                selected: _bgColor,
                presets: const [
                  Color(0xE6000000),
                  Color(0xE6FFFFFF),
                  Color(0xE6FF4081),
                  Color(0xE6000000),
                ],
                onSelected: _onBackgroundColorChanged,
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(onPressed: _apply, child: const Text('Done')),
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
