import 'package:flutter/material.dart';
import 'package:pixel_surface/pixel_surface.dart';

import 'media_playback_presenter.dart';

/// Displays video from [MediaPlaybackPresenter] using GPU texture when available.
///
/// Rebuilds only when texture id / size / CPU image notifiers change — not via parent
/// [setState] on every frame upload.
class MediaVideoSurface extends StatelessWidget {
  const MediaVideoSurface({
    super.key,
    required this.presenter,
    this.fit = BoxFit.contain,
    this.placeholder,
    this.overlay,
  });

  final MediaPlaybackPresenter presenter;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? overlay;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        presenter.gpu.textureId,
        presenter.gpu.frameSize,
        presenter.cpuImage,
      ]),
      builder: (context, _) {
        final child = _buildContent();
        if (overlay == null) return child;
        return Stack(
          fit: StackFit.expand,
          alignment: Alignment.center,
          children: [child, overlay!],
        );
      },
    );
  }

  Widget _buildContent() {
    if (presenter.usesGpuTexture) {
      final id = presenter.gpu.textureId.value;
      final size = presenter.gpu.frameSize.value;
      if (id != null && size.width > 0 && size.height > 0) {
        return GpuTextureView(
          textureId: id,
          width: size.width.round(),
          height: size.height.round(),
          fit: fit,
        );
      }
    } else {
      final image = presenter.cpuImage.value;
      if (image != null) {
        return RawImage(
          image: image,
          fit: fit,
          width: double.infinity,
          height: double.infinity,
        );
      }
    }
    return placeholder ??
        const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.video_collection_outlined, size: 48, color: Colors.white30),
              SizedBox(height: 12),
              Text(
                'NO VIDEO FRAME',
                style: TextStyle(color: Colors.white30, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        );
  }
}
