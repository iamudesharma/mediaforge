import 'dart:async';

import 'package:flutter/material.dart';
import '../editor_session.dart';
import '../models/layer_transform.dart';
import '../models/overlay_layer.dart';
import '../services/layer_rasterizer.dart';
import '../services/sticker_image_import.dart';
import '../services/sticker_catalog.dart';
import '../theme/lumina_tokens.dart';
import '../widgets/control_widgets.dart';
import 'shape_mask_sheet.dart';

class StickersPanel extends StatefulWidget {
  const StickersPanel({
    super.key,
    required this.session,
    this.scrollController,
  });

  final EditorSession session;

  /// When set (mobile tool sheet), this panel owns scrolling — no nested scroll views.
  final ScrollController? scrollController;

  @override
  State<StickersPanel> createState() => _StickersPanelState();
}

class _StickersPanelState extends State<StickersPanel> {
  static const double _defaultEmojiFontSize = 96;
  static const double _defaultEmojiLayerScale = 1.25;
  static const double _defaultBuiltinStickerScale = 1.4;

  int _tab = 0;
  final _textCtrl = TextEditingController(text: 'Hello');
  Color _textColor = Colors.white;
  TextBackgroundStyle _bgStyle = TextBackgroundStyle.rounded;
  double _textOpacity = 1;

  EditorSession get s => widget.session;

  StickerLayer? get _selectedSticker {
    final id = s.layerStack.selectedId;
    if (id == null) return null;
    for (final l in s.layerStack.layers) {
      if (l.id == id && l is StickerLayer) return l;
    }
    return null;
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  void _addEmoji(String glyph) {
    final info = s.imageInfo;
    final cx = (info?.width ?? 400) / 2;
    final cy = (info?.height ?? 600) / 2;
    s.pushLayerUndo();
    final layer = EmojiLayer(
      id: newLayerId(),
      transform: LayerTransform(
        centerX: cx,
        centerY: cy,
        scale: _defaultEmojiLayerScale,
      ),
      glyph: glyph,
      fontSize: _defaultEmojiFontSize,
    );
    s.layerStack.add(layer);
    s.notifyLayerChanged();
  }

  void _addBuiltinSticker(String key) {
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
          scale: _defaultBuiltinStickerScale,
        ),
        assetKey: key,
      ),
    );
    s.notifyLayerChanged();
  }

  Future<void> _importStickerImages(BuildContext context) async {
    await StickerImageImport.importFromGallery(context, s);
  }

  void _setSelectedStickerShape(StickerShapeMask mask) {
    final layer = _selectedSticker;
    if (layer == null) return;
    s.pushLayerUndo();
    layer.shapeMask = mask;
    LayerRasterizer.invalidateCache(layer);
    s.notifyLayerChanged();
    unawaited(LayerRasterizer.cacheLayerBitmap(layer).then((_) {
      if (mounted) s.notifyLayerChanged();
    }));
  }

  void _addText() {
    final info = s.imageInfo;
    final cx = (info?.width ?? 400) / 2;
    final cy = (info?.height ?? 600) / 2;
    s.pushLayerUndo();
    s.layerStack.add(
      TextLayer(
        id: newLayerId(),
        transform: LayerTransform(centerX: cx, centerY: cy, opacity: _textOpacity),
        text: _textCtrl.text,
        fontSize: 36,
        color: _textColor,
        backgroundStyle: _bgStyle,
      ),
    );
    s.notifyLayerChanged();
  }

  @override
  Widget build(BuildContext context) {
    final children = [
      _tabRow(),
      const SizedBox(height: LuminaTokens.padMd),
      if (_selectedSticker != null &&
          _selectedSticker!.userBytes != null &&
          _selectedSticker!.userBytes!.isNotEmpty) ...[
        const SectionHeader('Selected sticker shape'),
        ActionChipRow<StickerShapeMask>(
          horizontal: true,
          items: StickerShapeMask.values,
          label: ShapeMaskSheet.label,
          selected: _selectedSticker!.shapeMask,
          onSelected: _setSelectedStickerShape,
        ),
        const SizedBox(height: LuminaTokens.padMd),
      ],
      ..._tabBodyChildren(context),
    ];

    final controller = widget.scrollController;
    if (controller != null) {
      return ListView(
        controller: controller,
        padding: EdgeInsets.zero,
        children: children,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  Widget _tabRow() {
    return Row(
      children: [
        _tabChip(0, 'Emoji'),
        const SizedBox(width: 8),
        _tabChip(1, 'Stickers'),
        const SizedBox(width: 8),
        _tabChip(2, 'Text'),
      ],
    );
  }

  Widget _tabChip(int i, String label) {
    final selected = _tab == i;
    return Expanded(
      child: Material(
        color: selected
            ? LuminaTokens.primary.withValues(alpha: 0.2)
            : LuminaTokens.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(LuminaTokens.radiusMd),
        child: InkWell(
          onTap: () => setState(() => _tab = i),
          borderRadius: BorderRadius.circular(LuminaTokens.radiusMd),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? LuminaTokens.primary : LuminaTokens.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _tabBodyChildren(BuildContext context) {
    return switch (_tab) {
      0 => [_emojiGrid(context)],
      1 => [
          _stickerGrid(context),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: s.hasImage && !s.busy
                ? () => _importStickerImages(context)
                : null,
            icon: const Icon(Icons.add_photo_alternate),
            label: const Text('Import sticker images'),
          ),
        ],
      _ => [
          TextField(
            controller: _textCtrl,
            decoration: const InputDecoration(
              labelText: 'Caption',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          const SectionHeader('Background'),
          ActionChipRow<TextBackgroundStyle>(
            horizontal: true,
            items: TextBackgroundStyle.values,
            label: (b) => switch (b) {
              TextBackgroundStyle.none => 'None',
              TextBackgroundStyle.solid => 'Solid',
              TextBackgroundStyle.rounded => 'Rounded',
            },
            selected: _bgStyle,
            onSelected: (v) => setState(() => _bgStyle = v),
          ),
          LabeledSlider(
            label: 'Opacity',
            value: _textOpacity,
            min: 0.2,
            max: 1,
            divisions: 8,
            display: _textOpacity.toStringAsFixed(2),
            onChanged: (v) => setState(() => _textOpacity = v),
          ),
          PrimaryActionButton(
            icon: Icons.text_fields,
            label: 'Add text',
            enabled: s.hasImage && !s.busy,
            onPressed: _addText,
          ),
        ],
    };
  }

  Widget _emojiGrid(BuildContext context) {
    final cell = _gridCellSize(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var i = 0; i < StickerCatalog.emojis.length; i++)
          SizedBox(
            width: cell,
            height: cell,
            child: InkWell(
              onTap: s.hasImage ? () => _addEmoji(StickerCatalog.emojis[i]) : null,
              child: Center(
                child: Text(
                  StickerCatalog.emojis[i],
                  style: const TextStyle(fontSize: 28, shadows: []),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _stickerGrid(BuildContext context) {
    final cell = _gridCellSize(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (key, _) in StickerCatalog.builtinStickers)
          SizedBox(
            width: cell,
            height: cell,
            child: InkWell(
              onTap: s.hasImage ? () => _addBuiltinSticker(key) : null,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Image.asset(
                  StickerCatalog.assetPath(key),
                  package: StickerCatalog.assetPackage,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => Icon(
                    Icons.image_not_supported,
                    color: LuminaTokens.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  double _gridCellSize(BuildContext context) {
    const cols = 6;
    const spacing = 8.0;
    final w = MediaQuery.sizeOf(context).width;
    return ((w - spacing * (cols - 1)) / cols).clamp(44.0, 72.0);
  }
}
