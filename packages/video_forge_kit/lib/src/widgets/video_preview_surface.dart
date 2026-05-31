import 'package:flutter/material.dart';
import 'package:pixel_surface/pixel_surface.dart';

import '../runtime/media_runtime.dart';
import 'rgba_preview_image.dart';

/// Displays [MediaRuntime] preview — [GpuTextureView] when available, else [RgbaPreviewImage].
class VideoPreviewSurface extends StatelessWidget {
  const VideoPreviewSurface({
    super.key,
    required this.runtime,
    this.fit = BoxFit.contain,
    this.loadingBuilder,
    this.emptyBuilder,
  });

  final MediaRuntime runtime;
  final BoxFit fit;
  final WidgetBuilder? loadingBuilder;
  final WidgetBuilder? emptyBuilder;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: runtime,
      builder: (context, _) => _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (!runtime.isOpen) {
      return emptyBuilder?.call(context) ??
          const Center(
            child: Icon(Icons.videocam_outlined, size: 64, color: Colors.white24),
          );
    }

    final texId = runtime.textureId;
    final w = runtime.previewWidth;
    final h = runtime.previewHeight;
    if (texId != null && texId > 0 && w > 0 && h > 0) {
      return Center(
        child: AspectRatio(
          aspectRatio: runtime.aspectRatio,
          child: GpuTextureView(
            textureId: texId,
            width: w,
            height: h,
            fit: fit,
          ),
        ),
      );
    }

    final rgba = runtime.fallbackRgba;
    if (rgba != null && w > 0 && h > 0) {
      return Center(
        child: AspectRatio(
          aspectRatio: runtime.aspectRatio,
          child: RgbaPreviewImage(
            pixels: rgba,
            width: w,
            height: h,
            fit: fit,
          ),
        ),
      );
    }

    if (runtime.isLoading) {
      return loadingBuilder?.call(context) ??
          const Center(child: CircularProgressIndicator(color: Colors.white));
    }

    if (runtime.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            runtime.error!,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return emptyBuilder?.call(context) ??
        const Center(
          child: Icon(Icons.videocam_outlined, size: 64, color: Colors.white24),
        );
  }
}
