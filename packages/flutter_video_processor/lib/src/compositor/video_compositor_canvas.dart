import 'package:flutter/material.dart';
import 'package:rust_gpu_texture/rust_gpu_texture.dart';

import '../runtime/media_runtime.dart';
import '../widgets/rgba_preview_image.dart';
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
    this.fit = BoxFit.contain,
    this.backgroundColor = Colors.black,
    this.loadingBuilder,
    this.emptyBuilder,
  });

  final MediaRuntime runtime;
  final List<VideoOverlayItem> overlays;
  final int? timelinePlayheadMs;
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
            final frame = _containedSize(max, runtime.aspectRatio);
            final playhead = timelinePlayheadMs ?? runtime.ptsMs;
            final visible =
                overlays.where((o) => o.isVisibleAt(playhead)).toList();

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
                    for (final overlay in visible)
                      _OverlayPositioned(
                        anchor: overlay.anchor,
                        opacity: overlay.opacityAt(playhead),
                        child: overlay.child,
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  static Size _containedSize(Size max, double aspectRatio) {
    if (max.width <= 0 || max.height <= 0 || aspectRatio <= 0) {
      return Size.zero;
    }
    final containerAspect = max.width / max.height;
    if (containerAspect > aspectRatio) {
      final h = max.height;
      return Size(h * aspectRatio, h);
    }
    final w = max.width;
    return Size(w, w / aspectRatio);
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

class _OverlayPositioned extends StatelessWidget {
  const _OverlayPositioned({
    required this.anchor,
    required this.opacity,
    required this.child,
  });

  final Offset anchor;
  final double opacity;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ax = anchor.dx.clamp(0.0, 1.0);
    final ay = anchor.dy.clamp(0.0, 1.0);
    return Positioned.fill(
      child: Align(
        alignment: Alignment(ax * 2 - 1, ay * 2 - 1),
        child: Opacity(opacity: opacity, child: child),
      ),
    );
  }
}
