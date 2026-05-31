import 'package:flutter/material.dart';
import 'package:video_forge_kit/video_forge_kit.dart'
    show DraggableVideoOverlays, GpuTextureView, MediaPlaybackEngine, VideoOverlayItem, VideoPlaybackState;
import 'package:media_forge/media_forge.dart';

import '../services/rust_backend.dart';

/// Letterboxed video preview using the Rust MediaPlaybackEngine.
///
/// Uses [MediaVideoSurface] for GPU texture presentation.
/// Renders timeline overlays (text, emoji, poster) on top of the video.
class RustVideoCanvas extends StatelessWidget {
  const RustVideoCanvas({
    super.key,
    required this.backend,
    this.overlays = const [],
    this.timelinePlayheadMs,
    this.selectedOverlayId,
    this.onOverlayChanged,
    this.onSelectOverlay,
    this.fit = BoxFit.contain,
    this.backgroundColor = Colors.black,
    this.showDiagnostics = false,
  });

  final RustBackend backend;
  final List<VideoOverlayItem> overlays;
  final int? timelinePlayheadMs;
  final String? selectedOverlayId;
  final ValueChanged<VideoOverlayItem>? onOverlayChanged;
  final ValueChanged<String?>? onSelectOverlay;
  final BoxFit fit;
  final Color backgroundColor;
  final bool showDiagnostics;

  @override
  Widget build(BuildContext context) {
    final presenter = backend.presenter;
    if (presenter == null) {
      return const Center(
        child: Icon(Icons.videocam_outlined, size: 64, color: Colors.white24),
      );
    }

    return ColoredBox(
      color: backgroundColor,
      child: ListenableBuilder(
        listenable: backend,
        builder: (context, _) {
          return LayoutBuilder(
            builder: (context, constraints) {
              final max = Size(constraints.maxWidth, constraints.maxHeight);
              final frame = _containedVideoFrame(max, backend.aspectRatio);
              final playhead = timelinePlayheadMs ?? backend.positionMs;

              final overlayLayer = DraggableVideoOverlays(
                      frameSize: frame,
                      overlays: overlays,
                      playheadMs: playhead,
                      selectedOverlayId: selectedOverlayId,
                      onOverlayChanged: onOverlayChanged,
                      onSelectOverlay: onSelectOverlay,
                    );

              return Center(
                child: SizedBox(
                  width: frame.width,
                  height: frame.height,
                  child: Stack(
                    clipBehavior: Clip.none,
                    fit: StackFit.expand,
                    children: [
                      MediaVideoSurface(
                        presenter: presenter,
                        fit: fit,
                      ),
                      overlayLayer,
                      if (showDiagnostics)
                        Positioned(
                          top: 4,
                          left: 4,
                          child: _DiagnosticsBadge(backend: backend),
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  static Size _containedVideoFrame(Size container, double aspectRatio) {
    if (aspectRatio <= 0) aspectRatio = 16 / 9;
    final cw = container.width;
    final ch = container.height;
    final videoAspect = aspectRatio;

    if (cw / ch > videoAspect) {
      final w = ch * videoAspect;
      return Size(w, ch);
    } else {
      final h = cw / videoAspect;
      return Size(cw, h);
    }
  }
}

class _DiagnosticsBadge extends StatelessWidget {
  const _DiagnosticsBadge({required this.backend});

  final RustBackend backend;

  @override
  Widget build(BuildContext context) {
    final diag = backend.lastDiagnostics;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Rust Media Runtime',
            style: TextStyle(
              color: Colors.greenAccent,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
          if (diag != null) ...[
            const SizedBox(height: 2),
            Text(
              'drift: ${diag.avDriftMs}ms  vq: ${diag.videoFramesInQueue}  '
              'state: ${diag.state.name}',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 9,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ],
      ),
    );
  }
}
