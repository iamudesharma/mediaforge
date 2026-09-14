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
///
/// When [showSubtitles] is true (default), the active cue text polled from
/// the engine overlays the bottom of the surface. Cue refresh follows
/// controller position updates (~2 Hz); [subtitleStyle] and
/// [subtitleBuilder] customise rendering.
class MediaForgeVideo extends StatelessWidget {
  const MediaForgeVideo({
    super.key,
    required this.controller,
    this.fit = BoxFit.contain,
    this.placeholder,
    this.errorBuilder,
    this.filterQuality = FilterQuality.low,
    this.showSubtitles = true,
    this.subtitleStyle,
    this.subtitleBuilder,
  });

  final MediaForgePlayerController controller;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget Function(BuildContext context, String message)? errorBuilder;
  final FilterQuality filterQuality;
  final bool showSubtitles;
  final TextStyle? subtitleStyle;
  final Widget Function(BuildContext context, String text)? subtitleBuilder;

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
            Widget surface;
            if (textureId != null &&
                textureId > 0 &&
                size.width > 0 &&
                size.height > 0) {
              surface = Container(
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
            } else if (cpu != null) {

              surface = Container(
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
            } else if (value.isBuffering && value.isInitialized) {
              surface = _Fallback(
                fit: fit,
                child: const CircularProgressIndicator(),
              );
            } else {
              surface = placeholder ??
                  _Fallback(
                    fit: fit,
                    child: const Icon(Icons.movie_outlined),
                  );
            }
            if (!showSubtitles) {
              return _ViewportReporter(
                controller: controller,
                child: surface,
              );
            }
            return _ViewportReporter(
              controller: controller,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  surface,
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: _SubtitleOverlay(
                      controller: controller,
                      style: subtitleStyle,
                      builder: subtitleBuilder,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// Reports the played surface's size (in device pixels) to the controller so
/// the GPU enhancement stage can size its output to the display.
///
/// Reporting is deferred to a post-frame callback and swallowed on error, so
/// measuring can never affect layout or throw during a build.
class _ViewportReporter extends StatelessWidget {
  const _ViewportReporter({required this.controller, required this.child});

  final MediaForgePlayerController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ratio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        if (width.isFinite && height.isFinite && width > 0 && height > 0) {
          final deviceWidth = width * ratio;
          final deviceHeight = height * ratio;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            controller.setVideoEnhancementViewport(deviceWidth, deviceHeight);
          });
        }
        return child;
      },
    );
  }
}

/// Bottom-overlay caption polled from the engine at position cadence.
class _SubtitleOverlay extends StatefulWidget {
  const _SubtitleOverlay({
    required this.controller,
    required this.style,
    required this.builder,
  });

  final MediaForgePlayerController controller;
  final TextStyle? style;
  final Widget Function(BuildContext context, String text)? builder;

  @override
  State<_SubtitleOverlay> createState() => _SubtitleOverlayState();
}

class _SubtitleOverlayState extends State<_SubtitleOverlay> {
  String? _text;
  Duration _polledFor = Duration.zero;
  bool _polling = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_maybePoll);
    _maybePoll();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_maybePoll);
    super.dispose();
  }

  void _maybePoll() {
    final v = widget.controller.value;
    // Same gate as MediaForgePlayerController.subtitleTextAt
    // (MediaForgePlayerValue.hasActiveSubtitles): enabled + a selected track.
    if (!v.hasActiveSubtitles) {
      if (_text != null && mounted) setState(() => _text = null);
      return;
    }
    // Position updates arrive ~2 Hz; skip duplicate polls.
    if (_polling || v.position == _polledFor) return;
    _polling = true;
    final pos = v.position;
    widget.controller.subtitleTextAt(pos).then((text) {
      _polling = false;
      if (!mounted) return;
      setState(() {
        _text = (text == null || text.isEmpty) ? null : text;
        _polledFor = pos;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = _text;
    if (text == null) return const SizedBox.shrink();
    if (widget.builder != null) return widget.builder!(context, text);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: widget.style ??
            const TextStyle(
              color: Colors.white,
              fontSize: 15,
              height: 1.3,
            ),
      ),
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
