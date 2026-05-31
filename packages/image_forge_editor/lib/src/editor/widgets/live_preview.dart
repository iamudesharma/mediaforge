import 'dart:typed_data';

import 'package:image_forge_camera/image_forge_camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_forge/image_forge.dart';
import 'package:image_forge_editor/src/image_forge_editor.dart';

import '../crop_controller.dart';
import '../draw_placement.dart';
import '../models/layer_stack.dart';
import '../models/overlay_layer.dart';
import '../overlay_placement.dart';
import '../theme/editor_motion.dart';
import '../theme/lumina_tokens.dart';
import 'editor_animations.dart';
import 'cached_preview_image.dart';
import 'layer_editor_overlay.dart';
import 'overlay_placement_layer.dart';
import 'package:pixel_surface/pixel_surface.dart';
import 'rgba_preview_image.dart';
import 'crop_overlay.dart';
import 'placement_overlay.dart';
import 'swipe_look_filter.dart';
import 'swipe_look_particles.dart';
import 'swipe_beauty_look.dart';
import '../editor_session.dart';
import 'face_landmark_overlay.dart';

class LivePreview extends StatefulWidget {
  /// For widget tests (mobile chrome / sheet insets).
  static const widgetKey = Key('lumina_live_preview');

  const LivePreview({
    super.key = widgetKey,
    required this.bytes,
    required this.compareBytes,
    this.compareRgba,
    required this.showCompare,
    required this.processing,
    this.blocking = false,
    this.previewRgba,
    this.useRgbaPreview = false,
    this.placement,
    this.cropController,
    this.overlayPlacement,
    this.onOverlayPositionChanged,
    this.emptyHint = 'No image selected',
    this.immersive = false,
    this.overlayBottomInset = 0,
    this.layerStack,
    this.showLayerOverlay = false,
    this.layerInteractionEnabled = false,
    this.layersToolActive = false,
    this.paintMode = false,
    this.imageWidth = 0,
    this.imageHeight = 0,
    this.onLayerStackChanged,
    this.onTransformBegin,
    this.onUserImageStickerTap,
    this.onTextLayerDoubleTap,
    this.onPaintStroke,
    this.onActiveStrokeUpdate,
    this.activePaintStrokeListenable,
    this.activePaintColor,
    this.activePaintWidth,
    this.activePaintOpacity,
    this.activePaintBrush,
    this.activePaintFilled = false,
    this.hiddenTextLayerId,
    this.eraserMode = EraserMode.partial,
    this.onObjectErase,
    this.enableSwipeLooks = false,
    this.swipeLooksEnabled = false,
    this.swipeLookStrength = 1.0,
    this.swipeLookSession,
    this.enableSwipeBeautyLooks = false,
    this.swipeBeautyLooksEnabled = false,
    this.beautySession,
    this.useGpuTexturePreview = false,
    this.gpuTextureId,
    this.showFaceLandmarks = false,
    this.faceLandmarks,
    this.liveCameraController,
    this.liveShowBeautyPreview = false,
    this.livePreviewAspect = CropAspect.original,
    this.liveBeautyPending = false,
    this.liveBeautyLabel,
  });

  final Uint8List? bytes;
  final Uint8List? compareBytes;
  final RgbaImageBuffer? compareRgba;
  final RgbaImageBuffer? previewRgba;
  final bool useRgbaPreview;
  final bool showCompare;
  final bool processing;
  final bool blocking;
  final DrawPlacementController? placement;
  final CropController? cropController;
  final OverlayPlacementController? overlayPlacement;
  final VoidCallback? onOverlayPositionChanged;
  final String emptyHint;

  /// Full-bleed canvas (black letterbox) for mobile immersive layout.
  final bool immersive;

  /// Extra bottom inset for floating tool rail (zoom reset button).
  final double overlayBottomInset;

  final LayerStack? layerStack;

  /// Draw stickers, text, emoji, and paint strokes on the canvas (all tools).
  final bool showLayerOverlay;

  /// Drag, pinch, and layer gestures (Stickers / Paint / Layers only).
  final bool layerInteractionEnabled;
  final bool layersToolActive;
  final bool paintMode;
  final int imageWidth;
  final int imageHeight;
  final VoidCallback? onLayerStackChanged;
  final VoidCallback? onTransformBegin;
  final void Function(StickerLayer layer)? onUserImageStickerTap;
  final void Function(TextLayer layer)? onTextLayerDoubleTap;
  final void Function(List<Offset> points, {required Size childSize})?
      onPaintStroke;
  final void Function(List<Offset> points)? onActiveStrokeUpdate;
  final ValueListenable<List<Offset>>? activePaintStrokeListenable;
  final Color? activePaintColor;
  final double? activePaintWidth;
  final double? activePaintOpacity;
  final PaintBrushKind? activePaintBrush;
  final bool activePaintFilled;
  final String? hiddenTextLayerId;
  final EraserMode eraserMode;
  final void Function(Offset imagePixel)? onObjectErase;
  final bool enableSwipeLooks;
  final bool swipeLooksEnabled;
  final double swipeLookStrength;
  final EditorSession? swipeLookSession;
  final bool enableSwipeBeautyLooks;
  final bool swipeBeautyLooksEnabled;
  final EditorSession? beautySession;
  final bool useGpuTexturePreview;
  final int? gpuTextureId;
  final bool showFaceLandmarks;
  final List<Landmark2D>? faceLandmarks;
  final CameraController? liveCameraController;
  final bool liveShowBeautyPreview;
  final CropAspect livePreviewAspect;
  final bool liveBeautyPending;
  final String? liveBeautyLabel;

  @override
  State<LivePreview> createState() => _LivePreviewState();
}

class _LivePreviewState extends State<LivePreview> {
  final _controller = TransformationController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTransformChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTransformChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onTransformChanged() {
    // Overlays that depend on [TransformationController] listen via
    // [ListenableBuilder] in [_PreviewContent]; avoid rebuilding the image subtree.
  }

  static Object _bytesFingerprint(Uint8List bytes) {
    final mid = bytes.length ~/ 2;
    return Object.hash(
      bytes.length,
      bytes.first,
      bytes.last,
      bytes[mid],
      identityHashCode(bytes),
    );
  }

  Object? get _imageKey {
    final r = widget.previewRgba;
    if (widget.useRgbaPreview && r != null) {
      return Object.hash('r', r.width, r.height, identityHashCode(r.pixels));
    }
    final b = widget.bytes;
    if (b != null) return Object.hash('b', _bytesFingerprint(b));
    final cam = widget.liveCameraController;
    if (cam != null && cam.value.isInitialized) {
      return Object.hash('cam', cam.description.name);
    }
    if (r != null) {
      return Object.hash('r', r.width, r.height, identityHashCode(r.pixels));
    }
    return null;
  }

  bool get _liveCameraReady =>
      widget.liveCameraController?.value.isInitialized ?? false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final canvas = Stack(
      fit: StackFit.expand,
      children: [
        if (widget.immersive)
          const ColoredBox(color: LuminaTokens.canvas)
        else
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  scheme.primary.withValues(alpha: 0.04),
                  scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                  scheme.surface.withValues(alpha: 0.85),
                ],
              ),
            ),
            child: CustomPaint(painter: _CheckerPainter()),
          ),
          AnimatedSwitcher(
            duration: EditorMotion.medium,
            switchInCurve: EditorMotion.enter,
            switchOutCurve: EditorMotion.exit,
            child: widget.bytes == null &&
                    widget.previewRgba == null &&
                    !_liveCameraReady &&
                    widget.liveCameraController == null &&
                    (widget.gpuTextureId == null || widget.gpuTextureId! <= 0)
                ? _EmptyPreview(
                    key: const ValueKey('empty'),
                    hint: widget.emptyHint,
                  )
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      _PreviewContent(
                        key: ValueKey(_imageKey ?? widget.previewRgba),
                        bytes: widget.bytes,
                        previewRgba: widget.previewRgba,
                        useRgbaPreview: widget.useRgbaPreview,
                        useGpuTexturePreview: widget.useGpuTexturePreview,
                        gpuTextureId: widget.gpuTextureId,
                        liveCameraController: widget.liveCameraController,
                        liveShowBeautyPreview: widget.liveShowBeautyPreview,
                        livePreviewAspect: widget.livePreviewAspect,
                        liveBeautyPending: widget.liveBeautyPending,
                        liveBeautyLabel: widget.liveBeautyLabel,
                        compareBytes: widget.compareBytes,
                        compareRgba: widget.compareRgba,
                        showCompare: widget.showCompare,
                    placement: widget.placement,
                    cropController: widget.cropController,
                    overlayPlacement: widget.overlayPlacement,
                    onOverlayPositionChanged: widget.onOverlayPositionChanged,
                    controller: _controller,
                    layerStack: widget.layerStack,
                    showLayerOverlay: widget.showLayerOverlay,
                    layerInteractionEnabled: widget.layerInteractionEnabled,
                    layersToolActive: widget.layersToolActive,
                    paintMode: widget.paintMode,
                    imageWidth: widget.imageWidth,
                    imageHeight: widget.imageHeight,
                    onLayerStackChanged: widget.onLayerStackChanged,
                    onTransformBegin: widget.onTransformBegin,
                    onUserImageStickerTap: widget.onUserImageStickerTap,
                    onTextLayerDoubleTap: widget.onTextLayerDoubleTap,
                    onPaintStroke: widget.onPaintStroke,
                    onActiveStrokeUpdate: widget.onActiveStrokeUpdate,
                    activePaintStrokeListenable:
                        widget.activePaintStrokeListenable,
                    activePaintColor: widget.activePaintColor,
                    activePaintWidth: widget.activePaintWidth,
                    activePaintOpacity: widget.activePaintOpacity,
                    activePaintBrush: widget.activePaintBrush,
                    activePaintFilled: widget.activePaintFilled,
                    hiddenTextLayerId: widget.hiddenTextLayerId,
                    eraserMode: widget.eraserMode,
                    onObjectErase: widget.onObjectErase,
                      ),
                      if (widget.showFaceLandmarks &&
                          widget.faceLandmarks != null &&
                          widget.imageWidth > 0 &&
                          widget.imageHeight > 0)
                        IgnorePointer(
                          child: FaceLandmarkOverlay(
                            landmarks: widget.faceLandmarks!,
                            imageWidth: widget.imageWidth,
                            imageHeight: widget.imageHeight,
                          ),
                        ),
                      if (widget.liveBeautyLabel != null)
                        Positioned(
                          top: 12,
                          left: 0,
                          right: 0,
                          child: IgnorePointer(
                            child: Center(
                              child: _LiveBeautyChip(
                                label: widget.liveBeautyLabel!,
                                pending: widget.liveBeautyPending,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
          AnimatedSwitcher(
            duration: EditorMotion.fast,
            child: widget.blocking
                ? _BlockingOverlay(key: const ValueKey('block'))
                : const SizedBox.shrink(key: ValueKey('noblock')),
          ),
          if (widget.processing && !widget.blocking)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: ShimmerProgressBar(color: scheme.primary),
            ),
          Positioned(
            right: widget.immersive ? 12 : 8,
            bottom: 8 + widget.overlayBottomInset,
            child: _ZoomResetButton(
              onPressed: () {
                _controller.value = Matrix4.identity();
              },
              light: widget.immersive,
            ),
          ),
        ],
    );

    if (widget.immersive) {
      return _wrapSwipeBeauty(_wrapSwipeLook(canvas));
    }
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: _wrapSwipeBeauty(_wrapSwipeLook(canvas)),
    );
  }

  Widget _wrapSwipeBeauty(Widget canvas) {
    if (!widget.enableSwipeBeautyLooks ||
        widget.beautySession == null ||
        !widget.swipeBeautyLooksEnabled) {
      return canvas;
    }
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        return SwipeBeautyLookLayer(
          session: widget.beautySession!,
          enabled: widget.swipeBeautyLooksEnabled,
          viewerScale: _controller.value.getMaxScaleOnAxis(),
          child: canvas,
        );
      },
    );
  }

  Widget _wrapSwipeLook(Widget canvas) {
    if (!widget.enableSwipeLooks ||
        widget.swipeLookSession == null ||
        !widget.swipeLooksEnabled) {
      return canvas;
    }
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        return SwipeLookFilterLayer(
          session: widget.swipeLookSession!,
          enabled: widget.swipeLooksEnabled,
          viewerScale: _controller.value.getMaxScaleOnAxis(),
          strength: widget.swipeLookStrength,
          child: SwipeLookParticleOverlay(
            active: swipeLookUsesParticles(
              widget.swipeLookSession!.previewSwipeLook ??
                  widget.swipeLookSession!.committedSwipeLookPreset,
            ),
            child: canvas,
          ),
        );
      },
    );
  }
}

class _EmptyPreview extends StatelessWidget {
  const _EmptyPreview({super.key, required this.hint});

  final String hint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PulseWidget(
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.primary.withValues(alpha: 0.08),
                border: Border.all(color: scheme.primary.withValues(alpha: 0.2)),
              ),
              child: Icon(Icons.image_outlined, size: 48, color: scheme.primary),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            hint,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

class _PreviewContent extends StatelessWidget {
  static Object _bytesKey(Uint8List bytes) =>
      Object.hash(bytes.length, bytes.first, bytes.last);

  const _PreviewContent({
    super.key,
    required this.bytes,
    required this.previewRgba,
    required this.useRgbaPreview,
    required this.useGpuTexturePreview,
    required this.gpuTextureId,
    this.liveCameraController,
    this.liveShowBeautyPreview = false,
    this.livePreviewAspect = CropAspect.original,
    this.liveBeautyPending = false,
    this.liveBeautyLabel,
    required this.compareBytes,
    this.compareRgba,
    required this.showCompare,
    required this.placement,
    required this.cropController,
    required this.overlayPlacement,
    required this.onOverlayPositionChanged,
    required this.controller,
    this.layerStack,
    this.showLayerOverlay = false,
    this.layerInteractionEnabled = false,
    this.layersToolActive = false,
    this.paintMode = false,
    this.imageWidth = 0,
    this.imageHeight = 0,
    this.onLayerStackChanged,
    this.onTransformBegin,
    this.onUserImageStickerTap,
    this.onTextLayerDoubleTap,
    this.onPaintStroke,
    this.onActiveStrokeUpdate,
    this.activePaintStrokeListenable,
    this.activePaintColor,
    this.activePaintWidth,
    this.activePaintOpacity,
    this.activePaintBrush,
    this.activePaintFilled = false,
    this.hiddenTextLayerId,
    required this.eraserMode,
    this.onObjectErase,
  });

  final Uint8List? bytes;
  final RgbaImageBuffer? previewRgba;
  final bool useRgbaPreview;
  final bool useGpuTexturePreview;
  final int? gpuTextureId;
  final CameraController? liveCameraController;
  final bool liveShowBeautyPreview;
  final CropAspect livePreviewAspect;
  final bool liveBeautyPending;
  final String? liveBeautyLabel;
  final Uint8List? compareBytes;
  final RgbaImageBuffer? compareRgba;
  final bool showCompare;
  final DrawPlacementController? placement;
  final CropController? cropController;
  final OverlayPlacementController? overlayPlacement;
  final VoidCallback? onOverlayPositionChanged;
  final TransformationController controller;
  final LayerStack? layerStack;
  final bool showLayerOverlay;
  final bool layerInteractionEnabled;
  final bool layersToolActive;
  final bool paintMode;
  final int imageWidth;
  final int imageHeight;
  final VoidCallback? onLayerStackChanged;
  final VoidCallback? onTransformBegin;
  final void Function(StickerLayer layer)? onUserImageStickerTap;
  final void Function(TextLayer layer)? onTextLayerDoubleTap;
  final void Function(List<Offset> points, {required Size childSize})?
      onPaintStroke;
  final void Function(List<Offset> points)? onActiveStrokeUpdate;
  final ValueListenable<List<Offset>>? activePaintStrokeListenable;
  final Color? activePaintColor;
  final double? activePaintWidth;
  final double? activePaintOpacity;
  final PaintBrushKind? activePaintBrush;
  final bool activePaintFilled;
  final String? hiddenTextLayerId;
  final EraserMode eraserMode;
  final void Function(Offset imagePixel)? onObjectErase;

  Widget _frameLiveChild(Widget child, {Size? sourceSize}) {
    final ratio = livePreviewAspect.targetRatio;
    if (ratio == null) {
      return Center(child: child);
    }
    Widget inner = child;
    if (sourceSize != null && sourceSize.width > 0 && sourceSize.height > 0) {
      inner = FittedBox(
        fit: BoxFit.cover,
        alignment: Alignment.center,
        child: SizedBox(
          width: sourceSize.width,
          height: sourceSize.height,
          child: child,
        ),
      );
    }
    return Center(
      child: AspectRatio(
        aspectRatio: ratio,
        child: ClipRect(child: inner),
      ),
    );
  }

  Widget _buildPreviewImage() {
    if (liveShowBeautyPreview &&
        useGpuTexturePreview &&
        gpuTextureId != null &&
        gpuTextureId! > 0) {
      return _frameLiveChild(
        GpuTexturePreview(
          textureId: gpuTextureId!,
          width: imageWidth,
          height: imageHeight,
        ),
        sourceSize: Size(imageWidth.toDouble(), imageHeight.toDouble()),
      );
    }
    if (liveShowBeautyPreview && useRgbaPreview && previewRgba != null) {
      final buf = previewRgba!;
      return _frameLiveChild(
        RgbaPreviewImage(
          key: ValueKey(identityHashCode(buf.pixels)),
          buffer: buf,
          fit: BoxFit.cover,
        ),
        sourceSize: Size(buf.width.toDouble(), buf.height.toDouble()),
      );
    }

    final cam = liveCameraController;
    if (cam != null) {
      return ListenableBuilder(
        listenable: cam,
        builder: (context, _) {
          if (!cam.value.isInitialized) {
            return const Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          final size = cam.value.previewSize;
          final preview = size == null
              ? CameraPreview(cam)
              : SizedBox(
                  width: size.width,
                  height: size.height,
                  child: CameraPreview(cam),
                );
          return _frameLiveChild(
            preview,
            sourceSize: size == null
                ? null
                : Size(size.width.toDouble(), size.height.toDouble()),
          );
        },
      );
    }

    // Still photo: prefer GPU Texture when active (Sprint 22.2 — no RGBA widget).
    if (useGpuTexturePreview &&
        gpuTextureId != null &&
        gpuTextureId! > 0) {
      final w = previewRgba?.width ?? imageWidth;
      final h = previewRgba?.height ?? imageHeight;
      return GpuTexturePreview(
        textureId: gpuTextureId!,
        width: w,
        height: h,
      );
    }
    if (useRgbaPreview && previewRgba != null) {
      return RgbaPreviewImage(
        key: ValueKey(identityHashCode(previewRgba!.pixels)),
        buffer: previewRgba!,
        fit: BoxFit.contain,
      );
    }
    final b = bytes;
    if (b == null) {
      return const SizedBox.shrink();
    }
    return CachedPreviewImage(
      key: ValueKey(_PreviewContent._bytesKey(b)),
      bytes: b,
      fit: BoxFit.contain,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final childSize = constraints.biggest;
        final hasCompare =
            (compareBytes != null && compareBytes!.isNotEmpty) ||
            compareRgba != null;
        final image = RepaintBoundary(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: Opacity(
                  opacity: showCompare ? 0 : 1,
                  child: IgnorePointer(
                    ignoring: showCompare,
                    child: _buildPreviewImage(),
                  ),
                ),
              ),
              if (hasCompare)
                Center(
                  child: Opacity(
                    opacity: showCompare ? 1 : 0,
                    child: IgnorePointer(
                      ignoring: !showCompare,
                      child: compareRgba != null
                          ? RgbaPreviewImage(
                              key: const ValueKey('compare_beauty_rgba'),
                              buffer: compareRgba!,
                              fit: BoxFit.contain,
                            )
                          : CachedPreviewImage(
                              key: const ValueKey('compare_original'),
                              bytes: compareBytes!,
                              fit: BoxFit.contain,
                            ),
                    ),
                  ),
                ),
            ],
          ),
        );

        // Frozen preview subtree — placement [ListenableBuilder] must not close
        // over `content` after we wrap it in a [Stack] (infinite nest on zoom).
        final previewBase = Center(child: image);
        Widget content = previewBase;
        final needsViewerTransform = placement != null ||
            cropController != null ||
            overlayPlacement != null ||
            showLayerOverlay;

        if (placement != null || cropController != null || overlayPlacement != null) {
          content = ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              Widget child = previewBase;
              if (placement != null) {
                child = PlacementOverlay(
                  placement: placement!,
                  childSize: childSize,
                  viewerTransform: controller.value,
                  child: child,
                );
              } else if (cropController != null) {
                child = CropOverlay(
                  crop: cropController!,
                  childSize: childSize,
                  viewerTransform: controller.value,
                  child: child,
                );
              } else if (overlayPlacement != null) {
                child = OverlayPlacementLayer(
                  placement: overlayPlacement!,
                  childSize: childSize,
                  onPositionChanged: onOverlayPositionChanged,
                  child: child,
                );
              }
              return child;
            },
          );
        }

        if (showLayerOverlay &&
            layerStack != null &&
            imageWidth > 0 &&
            imageHeight > 0) {
          Widget overlayChild = needsViewerTransform
              ? ListenableBuilder(
                  listenable: controller,
                  builder: (context, _) {
                    return LayerEditorOverlay(
                      stack: layerStack!,
                      imageWidth: imageWidth,
                      imageHeight: imageHeight,
                      childSize: childSize,
                      viewerTransform: controller.value,
                      paintMode: paintMode,
                      layersToolActive: layersToolActive,
                      eraserMode: eraserMode,
                      onStackChanged: onLayerStackChanged ?? () {},
                      onTransformBegin: onTransformBegin,
                      onUserImageStickerTap: onUserImageStickerTap,
                      onTextLayerDoubleTap: onTextLayerDoubleTap,
                      onPaintStroke: onPaintStroke,
                      onActiveStrokeUpdate: onActiveStrokeUpdate,
                      activePaintStrokeListenable: activePaintStrokeListenable,
                      activePaintColor: activePaintColor,
                      activePaintWidth: activePaintWidth,
                      activePaintOpacity: activePaintOpacity,
                      activePaintBrush: activePaintBrush,
                      activePaintFilled: activePaintFilled,
                      hiddenTextLayerId: hiddenTextLayerId,
                      onObjectErase: onObjectErase,
                    );
                  },
                )
              : LayerEditorOverlay(
                  stack: layerStack!,
                  imageWidth: imageWidth,
                  imageHeight: imageHeight,
                  childSize: childSize,
                  viewerTransform: controller.value,
                  paintMode: paintMode,
                  layersToolActive: layersToolActive,
                  eraserMode: eraserMode,
                  onStackChanged: onLayerStackChanged ?? () {},
                  onTransformBegin: onTransformBegin,
                  onUserImageStickerTap: onUserImageStickerTap,
                  onTextLayerDoubleTap: onTextLayerDoubleTap,
                  onPaintStroke: onPaintStroke,
                  onActiveStrokeUpdate: onActiveStrokeUpdate,
                  activePaintStrokeListenable: activePaintStrokeListenable,
                  activePaintColor: activePaintColor,
                  activePaintWidth: activePaintWidth,
                  activePaintOpacity: activePaintOpacity,
                  activePaintBrush: activePaintBrush,
                  activePaintFilled: activePaintFilled,
                  hiddenTextLayerId: hiddenTextLayerId,
                  onObjectErase: onObjectErase,
                );
          // Read-only layer preview on crop/filter/etc.; paint must keep receiving pointers.
          if (!layerInteractionEnabled && !paintMode) {
            overlayChild = IgnorePointer(child: overlayChild);
          }
          content = Stack(
            fit: StackFit.expand,
            children: [
              content,
              RepaintBoundary(child: overlayChild),
            ],
          );
        }

        // Disable InteractiveViewer pan/scale when layer gestures or paint are active.
        // Overlay uses targeted hit targets so pinch/pan on the canvas still zooms.
        final viewerInteractive = placement == null &&
            cropController == null &&
            !paintMode &&
            !layerInteractionEnabled;

        return InteractiveViewer(
          transformationController: controller,
          minScale: 0.5,
          maxScale: 6,
          panEnabled: viewerInteractive,
          scaleEnabled: viewerInteractive,
          child: content,
        );
      },
    );
  }
}

class _BlockingOverlay extends StatelessWidget {
  const _BlockingOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black54,
      child: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.85, end: 1),
          duration: EditorMotion.medium,
          curve: EditorMotion.spring,
          builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
          child: Material(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 36,
                    height: 36,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Loading…',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: Colors.white,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LiveBeautyChip extends StatelessWidget {
  const _LiveBeautyChip({
    required this.label,
    required this.pending,
  });

  final String label;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (pending)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: scheme.primary,
                  ),
                ),
              ),
            Text(
              pending ? '$label · detecting…' : label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Colors.white,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ZoomResetButton extends StatefulWidget {
  const _ZoomResetButton({required this.onPressed, this.light = false});

  final VoidCallback onPressed;
  final bool light;

  @override
  State<_ZoomResetButton> createState() => _ZoomResetButtonState();
}

class _ZoomResetButtonState extends State<_ZoomResetButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        scale: _hovered ? 1.08 : 1,
        duration: EditorMotion.fast,
        child: Material(
          color: widget.light
              ? Colors.black.withValues(alpha: _hovered ? 0.65 : 0.45)
              : scheme.surface.withValues(alpha: _hovered ? 0.95 : 0.85),
          borderRadius: BorderRadius.circular(20),
          elevation: 0,
          shadowColor: Colors.transparent,
          child: IconButton(
            tooltip: 'Reset zoom',
            icon: Icon(
              Icons.center_focus_strong,
              size: 20,
              color: widget.light ? Colors.white : null,
            ),
            onPressed: widget.onPressed,
          ),
        ),
      ),
    );
  }
}

class _CheckerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const tile = 12.0;
    final light = Paint()..color = const Color(0xFF1A1D26);
    final dark = Paint()..color = const Color(0xFF14171F);
    for (var y = 0.0; y < size.height; y += tile) {
      for (var x = 0.0; x < size.width; x += tile) {
        final isLight = ((x / tile).floor() + (y / tile).floor()) % 2 == 0;
        canvas.drawRect(
          Rect.fromLTWH(x, y, tile, tile),
          isLight ? light : dark,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
