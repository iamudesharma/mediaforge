import 'package:flutter/material.dart';

import '../editor_session.dart';
import '../models/layer_stack.dart';
import '../models/overlay_layer.dart';
import '../theme/lumina_tokens.dart';
import '../widgets/control_widgets.dart';

/// Instagram-style layer list: reorder, visibility, delete, selection.
class LayersPanel extends StatelessWidget {
  const LayersPanel({super.key, required this.session});

  final EditorSession session;

  static IconData _iconFor(OverlayLayer layer) => switch (layer.kind) {
        OverlayLayerKind.emoji => Icons.emoji_emotions_outlined,
        OverlayLayerKind.sticker => Icons.sticky_note_2_outlined,
        OverlayLayerKind.text => Icons.text_fields,
        OverlayLayerKind.shape => Icons.interests_outlined,
        OverlayLayerKind.paintStroke => Icons.brush_outlined,
      };

  static String _labelFor(OverlayLayer layer) {
    switch (layer.kind) {
      case OverlayLayerKind.emoji:
        return (layer as EmojiLayer).glyph;
      case OverlayLayerKind.sticker:
        return (layer as StickerLayer).assetKey ?? 'Image sticker';
      case OverlayLayerKind.text:
        final text = (layer as TextLayer).text;
        return text.length > 24 ? '${text.substring(0, 24)}…' : text;
      case OverlayLayerKind.shape:
        return (layer as ShapeLayer).shapeKind.name;
      case OverlayLayerKind.paintStroke:
        return 'Paint stroke';
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = session;
    return ListenableBuilder(
      listenable: s.layerListenable,
      builder: (context, _) {
        final stack = s.layerStack;
        if (stack.isEmpty) {
          return Text(
            'No layers yet. Add stickers, text, or paint from other tools.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          );
        }

        final ordered = List<OverlayLayer>.from(stack.layers.reversed);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionHeader(
              'Layers',
              subtitle: 'Top of list = front. Drag to reorder.',
            ),
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: ordered.length,
              onReorder: (oldIndex, newIndex) {
                if (newIndex > oldIndex) newIndex -= 1;
                final layer = ordered.removeAt(oldIndex);
                ordered.insert(newIndex, layer);
                s.pushLayerUndo();
                final frontToBack = ordered.reversed.toList();
                stack.layers
                  ..clear()
                  ..addAll(frontToBack);
                stack.bumpRevision();
                s.notifyLayerChanged();
              },
              itemBuilder: (context, index) {
                final layer = ordered[index];
                final selected = layer.id == stack.selectedId;
                return _LayerRow(
                  key: ValueKey(layer.id),
                  listIndex: index,
                  layer: layer,
                  selected: selected,
                  icon: _iconFor(layer),
                  label: _labelFor(layer),
                  onSelect: () {
                    stack.select(layer.id);
                    s.notifyLayerChanged();
                  },
                  onVisibility: () {
                    s.pushLayerUndo();
                    stack.setVisible(layer.id, !layer.visible);
                    s.notifyLayerChanged();
                  },
                  onDelete: () {
                    s.pushLayerUndo();
                    stack.remove(layer.id);
                    s.notifyLayerChanged();
                  },
                  onBringFront: () {
                    s.pushLayerUndo();
                    stack.bringToFront(layer.id);
                    s.notifyLayerChanged();
                  },
                  onSendBack: () {
                    s.pushLayerUndo();
                    stack.sendToBack(layer.id);
                    s.notifyLayerChanged();
                  },
                );
              },
            ),
            const SizedBox(height: LuminaTokens.padMd),
            const SectionHeader('Watermark', subtitle: 'Legacy second-image overlay'),
            Text(
              'Use the Overlay tool tab for watermark placement on the base image.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        );
      },
    );
  }
}

class _LayerRow extends StatelessWidget {
  const _LayerRow({
    super.key,
    required this.listIndex,
    required this.layer,
    required this.selected,
    required this.icon,
    required this.label,
    required this.onSelect,
    required this.onVisibility,
    required this.onDelete,
    required this.onBringFront,
    required this.onSendBack,
  });

  final int listIndex;
  final OverlayLayer layer;
  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onSelect;
  final VoidCallback onVisibility;
  final VoidCallback onDelete;
  final VoidCallback onBringFront;
  final VoidCallback onSendBack;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? scheme.primaryContainer.withValues(alpha: 0.35)
          : Colors.transparent,
      child: ListTile(
        leading: ReorderableDragStartListener(
          index: listIndex,
          child: Icon(icon, color: layer.visible ? null : scheme.outline),
        ),
        title: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: layer.visible ? null : scheme.onSurfaceVariant,
          ),
        ),
        subtitle: layer.visible ? null : const Text('Hidden'),
        selected: selected,
        onTap: onSelect,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: layer.visible ? 'Hide' : 'Show',
              icon: Icon(layer.visible ? Icons.visibility : Icons.visibility_off),
              onPressed: onVisibility,
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (v) {
                switch (v) {
                  case 'front':
                    onBringFront();
                  case 'back':
                    onSendBack();
                  case 'delete':
                    onDelete();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'front', child: Text('Bring to front')),
                const PopupMenuItem(value: 'back', child: Text('Send to back')),
                const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
