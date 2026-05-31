import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'crop_controller.dart';
import 'state/editor_providers.dart';
import 'draw_placement.dart';
import 'editor_session.dart';
import 'models/overlay_layer.dart';
import 'layout/editor_layout.dart';
import 'layout/editor_overlay_panel.dart';
import 'layout/editor_overlay_state.dart';
import 'layout/canvas_floating_chrome.dart';
import 'layout/mobile_editor_chrome.dart';
import 'layout/tool_context_strip.dart';
import 'overlay_placement.dart';
import 'panels/text_layer_edit_sheet.dart';
import 'panels/tool_panels.dart';
import 'image_forge_editor_config.dart';
import 'models/beauty_params.dart';
import 'services/beauty_look_names.dart';
import 'theme/editor_motion.dart';
import 'theme/lumina_tokens.dart';
import 'widgets/compare_hold_button.dart';
import 'services/face_analysis_service.dart';
import 'package:image_forge_camera/image_forge_camera.dart';
import 'services/sticker_image_import.dart';
import 'services/paint_hit_test.dart';
import 'widgets/editor_tool_rail.dart';
import 'widgets/live_preview.dart';

/// Full-screen editor layout (preview + tool rail). Prefer [RustImageEditorWidget] for drop-in use.
class RustImageEditorView extends ConsumerStatefulWidget {
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
      ProviderScope(
        overrides: [
          editorSessionProvider.overrideWithValue(session),
        ],
        child: RustImageEditorView(config: config, session: session),
      );

  @override
  ConsumerState<RustImageEditorView> createState() => _RustImageEditorViewState();
}

/// @deprecated Use [RustImageEditorView]
typedef EditorScreen = RustImageEditorView;

class _RustImageEditorViewState extends ConsumerState<RustImageEditorView> {
  final _drawPlacement = DrawPlacementController();
  final _overlayPlacement = OverlayPlacementController();
  final _cropController = CropController();
  late EditorTool _tool;
  bool _compareHeld = false;
  EditorOverlayState _overlay = const EditorOverlayState.none();
  int _stickersTab = 0;
  AdjustControlKind _adjustKind = AdjustControlKind.brightness;
  Completer<StickerShapeMask?>? _shapeMaskCompleter;

  EditorSession get _session => ref.watch(editorSessionProvider);
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
    widget.session.addListener(_onSessionChanged);
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
    widget.session.removeListener(_onSessionChanged);
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
        // Overlay/crop map to preview pixels (edit-scale when RGBA pipeline is active).
        final preview = _session.previewRgba;
        final pw = preview?.width ?? info.width;
        final ph = preview?.height ?? info.height;
        _overlayPlacement.syncImageSize(pw, ph);
        _cropController.syncImageSize(pw, ph);
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
    widget.config.onCompareHoldStart?.call();
  }

  void _endCompareHold() {
    if (!_compareHeld) return;
    setState(() => _compareHeld = false);
    widget.config.onCompareHoldEnd?.call();
  }

  void _dismissOverlay() {
    if (_overlay.kind == EditorOverlayKind.none) return;
    _shapeMaskCompleter?.complete(null);
    _shapeMaskCompleter = null;
    setState(() => _overlay = const EditorOverlayState.none());
  }

  Future<StickerShapeMask?> _pickShapeMask({
    required int imageCount,
    String? title,
    StickerShapeMask? initial,
    void Function(StickerShapeMask mask)? onPicked,
  }) {
    _shapeMaskCompleter = Completer<StickerShapeMask?>();
    setState(() {
      _overlay = EditorOverlayState(
        kind: EditorOverlayKind.shapeMask,
        shapeMaskImageCount: imageCount,
        shapeMaskTitle: title,
        shapeMaskInitial: initial,
        onShapeMaskSelected: (mask) {
          onPicked?.call(mask);
          _shapeMaskCompleter?.complete(mask);
          _shapeMaskCompleter = null;
          setState(() => _overlay = const EditorOverlayState.none());
        },
      );
    });
    return _shapeMaskCompleter!.future;
  }

  bool _useMobileChrome(BuildContext context) => !_useWideLayout(context);

  String? _liveBeautyChipLabel(EditorSession session) {
    if (!session.liveCameraActive) return null;
    final params = session.liveActiveBeautyParams;
    if (params == null || !params.hasEffect) return null;
    final look = session.previewBeautyLook ?? session.committedBeautyLook;
    if (look != null) return beautyLookLabel(look);
    return 'Beauty';
  }

  Widget _previewListenableBuilder(
    Widget Function(BuildContext context) builder,
  ) {
    return ListenableBuilder(
      listenable: ref.watch(editorCanvasListenableProvider),
      builder: (context, _) => builder(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = _useWideLayout(context);
    final shellListenable = ref.watch(editorChromeListenableProvider);

    return CallbackShortcuts(
      bindings: {
        if (_tool == EditorTool.layers)
          const SingleActivator(LogicalKeyboardKey.keyD, control: true):
              () => _session.duplicateSelection(),
        if (_tool == EditorTool.layers)
          const SingleActivator(LogicalKeyboardKey.keyD, meta: true):
              () => _session.duplicateSelection(),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
      backgroundColor: wide ? LuminaTokens.background : LuminaTokens.canvas,
      body: ListenableBuilder(
        listenable: shellListenable,
        builder: (context, _) {
          return wide
              ? SafeArea(child: _buildWide(context))
              : _buildMobile(context);
        },
      ),
    ),
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
      showMobileMetaOverlay: widget.config.showMobileMetaOverlay,
      canvasChrome: widget.config.showCanvasFloatingChrome
          ? CanvasFloatingChrome(session: _session)
          : null,
      contextStripBuilder: (tool) => ToolContextStrip(
        tool: tool,
        session: _session,
        cropController: _cropController,
        stickersTabIndex: _stickersTab,
        onStickersTabChanged: (i) => setState(() => _stickersTab = i),
        adjustKind: _adjustKind,
        onAdjustKindChanged: (k) => setState(() => _adjustKind = k),
      ),
      overlay: _overlay.kind != EditorOverlayKind.none
          ? EditorOverlayPanel(
              state: _overlay,
              session: _session,
              onDismiss: _dismissOverlay,
            )
          : null,
      previewBuilder: (metrics) => _previewListenableBuilder(
        (context) => _buildPreview(
          context,
          immersive: true,
          overlayBottomInset: metrics.bottomInset,
        ),
      ),
      toolPanelBuilder: () => _toolPanelHost(
        compact: true,
        stripHostedExternally: true,
      ),
    );
  }

  ToolPanelHost _toolPanelHost({
    ScrollController? scrollController,
    bool compact = false,
    bool stripHostedExternally = false,
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
      stripHostedExternally: stripHostedExternally,
      stickersTabIndex: _stickersTab,
      onStickersTabChanged: (i) => setState(() => _stickersTab = i),
      selectedAdjustKind: _adjustKind,
      onAdjustKindChanged: (k) => setState(() => _adjustKind = k),
      onBlankCanvas: _useMobileChrome(context)
          ? () => setState(() {
                _overlay = const EditorOverlayState(
                  kind: EditorOverlayKind.blankCanvas,
                );
              })
          : null,
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
            _MetaChips(session: _session, statusListenable: ref.watch(editorStatusListenableProvider)),
            const SizedBox(height: 8),
          ],
          Expanded(
            child: _previewListenableBuilder(
              (context) => _buildPreview(
                context,
                immersive: immersive,
                overlayBottomInset: 0,
              ),
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
    final hasLayers = _session.layerStack.layers.isNotEmpty;
    final onPaintTool = _tool == EditorTool.paint;
    final info = _session.imageInfo;
    final iw = info?.width ??
        _session.previewRgba?.width ??
        _session.rgbaBuffer?.width ??
        0;
    final ih = info?.height ??
        _session.previewRgba?.height ??
        _session.rgbaBuffer?.height ??
        0;
    final onBeautyTool = _tool == EditorTool.beauty;
    final beautyEraser = onBeautyTool && _session.beautyEraserMode;
    final layerInteraction = _session.hasImage &&
        iw > 0 &&
        !beautyEraser &&
        (onPaintTool ||
            (hasLayers &&
                (_tool == EditorTool.stickers || _tool == EditorTool.layers)));
    final swipeLookEnabled = widget.config.enableSwipeLooks &&
        !_compareHeld &&
        _tool != EditorTool.transform &&
        _tool != EditorTool.draw &&
        _tool != EditorTool.overlay &&
        !onPaintTool &&
        !layerInteraction &&
        !(onBeautyTool && _session.beautyEraserMode);

    final swipeBeautyEnabled = widget.config.enableSwipeBeautyLooks &&
        !_compareHeld &&
        onBeautyTool &&
        !beautyEraser &&
        (_session.hasImage || _session.liveCameraActive) &&
        _session.skinMask != null &&
        FaceAnalysisService.isAnalysisValid(_session.faceAnalysis);

    final beautyCompareActive = onBeautyTool &&
        !beautyEraser &&
        _session.beautyCompareRgba != null &&
        (_session.committedBeautyParams?.hasEffect ?? false);

    return LivePreview(
      immersive: immersive,
      overlayBottomInset: overlayBottomInset,
      bytes: _session.displayBytes,
      previewRgba: _session.previewRgba,
      useRgbaPreview: _session.useRgbaPreview,
      useGpuTexturePreview: _session.useGpuTexturePreview,
      gpuTextureId: _session.gpuTextureId,
      compareBytes: beautyCompareActive ? null : _session.sourceBytes,
      compareRgba: beautyCompareActive ? _session.beautyCompareRgba : null,
      showCompare: _compareHeld && widget.config.showCompare,
      processing: _session.processing,
      blocking: _session.blocking,
      placement: _tool == EditorTool.draw ? _drawPlacement : null,
      cropController: _tool == EditorTool.transform ? _cropController : null,
      overlayPlacement:
          _tool == EditorTool.overlay ? _overlayPlacement : null,
      onOverlayPositionChanged: _tool == EditorTool.overlay
          ? () => _session.scheduleOverlayLivePreview(_overlayPlacement)
          : null,
      layerStack: _session.layerStack,
      showLayerOverlay:
          (hasLayers || onPaintTool || beautyEraser) && _session.hasImage && iw > 0,
      layerInteractionEnabled: layerInteraction,
      layersToolActive: _tool == EditorTool.layers,
      paintMode: onPaintTool || beautyEraser,
      imageWidth: iw,
      imageHeight: ih,
      eraserMode: _session.eraserMode,
      onObjectErase: (pixelOffset) {
        final layers = _session.layerStack.layers;
        final hitIndex = layers.lastIndexWhere(
          (l) => l is PaintStrokeLayer && PaintHitTest.hitTestLayer(l, pixelOffset),
        );
        if (hitIndex < 0) return;
        _session.pushLayerUndo();
        layers.removeAt(hitIndex);
        _session.notifyLayerChanged();
        _session.notifyListeners();
      },
      onLayerStackChanged: _session.notifyLayerChanged,
      onTransformBegin: _session.pushLayerUndo,
      onUserImageStickerTap: (layer) {
        if (_useMobileChrome(context)) {
          StickerImageImport.pickShapeForLayer(
            context,
            _session,
            layer,
            pickShapeMask: () => _pickShapeMask(
              imageCount: 1,
              title: 'Sticker shape',
              initial: layer.shapeMask,
            ),
          );
        } else {
          StickerImageImport.pickShapeForLayer(context, _session, layer);
        }
      },
      onTextLayerDoubleTap: (layer) {
        _session.layerStack.select(layer.id);
        _session.notifyLayerChanged();
        if (_useMobileChrome(context)) {
          setState(() {
            _overlay = EditorOverlayState(
              kind: EditorOverlayKind.textEdit,
              textLayer: layer,
            );
          });
        } else {
          TextLayerEditSheet.show(
            context,
            session: _session,
            layer: layer,
          );
        }
      },
      onPaintStroke: beautyEraser
          ? (pts, {required Size childSize}) => _session.addBeautyEraserStroke(
                pts,
                imageWidth: iw,
                imageHeight: ih,
              )
          : onPaintTool
              ? (pts, {required Size childSize}) => _session.addPaintStroke(
                    pts,
                    imageWidth: iw,
                    imageHeight: ih,
                    childSize: childSize,
                  )
              : null,
      onActiveStrokeUpdate: beautyEraser || onPaintTool
          ? _session.setActivePaintStroke
          : null,
      activePaintStrokeListenable: beautyEraser || onPaintTool
          ? _session.activePaintStrokeListenable
          : null,
      activePaintColor: beautyEraser ? Colors.redAccent : _session.paintColor,
      activePaintWidth: beautyEraser
          ? _session.beautyEraserRadius
          : _session.paintStrokeWidth,
      activePaintOpacity: beautyEraser ? 0.45 : _session.paintStrokeOpacity,
      activePaintBrush: beautyEraser ? PaintBrushKind.eraser : _session.paintBrush,
      activePaintFilled: _session.paintShapeFilled,
      enableSwipeLooks: widget.config.enableSwipeLooks,
      swipeLooksEnabled: swipeLookEnabled,
      swipeLookStrength: widget.config.swipeLookStrength,
      swipeLookSession: _session,
      enableSwipeBeautyLooks: widget.config.enableSwipeBeautyLooks,
      swipeBeautyLooksEnabled: swipeBeautyEnabled,
      beautySession: _session,
      showFaceLandmarks: _session.showDebugFaceLandmarks &&
          FaceAnalysisService.isAnalysisValid(_session.faceAnalysis),
      faceLandmarks: _session.faceAnalysis?.landmarks,
      liveCameraController: (_session.liveCameraActive ||
              _session.liveCameraTransitioning)
          ? LiveCameraService.controller
          : null,
      liveShowBeautyPreview: _session.liveBeautyRgbaActive,
      livePreviewAspect: _session.livePreviewAspect,
      liveBeautyPending: _session.liveBeautyPending,
      liveBeautyLabel: _liveBeautyChipLabel(_session),
      emptyHint: _session.liveCameraTransitioning
          ? 'Starting camera…'
          : _session.liveCameraActive
              ? 'Waiting for camera…'
              : immersive
                  ? 'Tap Import to open a photo'
                  : 'No image selected',
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
                ListenableBuilder(
                  listenable: ref.watch(editorStatusListenableProvider),
                  builder: (context, _) {
                    return AnimatedSwitcher(
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
                    );
                  },
                ),
              ],
            ),
          ),
          if (_session.hasUncommittedLayers)
            FilledButton.tonal(
              onPressed: _session.busy
                  ? null
                  : () => unawaited(_session.commitLayersToCanvas()),
              child: const Text('Apply'),
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
            onPressed: _session.canUndo && !_session.busy
                ? () => unawaited(_session.undo())
                : null,
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            tooltip: 'Redo',
            onPressed: _session.canRedo && !_session.busy
                ? () => unawaited(_session.redo())
                : null,
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
  const _MetaChips({
    required this.session,
    required this.statusListenable,
  });

  final EditorSession session;
  final Listenable statusListenable;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: statusListenable,
      builder: (context, _) {
        if (!session.hasImage && !session.liveCameraActive) {
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

        return _MetaChipsRow(labels: labels);
      },
    );
  }
}

class _MetaChipsRow extends StatelessWidget {
  const _MetaChipsRow({required this.labels});

  final List<String> labels;

  @override
  Widget build(BuildContext context) {
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
                key: ValueKey('meta-$i-${labels[i]}'),
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

