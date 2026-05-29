import 'package:flutter/material.dart';
import 'package:rust_gpu_texture/rust_gpu_texture.dart';

import '../playback/compositor_layout.dart';
import '../runtime/media_runtime.dart';
import '../widgets/rgba_preview_image.dart';
import 'draggable_video_overlays.dart';
import 'video_overlay_item.dart';

/// Letterboxed video preview with timeline-filtered Flutter overlays (Sprint V1.5).
///
/// Same pattern as image editor [LivePreview]: texture/video underneath, `Stack` on top.
/// Overlays use [timelinePlayheadMs] when provided (Sprint 20); export is still source video.
class VideoCompositorCanvas extends StatelessWidget {
  const VideoCompositorCanvas({
    super.key,
    required this.runtime,
    this.overlays = const [],
    /// Master timeline position for overlay visibility (defaults to [MediaRuntime.ptsMs]).
    this.timelinePlayheadMs,
    this.selectedOverlayId,
    this.onOverlayChanged,
    this.onSelectOverlay,
    this.fit = BoxFit.contain,
    this.backgroundColor = Colors.black,
    this.loadingBuilder,
    this.emptyBuilder,
  });

  final MediaRuntime runtime;
  final List<VideoOverlayItem> overlays;
  final int? timelinePlayheadMs;
  final String? selectedOverlayId;
  final ValueChanged<VideoOverlayItem>? onOverlayChanged;
  final ValueChanged<String?>? onSelectOverlay;
  final BoxFit fit;
  final Color backgroundColor;
  final WidgetBuilder? loadingBuilder;
  final WidgetBuilder? emptyBuilder;

  @override
  Widget build(BuildContext context) {
    if (!runtime.isOpen) {
      return emptyBuilder?.call(context) ??
          const Center(
            child: Icon(Icons.videocam_outlined, size: 64, color: Colors.white24),
          );
    }

    return ColoredBox(
      color: backgroundColor,
      child: ListenableBuilder(
        listenable: runtime,
        builder: (context, _) => LayoutBuilder(
          builder: (context, constraints) {
            final max = Size(constraints.maxWidth, constraints.maxHeight);
            final frame = containedVideoFrameSize(max, runtime.aspectRatio);
            final playhead = timelinePlayheadMs ?? runtime.ptsMs;
            final overlayLayer = onOverlayChanged != null || onSelectOverlay != null
                ? DraggableVideoOverlays(
                    frameSize: frame,
                    overlays: overlays,
                    playheadMs: playhead,
                    selectedOverlayId: selectedOverlayId,
                    onOverlayChanged: onOverlayChanged,
                    onSelectOverlay: onSelectOverlay,
                  )
                : Stack(
                    clipBehavior: Clip.none,
                    fit: StackFit.expand,
                    children: [
                      for (final overlay in overlays.where((o) => o.isVisibleAt(playhead)))
                        VideoOverlayPositioned(
                          anchor: overlay.anchor,
                          opacity: overlay.opacityAt(playhead),
                          child: overlay.child,
                        ),
                    ],
                  );

            return Center(
              child: SizedBox(
                width: frame.width,
                height: frame.height,
                child: Stack(
                  clipBehavior: Clip.none,
                  fit: StackFit.expand,
                  children: [
                    _VideoFrameLayer(
                      runtime: runtime,
                      fit: fit,
                      loadingBuilder: loadingBuilder,
                    ),
                    overlayLayer,
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

}

/// Video pixels only (no letterbox wrapper) for use inside [VideoCompositorCanvas].
class _VideoFrameLayer extends StatelessWidget {
  const _VideoFrameLayer({
    required this.runtime,
    required this.fit,
    this.loadingBuilder,
  });

  final MediaRuntime runtime;
  final BoxFit fit;
  final WidgetBuilder? loadingBuilder;

  @override
  Widget build(BuildContext context) {
    final texId = runtime.textureId;
    final w = runtime.previewWidth;
    final h = runtime.previewHeight;

    if (texId != null && texId > 0 && w > 0 && h > 0) {
      return GpuTextureView(
        textureId: texId,
        width: w,
        height: h,
        fit: fit,
      );
    }

    final rgba = runtime.fallbackRgba;
    if (rgba != null && w > 0 && h > 0) {
      return RgbaPreviewImage(
        pixels: rgba,
        width: w,
        height: h,
        fit: fit,
      );
    }

    if (runtime.isLoading) {
      return loadingBuilder?.call(context) ??
          const Center(child: CircularProgressIndicator(color: Colors.white));
    }

    if (runtime.error != null) {
      return Center(
        child: Text(
          runtime.error!,
          style: const TextStyle(color: Colors.white54, fontSize: 12),
          textAlign: TextAlign.center,
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

