import 'package:flutter/material.dart';

import 'crop_controller.dart';
import 'draw_placement.dart';
import 'editor_session.dart';
import 'models/overlay_layer.dart';
import 'layout/editor_layout.dart';
import 'layout/mobile_editor_chrome.dart';
import 'overlay_placement.dart';
import 'panels/tool_panels.dart';
import 'rust_image_editor_config.dart';
import 'theme/editor_motion.dart';
import 'theme/lumina_tokens.dart';
import 'widgets/compare_hold_button.dart';
import 'panels/text_layer_edit_sheet.dart';
import 'services/sticker_image_import.dart';
import 'widgets/editor_tool_rail.dart';
import 'widgets/live_preview.dart';

/// Full-screen editor layout (preview + tool rail). Prefer [RustImageEditorWidget] for drop-in use.
class RustImageEditorView extends StatefulWidget {
  const RustImageEditorView({
    super.key,
    required this.config,
    required this.session,
  });

  final RustImageEditorConfig config;
  final EditorSession session;

  /// Alias for apps that embedded the example [EditorScreen] name.
  static Widget screen({
    required RustImageEditorConfig config,
    required EditorSession session,
  }) =>
      RustImageEditorView(config: config, session: session);

  @override
  State<RustImageEditorView> createState() => _RustImageEditorViewState();
}

/// @deprecated Use [RustImageEditorView]
typedef EditorScreen = RustImageEditorView;

class _RustImageEditorViewState extends State<RustImageEditorView> {
  final _drawPlacement = DrawPlacementController();
  final _overlayPlacement = OverlayPlacementController();
  final _cropController = CropController();
  late EditorTool _tool;
  bool _compareHeld = false;

  EditorSession get _session => widget.session;
  List<EditorTool> get _tools => widget.config.enabledTools;

  /// Fallback when [RustImageEditorConfig.enabledTools] is empty (avoids crashes).
  static const EditorTool _fallbackTool = EditorTool.import;

  EditorTool _initialTool() {
    final tools = _tools;
    return tools.isNotEmpty ? tools.first : _fallbackTool;
  }

  EditorTool _toolForEnabledList() {
    final tools = _tools;
    if (tools.isEmpty) return _fallbackTool;
    return tools.contains(_tool) ? _tool : tools.first;
  }

  bool _useWideLayout(BuildContext context) {
    final mode = widget.config.layoutMode;
    if (mode == EditorLayoutMode.sidebar) return true;
    if (mode == EditorLayoutMode.immersive) return false;
    return MediaQuery.sizeOf(context).width >= 900;
  }

  @override
  void initState() {
    super.initState();
    _tool = _initialTool();
    _session.addListener(_onSessionChanged);
  }

  @override
  void didUpdateWidget(covariant RustImageEditorView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config.enabledTools != widget.config.enabledTools) {
      final resolved = _toolForEnabledList();
      if (resolved != _tool) {
        setState(() => _tool = resolved);
      }
    }
  }

  @override
  void dispose() {
    _session.removeListener(_onSessionChanged);
    _drawPlacement.dispose();
    _overlayPlacement.dispose();
    _cropController.dispose();
    super.dispose();
  }

  void _onSessionChanged() {
    final info = _session.imageInfo;
    if (info != null) {
      // Defer placement sync so we never notify nested listenables during
      // [ChangeNotifier.notifyListeners] (avoids rebuild feedback loops).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _drawPlacement.syncImageSize(info.width, info.height);
        _overlayPlacement.syncImageSize(info.width, info.height);
        // Crop overlay maps to preview pixels (may be ≤ full image when RGBA pipeline).
        final preview = _session.previewRgba;
        _cropController.syncImageSize(
          preview?.width ?? info.width,
          preview?.height ?? info.height,
        );
      });
    }
    final bytes = _session.displayBytes;
    if (bytes != null) {
      widget.config.onImageChanged?.call(_session, bytes);
    }
  }

  void _startCompareHold() {
    if (!widget.config.showCompare || !_session.hasImage || _compareHeld) return;
    setState(() => _compareHeld = true);
  }

  void _endCompareHold() {
    if (!_compareHeld) return;
    setState(() => _compareHeld = false);
  }

  @override
  Widget build(BuildContext context) {
    final wide = _useWideLayout(context);

    return Scaffold(
      backgroundColor: wide ? LuminaTokens.background : LuminaTokens.canvas,
      body: ListenableBuilder(
        listenable: _session.editorChromeListenable,
        builder: (context, _) {
          return wide
              ? SafeArea(child: _buildWide(context))
              : _buildMobile(context);
        },
      ),
    );
  }

  Widget _buildWide(BuildContext context) {
    final extended = MediaQuery.sizeOf(context).width >= 1100;
    return Row(
      children: [
        EditorToolRail(
          tools: _tools,
          selectedTool: _tool,
          extended: extended,
          onSelected: (t) => setState(() => _tool = t),
        ),
        const VerticalDivider(width: 1),
        Expanded(flex: 3, child: _buildPreviewColumn(context, immersive: false)),
        Expanded(
          flex: 2,
          child: ColoredBox(
            color: LuminaTokens.surfaceContainerLow,
            child: _toolPanelHost(compact: false),
          ),
        ),
      ],
    );
  }

  Widget _buildMobile(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom + 72;

    return MobileEditorLayout(
      config: widget.config,
      session: _session,
      cropController: _cropController,
      tools: _tools,
      selectedTool: _tool,
      onToolSelected: (t) => setState(() => _tool = t),
      compareHeld: _compareHeld,
      onCompareHoldStart: _startCompareHold,
      onCompareHoldEnd: _endCompareHold,
      onExport: _session.hasImage && !_session.busy
          ? () => _session.exportAndSave(customSave: widget.config.onExport)
          : null,
      toolBarPlacement: widget.config.toolBarPlacement,
      preview: _buildPreview(
        context,
        immersive: true,
        overlayBottomInset: bottomInset,
      ),
      toolPanelBuilder: (scroll) => _toolPanelHost(
        scrollController: scroll,
        compact: true,
      ),
    );
  }

  ToolPanelHost _toolPanelHost({
    ScrollController? scrollController,
    bool compact = false,
  }) {
    return ToolPanelHost(
      tool: _tool,
      session: _session,
      config: widget.config,
      drawPlacement: _drawPlacement,
      overlayPlacement: _overlayPlacement,
      cropController: _cropController,
      scrollController: scrollController,
      compact: compact,
    );
  }

  Widget _buildPreviewColumn(BuildContext context, {required bool immersive}) {
    return Padding(
      padding: immersive ? EdgeInsets.zero : const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!immersive) ...[
            _buildTopBar(context),
            _MetaChips(session: _session),
            const SizedBox(height: 8),
          ],
          Expanded(
            child: _buildPreview(
              context,
              immersive: immersive,
              overlayBottomInset: 0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview(
    BuildContext context, {
    required bool immersive,
    required double overlayBottomInset,
  }) {
    final hasUserImageStickers = _session.layerStack.layers.any(
      (l) => l is StickerLayer && l.userBytes != null && l.userBytes!.isNotEmpty,
    );
    final layerTool = _tool == EditorTool.stickers ||
        _tool == EditorTool.paint ||
        _tool == EditorTool.layers ||
        hasUserImageStickers;
    final info = _session.imageInfo;
    final iw = info?.width ?? _session.previewRgba?.width ?? 0;
    final ih = info?.height ?? _session.previewRgba?.height ?? 0;

    return LivePreview(
      immersive: immersive,
      overlayBottomInset: overlayBottomInset,
      bytes: _session.displayBytes,
      previewRgba: _session.previewRgba,
      useRgbaPreview: _session.useRgbaPreview,
      compareBytes: _session.sourceBytes,
      showCompare: _compareHeld && widget.config.showCompare,
      processing: _session.processing,
      blocking: _session.blocking,
      placement: _tool == EditorTool.draw ? _drawPlacement : null,
      cropController: _tool == EditorTool.transform ? _cropController : null,
      overlayPlacement:
          _tool == EditorTool.overlay ? _overlayPlacement : null,
      onOverlayPositionChanged: _tool == EditorTool.overlay
          ? () => _session.scheduleOverlayLivePreview(
                x: _overlayPlacement.x,
                y: _overlayPlacement.y,
              )
          : null,
      layerStack: _session.layerStack,
      layerEditorActive: layerTool && _session.hasImage && iw > 0,
      paintMode: _tool == EditorTool.paint,
      imageWidth: iw,
      imageHeight: ih,
      onLayerStackChanged: _session.notifyLayerChanged,
      onTransformBegin: _session.pushLayerUndo,
      onUserImageStickerTap: (layer) =>
          StickerImageImport.pickShapeForLayer(context, _session, layer),
      onTextLayerDoubleTap: (layer) => TextLayerEditSheet.show(
            context,
            session: _session,
            layer: layer,
          ),
      onPaintStroke: (pts, {required Size childSize}) => _session.addPaintStroke(
            pts,
            imageWidth: iw,
            imageHeight: ih,
            childSize: childSize,
          ),
      onActiveStrokeUpdate: _session.setActivePaintStroke,
      activePaintStrokeListenable: _session.activePaintStrokeListenable,
      activePaintColor: _session.paintColor,
      activePaintWidth: _session.paintStrokeWidth,
      activePaintOpacity: _session.paintStrokeOpacity,
      activePaintBrush: _session.paintBrush,
      emptyHint: immersive ? 'Tap Import to open a photo' : 'No image selected',
    );
  }

  Widget _buildTopBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.config.title.toUpperCase(),
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                AnimatedSwitcher(
                  duration: EditorMotion.fast,
                  child: Text(
                    _session.status,
                    key: ValueKey(_session.status),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ),
              ],
            ),
          ),
          if (_tool == EditorTool.transform && _session.hasImage)
            FilledButton(
              onPressed: _session.busy
                  ? null
                  : () => _session.applyCrop(crop: _cropController),
              child: const Text('Done'),
            ),
          IconButton(
            tooltip: 'Undo',
            onPressed: _session.canUndo && !_session.busy ? _session.undo : null,
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            tooltip: 'Redo',
            onPressed: _session.canRedo && !_session.busy ? _session.redo : null,
            icon: const Icon(Icons.redo),
          ),
          if (widget.config.showCompare)
            CompareHoldButton(
              enabled: _session.hasImage,
              active: _compareHeld,
              onHoldStart: _startCompareHold,
              onHoldEnd: _endCompareHold,
            ),
        ],
      ),
    );
  }
}

class _MetaChips extends StatelessWidget {
  const _MetaChips({required this.session});

  final EditorSession session;

  @override
  Widget build(BuildContext context) {
    if (!session.hasImage) {
      return const SizedBox.shrink();
    }

    final gpu = session.gpuInfo;
    final labels = <String>[
      session.dimensionsLabel,
      session.sizeLabel,
      if (session.rgbaPipeline) 'RGBA',
      if (session.editOpCount > 0) '${session.editOpCount} ops',
      if (gpu?.available == true) gpu!.api,
    ];

    return AnimatedSize(
      duration: EditorMotion.medium,
      curve: EditorMotion.enter,
      alignment: Alignment.centerLeft,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < labels.length; i++)
              _AnimatedChip(
                key: ValueKey(labels[i]),
                label: labels[i],
                index: i,
              ),
          ],
        ),
      ),
    );
  }
}

class _AnimatedChip extends StatelessWidget {
  const _AnimatedChip({
    super.key,
    required this.label,
    required this.index,
  });

  final String label;
  final int index;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: EditorMotion.medium + Duration(milliseconds: 40 * index),
      curve: EditorMotion.enter,
      builder: (context, value, child) {
        final t = value.clamp(0.0, 1.0);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 10 * (1 - t)),
            child: child,
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.only(right: 8),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.7),
            border: Border.all(color: scheme.outline.withValues(alpha: 0.12)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

