import 'dart:async';

import 'package:flutter/material.dart';
import '../editor_session.dart';
import '../models/layer_transform.dart';
import '../models/overlay_layer.dart';
import '../services/layer_rasterizer.dart';
import '../services/sticker_image_import.dart';
import '../services/sticker_catalog.dart';
import '../theme/lumina_tokens.dart';
import '../models/text_style_draft.dart';
import '../widgets/control_widgets.dart';
import '../widgets/text_style_controls.dart';
import 'shape_mask_sheet.dart';
import 'text_layer_edit_sheet.dart';

class StickersPanel extends StatefulWidget {
  const StickersPanel({
    super.key,
    required this.session,
    this.scrollController,
    this.stripHostedExternally = false,
    this.tabIndex = 0,
    this.onTabChanged,
  });

  final EditorSession session;

  /// When set (mobile tool sheet), this panel owns scrolling — no nested scroll views.
  final ScrollController? scrollController;
  final bool stripHostedExternally;
  final int tabIndex;
  final ValueChanged<int>? onTabChanged;

  @override
  State<StickersPanel> createState() => _StickersPanelState();
}

class _StickersPanelState extends State<StickersPanel> {
  static const double _defaultEmojiFontSize = 96;
  static const double _defaultEmojiLayerScale = 1.25;
  static const double _defaultBuiltinStickerScale = 1.4;

  int get _tab => widget.tabIndex;
  final _textCtrl = TextEditingController(text: 'Hello');
  TextStyleDraft _textStyle = const TextStyleDraft();
  TextBackgroundStyle _bgStyle = TextBackgroundStyle.rounded;
  double _textOpacity = 1;

  /// Live text on canvas while the Text tab is active.
  String? _canvasTextLayerId;

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
  void initState() {
    super.initState();
    _textCtrl.addListener(_onTextDraftChanged);
    if (widget.tabIndex == 2) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _ensureLiveTextLayer();
      });
    }
  }

  @override
  void didUpdateWidget(covariant StickersPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tabIndex != widget.tabIndex && widget.tabIndex == 2) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _ensureLiveTextLayer();
      });
    }
  }

  @override
  void dispose() {
    _textCtrl.removeListener(_onTextDraftChanged);
    _textCtrl.dispose();
    super.dispose();
  }

  void _onTextDraftChanged() {
    if (_tab == 2) _syncLiveTextToCanvas();
  }

  void _ensureLiveTextLayer() {
    if (_tab != 2 || !s.hasImage || s.busy) return;

    if (_canvasTextLayerId != null) {
      final exists =
          s.layerStack.layers.any((l) => l.id == _canvasTextLayerId);
      if (exists) {
        _syncLiveTextToCanvas();
        return;
      }
      _canvasTextLayerId = null;
    }

    final info = s.imageInfo;
    final cx = (info?.width ?? 400) / 2;
    final cy = (info?.height ?? 600) / 2;
    final id = newLayerId();
    _canvasTextLayerId = id;
    s.pushLayerUndo();
    final layer = _textStyle.toLayer(
      id: id,
      transform: LayerTransform(
        centerX: cx,
        centerY: cy,
        opacity: _textOpacity,
      ),
      text: _textCtrl.text,
      backgroundStyle: _bgStyle,
    );
    s.layerStack.add(layer, select: true);
    s.layerStack.bumpRevision();
    s.notifyLayerChanged();
  }

  void _syncLiveTextToCanvas() {
    if (!s.hasImage || s.busy) return;
    if (_canvasTextLayerId == null) {
      _ensureLiveTextLayer();
      return;
    }
    if (!s.layerStack.layers.any((l) => l.id == _canvasTextLayerId)) {
      _canvasTextLayerId = null;
      _ensureLiveTextLayer();
      return;
    }

    replaceTextLayerInStack(
      session: s,
      layerId: _canvasTextLayerId!,
      style: _textStyle,
      text: _textCtrl.text,
      backgroundStyle: _bgStyle,
      backgroundColor: const Color(0xE6000000),
    );

    final j = s.layerStack.layers.indexWhere((l) => l.id == _canvasTextLayerId);
    if (j >= 0 && s.layerStack.layers[j] is TextLayer) {
      final layer = s.layerStack.layers[j] as TextLayer;
      layer.transform = layer.transform.copyWith(opacity: _textOpacity);
      s.layerStack.bumpRevision();
      s.notifyLayerChanged();
    }
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
    if (_canvasTextLayerId != null) {
      _syncLiveTextToCanvas();
      s.layerStack.select(_canvasTextLayerId);
      _canvasTextLayerId = null;
      s.notifyLayerChanged();
      return;
    }

    final info = s.imageInfo;
    final cx = (info?.width ?? 400) / 2;
    final cy = (info?.height ?? 600) / 2;
    s.pushLayerUndo();
    s.layerStack.add(
      _textStyle.toLayer(
        id: newLayerId(),
        transform: LayerTransform(centerX: cx, centerY: cy, opacity: _textOpacity),
        text: _textCtrl.text,
        backgroundStyle: _bgStyle,
      ),
      select: true,
    );
    s.notifyLayerChanged();
  }

  @override
  Widget build(BuildContext context) {
    final children = [
      if (!widget.stripHostedExternally) ...[
        _tabRow(),
        const SizedBox(height: LuminaTokens.padMd),
      ],
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  Widget _tabRow() {
    return SegmentedButton<int>(
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(value: 0, label: Text('Emoji'), icon: Icon(Icons.emoji_emotions_outlined, size: 16)),
        ButtonSegment(value: 1, label: Text('Stickers'), icon: Icon(Icons.sticky_note_2_outlined, size: 16)),
        ButtonSegment(value: 2, label: Text('Text'), icon: Icon(Icons.text_fields_rounded, size: 16)),
      ],
      selected: {_tab},
      onSelectionChanged: (s) => _selectTab(s.first),
    );
  }

  void _selectTab(int i) {
    widget.onTabChanged?.call(i);
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
          Text(
            'Text appears on the image as you type',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: LuminaTokens.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _textCtrl,
            decoration: const InputDecoration(
              labelText: 'Caption',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextStyleControls(
            value: _textStyle,
            onChanged: (d) {
              setState(() => _textStyle = d);
              _syncLiveTextToCanvas();
            },
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
            onSelected: (v) {
              setState(() => _bgStyle = v);
              _syncLiveTextToCanvas();
            },
          ),
          LabeledSlider(
            label: 'Opacity',
            value: _textOpacity,
            min: 0.2,
            max: 1,
            divisions: 8,
            display: _textOpacity.toStringAsFixed(2),
            onChanged: (v) {
              setState(() => _textOpacity = v);
              _syncLiveTextToCanvas();
            },
          ),
          PrimaryActionButton(
            icon: Icons.text_fields,
            label: _canvasTextLayerId != null ? 'Place text' : 'Add text',
            enabled: s.hasImage && !s.busy,
            onPressed: _addText,
          ),
        ],
    };
  }

  Widget _emojiGrid(BuildContext context) {
    final cols = _gridColumns(context);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        mainAxisSpacing: LuminaTokens.space2,
        crossAxisSpacing: LuminaTokens.space2,
      ),
      itemCount: StickerCatalog.emojis.length,
      itemBuilder: (context, i) {
        final glyph = StickerCatalog.emojis[i];
        return Material(
          color: LuminaTokens.surfaceContainerHigh.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(LuminaTokens.radiusMd),
          child: InkWell(
            onTap: s.hasImage ? () => _addEmoji(glyph) : null,
            borderRadius: BorderRadius.circular(LuminaTokens.radiusMd),
            child: Center(
              child: Text(
                glyph,
                style: const TextStyle(fontSize: 28, shadows: []),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _stickerGrid(BuildContext context) {
    final cols = _gridColumns(context);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        mainAxisSpacing: LuminaTokens.space2,
        crossAxisSpacing: LuminaTokens.space2,
        childAspectRatio: 1.0,
      ),
      itemCount: StickerCatalog.builtinStickers.length,
      itemBuilder: (context, i) {
        final (key, _) = StickerCatalog.builtinStickers[i];
        return Material(
          color: LuminaTokens.surfaceContainerHigh.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(LuminaTokens.radiusMd),
          child: InkWell(
            onTap: s.hasImage ? () => _addBuiltinSticker(key) : null,
            borderRadius: BorderRadius.circular(LuminaTokens.radiusMd),
            child: Padding(
              padding: const EdgeInsets.all(LuminaTokens.space2),
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
        );
      },
    );
  }

  int _gridColumns(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w >= 400) return 6;
    if (w >= 320) return 5;
    return 4;
  }
}
