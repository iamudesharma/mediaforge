import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../compositor/draggable_video_overlays.dart';
import '../compositor/video_overlay_item.dart';
import 'compositor_layout.dart';
import 'native_playback_controller.dart';

/// Letterboxed native video preview with timeline-filtered Flutter overlays.
///
/// Same overlay pattern as [VideoCompositorCanvas], but uses AVPlayer /
/// ExoPlayer via [video_player] instead of the Rust texture runtime.
class NativeVideoCanvas extends StatelessWidget {
  const NativeVideoCanvas({
    super.key,
    required this.controller,
    this.overlays = const [],
    this.timelinePlayheadMs,
    this.selectedOverlayId,
    this.onOverlayChanged,
    this.onSelectOverlay,
    this.fit = BoxFit.contain,
    this.backgroundColor = Colors.black,
    this.loadingBuilder,
    this.emptyBuilder,
  });

  final NativePlaybackController controller;
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
    if (!controller.isOpen) {
      return emptyBuilder?.call(context) ??
          const Center(
            child: Icon(Icons.videocam_outlined, size: 64, color: Colors.white24),
          );
    }

    return ColoredBox(
      color: backgroundColor,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => LayoutBuilder(
          builder: (context, constraints) {
            final max = Size(constraints.maxWidth, constraints.maxHeight);
            final frame = containedVideoFrameSize(max, controller.aspectRatio);
            final playhead = timelinePlayheadMs ?? controller.positionMs;
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
                    _NativeVideoFrameLayer(
                      controller: controller,
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

class _NativeVideoFrameLayer extends StatelessWidget {
  const _NativeVideoFrameLayer({
    required this.controller,
    required this.fit,
    this.loadingBuilder,
  });

  final NativePlaybackController controller;
  final BoxFit fit;
  final WidgetBuilder? loadingBuilder;

  @override
  Widget build(BuildContext context) {
    final c = controller.controller;
    if (c == null || !c.value.isInitialized) {
      return loadingBuilder?.call(context) ??
          const Center(child: CircularProgressIndicator(color: Colors.white));
    }

    return FittedBox(
      fit: fit,
      child: SizedBox(
        width: c.value.size.width,
        height: c.value.size.height,
        child: VideoPlayer(c),
      ),
    );
  }
}
