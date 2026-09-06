import 'package:flutter/material.dart';
import 'package:pixel_surface/pixel_surface.dart';

import 'player_controller.dart';

/// Fullscreen-friendly Flutter video surface for [MediaForgePlayerController].
///
/// ```dart
/// MediaForgeVideo(controller: controller, fit: BoxFit.contain)
/// ```
///
/// Renders the stable GPU texture when available, falls back to the CPU
/// image on unsupported platforms, and shows [placeholder] until the first
/// frame arrives. Listens to the presenter (texture id / size), not to the
/// controller value, so per-frame work never rebuilds playback controls.
class MediaForgeVideo extends StatelessWidget {
  const MediaForgeVideo({
    super.key,
    required this.controller,
    this.fit = BoxFit.contain,
    this.placeholder,
    this.errorBuilder,
    this.filterQuality = FilterQuality.low,
  });

  final MediaForgePlayerController controller;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget Function(BuildContext context, String message)? errorBuilder;
  final FilterQuality filterQuality;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: controller,
      builder: (context, value, _) {
        if (value.hasError && value.errorDescription != null) {
          if (errorBuilder != null) {
            return errorBuilder!(context, value.errorDescription!);
          }
          return _Fallback(
            fit: fit,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline),
                const SizedBox(height: 8),
                Text(
                  value.errorDescription!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          );
        }
        final presenter = controller.presenter;
        return ListenableBuilder(
          listenable: Listenable.merge(
            [presenter.textureId, presenter.frameSize, presenter.cpuImage],
          ),
          builder: (context, _) {
            final textureId = presenter.textureId.value;
            final size = presenter.frameSize.value;
            final cpu = presenter.cpuImage.value;
            if (textureId != null &&
                textureId > 0 &&
                size.width > 0 &&
                size.height > 0) {
              return Container(
                color: Colors.black,
                alignment: Alignment.center,
                child: AspectRatio(
                  aspectRatio: size.width / size.height,
                  child: GpuTextureView(
                    textureId: textureId,
                    width: size.width.toInt(),
                    height: size.height.toInt(),
                    fit: fit,
                  ),
                ),
              );
            }
            if (cpu != null) {
              return Container(
                color: Colors.black,
                alignment: Alignment.center,
                child: AspectRatio(
                  aspectRatio: value.aspectRatio,
                  child: RawImage(
                    image: cpu,
                    fit: fit,
                    filterQuality: filterQuality,
                  ),
                ),
              );
            }
            if (value.isBuffering && value.isInitialized) {
              return _Fallback(
                fit: fit,
                child: const CircularProgressIndicator(),
              );
            }
            return placeholder ??
                _Fallback(
                  fit: fit,
                  child: const Icon(Icons.movie_outlined),
                );
          },
        );
      },
    );
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback({required this.fit, required this.child});
  final BoxFit fit;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Center(child: child),
      ),
    );
  }
}
