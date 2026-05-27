import 'package:flutter/material.dart';

import '../editor_session.dart';
import '../models/overlay_layer.dart';
import '../theme/lumina_tokens.dart';
import '../widgets/control_widgets.dart';

/// Instagram-style layer list: reorder, visibility, delete, selection.
class LayersPanel extends StatelessWidget {
  const LayersPanel({
    super.key,
    required this.session,
    this.compact = false,
  });

  final EditorSession session;

  /// Tighter actions row for mobile sheet / canvas popover.
  final bool compact;

  static IconData _iconFor(OverlayLayer layer) => switch (layer.kind) {
        OverlayLayerKind.emoji => Icons.emoji_emotions_outlined,
        OverlayLayerKind.sticker => Icons.sticky_note_2_outlined,
        OverlayLayerKind.text => Icons.text_fields,
        OverlayLayerKind.shape => Icons.interests_outlined,
        OverlayLayerKind.paintStroke => Icons.brush_outlined,
        OverlayLayerKind.group => Icons.folder_outlined,
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
      case OverlayLayerKind.group:
        return 'Group (${(layer as GroupLayer).children.length})';
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
        final hasSelection = stack.selectedIds.isNotEmpty;
        final canGroup = stack.selectedIds.length >= 2;
        final canUngroup = stack.selectedId != null &&
            stack.findById(stack.selectedId!) is GroupLayer;

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(
              'Layers',
              subtitle: compact ? null : 'Top of list = front. Drag to reorder.',
            ),
            _LayerActionsBar(
              compact: compact,
              hasSelection: hasSelection,
              canGroup: canGroup,
              canUngroup: canUngroup,
              onDuplicate: hasSelection ? () => s.duplicateSelection() : null,
              onGroup: canGroup
                  ? () {
                      final err = s.groupSelection();
                      if (err != null && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(err)),
                        );
                      }
                    }
                  : null,
              onUngroup: canUngroup ? () => s.ungroupSelection() : null,
            ),
            SizedBox(height: compact ? 4 : LuminaTokens.padSm),
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
                final selected = stack.isSelected(layer.id);
                return _LayerRow(
                  key: ValueKey(layer.id),
                  listIndex: index,
                  layer: layer,
                  selected: selected,
                  icon: _iconFor(layer),
                  label: _labelFor(layer),
                  onSelect: () {
                    stack.selectOnly(layer.id);
                    s.notifyLayerChanged();
                  },
                  onToggleSelect: () {
                    stack.toggleSelect(layer.id);
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
                  onDuplicate: () {
                    stack.selectOnly(layer.id);
                    s.duplicateSelection();
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
            if (!compact) ...[
              const SizedBox(height: LuminaTokens.padMd),
              const SectionHeader(
                'Watermark',
                subtitle: 'Legacy second-image overlay',
              ),
              Text(
                'Use the Overlay tool tab for watermark placement on the base image.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _LayerActionsBar extends StatelessWidget {
  const _LayerActionsBar({
    required this.compact,
    required this.hasSelection,
    required this.canGroup,
    required this.canUngroup,
    required this.onDuplicate,
    required this.onGroup,
    required this.onUngroup,
  });

  final bool compact;
  final bool hasSelection;
  final bool canGroup;
  final bool canUngroup;
  final VoidCallback? onDuplicate;
  final VoidCallback? onGroup;
  final VoidCallback? onUngroup;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Row(
        children: [
          IconButton(
            tooltip: 'Duplicate',
            onPressed: onDuplicate,
            icon: const Icon(Icons.copy_outlined, size: 22),
          ),
          IconButton(
            tooltip: 'Group',
            onPressed: onGroup,
            icon: const Icon(Icons.workspaces_outlined, size: 22),
          ),
          IconButton(
            tooltip: 'Ungroup',
            onPressed: onUngroup,
            icon: const Icon(Icons.workspaces_filled, size: 22),
          ),
        ],
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.tonalIcon(
          onPressed: onDuplicate,
          icon: const Icon(Icons.copy_outlined, size: 18),
          label: const Text('Duplicate'),
        ),
        FilledButton.tonalIcon(
          onPressed: onGroup,
          icon: const Icon(Icons.workspaces_outlined, size: 18),
          label: const Text('Group'),
        ),
        FilledButton.tonalIcon(
          onPressed: onUngroup,
          icon: const Icon(Icons.workspaces_filled, size: 18),
          label: const Text('Ungroup'),
        ),
      ],
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
    required this.onToggleSelect,
    required this.onVisibility,
    required this.onDelete,
    required this.onDuplicate,
    required this.onBringFront,
    required this.onSendBack,
  });

  final int listIndex;
  final OverlayLayer layer;
  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onSelect;
  final VoidCallback onToggleSelect;
  final VoidCallback onVisibility;
  final VoidCallback onDelete;
  final VoidCallback onDuplicate;
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
        onLongPress: onToggleSelect,
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
                  case 'duplicate':
                    onDuplicate();
                  case 'front':
                    onBringFront();
                  case 'back':
                    onSendBack();
                  case 'delete':
                    onDelete();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
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
