import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_video_processor/flutter_video_processor.dart';

class ModernTimeline extends StatefulWidget {
  const ModernTimeline({
    super.key,
    required this.controller,
    required this.playheadMs,
    required this.zoom,
    required this.onZoomChanged,
    this.onAddAudio,
    this.onAddText,
    this.onAddEmoji,
    this.onSplitAtPlayhead,
    this.onSeek,
  });

  final TimelineController controller;
  final int playheadMs;
  final double zoom;
  final ValueChanged<double> onZoomChanged;
  final VoidCallback? onAddAudio;
  final VoidCallback? onAddText;
  final VoidCallback? onAddEmoji;
  final VoidCallback? onSplitAtPlayhead;
  final ValueChanged<int>? onSeek;

  @override
  State<ModernTimeline> createState() => _ModernTimelineState();
}

class _ModernTimelineState extends State<ModernTimeline> {
  bool _videoCollapsed = false;
  bool _audioCollapsed = false;
  bool _overlayCollapsed = false;

  final ScrollController _scrollController = ScrollController();

  static const double basePixelsPerSecond = 60.0;
  static const int snapThresholdMs = 200;

  double get pxPerSec => basePixelsPerSecond * widget.zoom;

  int get totalDurationMs => widget.controller.durationMs.clamp(1000, 1 << 30);

  double get timelineWidth => (totalDurationMs / 1000.0) * pxPerSec;

  List<int> _getSnapPoints(String? draggingId) {
    final points = <int>[0, totalDurationMs, widget.playheadMs];
    for (final clip in widget.controller.videoClips) {
      points.add(clip.timelineStartMs);
      points.add(clip.timelineStartMs + clip.durationMs);
    }
    for (final audio in widget.controller.audioClips) {
      if (audio.id != draggingId) {
        points.add(audio.timelineStartMs);
        points.add(audio.timelineStartMs + audio.durationMs);
      }
    }
    for (final overlay in widget.controller.overlays) {
      if (overlay.id != draggingId) {
        points.add(overlay.startMs);
        points.add(overlay.endMs);
      }
    }
    return points.toSet().toList();
  }

  int _applySnapping(int targetMs, List<int> snapPoints) {
    int closest = targetMs;
    int minDiff = snapThresholdMs + 1;
    for (final p in snapPoints) {
      final diff = (p - targetMs).abs();
      if (diff < minDiff) {
        minDiff = diff;
        closest = p;
      }
    }
    if (minDiff <= snapThresholdMs) {
      return closest;
    }
    return targetMs;
  }

  void _zoomFit(double viewportWidth) {
    if (viewportWidth <= 0) return;
    // Fit the total duration into the viewport width
    final durSec = totalDurationMs / 1000.0;
    final targetPxPerSec = (viewportWidth - 48) / durSec;
    final targetZoom = (targetPxPerSec / basePixelsPerSecond).clamp(0.2, 5.0);
    widget.onZoomChanged(targetZoom);
  }

  @override
  Widget build(BuildContext context) {
    final duration = totalDurationMs;
    final playheadX = (widget.playheadMs / 1000.0) * pxPerSec;

    return LayoutBuilder(
      builder: (context, constraints) {
        final double viewportWidth = constraints.maxWidth;
        final double contentWidth = math.max(timelineWidth, viewportWidth - 32);

        final double tracksHeight = 24.0 + 6.0 +
            (_videoCollapsed ? 20.0 : 64.0) + 6.0 +
            (_audioCollapsed ? 20.0 : 72.0) + 6.0 +
            (_overlayCollapsed ? 20.0 : 64.0) + 16.0;

        return Card(
          color: const Color(0xFF141416),
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Colors.white10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Control bar with zoom, action buttons and collapse controls
              _buildControlBar(context, viewportWidth),

              const Divider(color: Colors.white10, height: 1),

              // 2. Main Scrollable Track View
              Expanded(
                child: NotificationListener<ScrollNotification>(
                  onNotification: (notification) => true,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.vertical,
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: SizedBox(
                        width: contentWidth,
                        height: tracksHeight,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            // Stack of lanes
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Time ruler lane
                                _buildTimeRuler(duration, contentWidth),
                                const SizedBox(height: 6),

                              // Video Track
                              _buildVideoTrackLane(contentWidth),
                              const SizedBox(height: 6),

                              // Audio Track
                              _buildAudioTrackLane(contentWidth),
                              const SizedBox(height: 6),

                              // Overlay Track
                              _buildOverlayTrackLane(contentWidth),
                            ],
                          ),

                          // Playhead Vertical Line overlaying the tracks
                          Positioned(
                            left: playheadX - 1,
                            top: 0,
                            bottom: 0,
                            child: IgnorePointer(
                              child: Container(
                                width: 2,
                                color: Colors.amberAccent,
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    Positioned(
                                      top: -3,
                                      left: -5,
                                      child: Container(
                                        width: 12,
                                        height: 12,
                                        decoration: const BoxDecoration(
                                          color: Colors.amberAccent,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
          ),
        );
      },
    );
  }

  Widget _buildControlBar(BuildContext context, double viewportWidth) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.history, size: 16, color: Colors.white70),
          const SizedBox(width: 6),
          const Text(
            'Timeline',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          const Spacer(),
          // Cut button
          IconButton(
            onPressed: widget.onSplitAtPlayhead,
            icon: const Icon(Icons.content_cut, size: 16, color: Colors.white70),
            tooltip: 'Split Clip',
          ),
          // Add assets buttons
          IconButton(
            onPressed: widget.onAddText,
            icon: const Icon(Icons.text_fields, size: 16, color: Colors.white70),
            tooltip: 'Add Text',
          ),
          IconButton(
            onPressed: widget.onAddEmoji,
            icon: const Icon(Icons.emoji_emotions_outlined, size: 16, color: Colors.white70),
            tooltip: 'Add Emoji',
          ),
          IconButton(
            onPressed: widget.onAddAudio,
            icon: const Icon(Icons.music_note, size: 16, color: Colors.white70),
            tooltip: 'Add Audio',
          ),
          const SizedBox(width: 8),
          const VerticalDivider(color: Colors.white10, width: 1, indent: 8, endIndent: 8),
          const SizedBox(width: 8),
          // Collapsible track toggles
          _buildLaneToggle(
            icon: Icons.movie_outlined,
            value: !_videoCollapsed,
            onChanged: (v) => setState(() => _videoCollapsed = !v),
            tooltip: 'Toggle Video Track',
          ),
          _buildLaneToggle(
            icon: Icons.music_note,
            value: !_audioCollapsed,
            onChanged: (v) => setState(() => _audioCollapsed = !v),
            tooltip: 'Toggle Audio Track',
          ),
          _buildLaneToggle(
            icon: Icons.layers_outlined,
            value: !_overlayCollapsed,
            onChanged: (v) => setState(() => _overlayCollapsed = !v),
            tooltip: 'Toggle Overlay Track',
          ),
          const SizedBox(width: 8),
          const VerticalDivider(color: Colors.white10, width: 1, indent: 8, endIndent: 8),
          const SizedBox(width: 8),
          // Zoom out
          IconButton(
            onPressed: () {
              widget.onZoomChanged((widget.zoom - 0.25).clamp(0.2, 5.0));
            },
            icon: const Icon(Icons.zoom_out, size: 16, color: Colors.white70),
            tooltip: 'Zoom Out',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 6),
          // Fit timeline
          TextButton(
            onPressed: () => _zoomFit(viewportWidth),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Fit', style: TextStyle(color: Colors.white70, fontSize: 10)),
          ),
          const SizedBox(width: 6),
          // Zoom in
          IconButton(
            onPressed: () {
              widget.onZoomChanged((widget.zoom + 0.25).clamp(0.2, 5.0));
            },
            icon: const Icon(Icons.zoom_in, size: 16, color: Colors.white70),
            tooltip: 'Zoom In',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildLaneToggle({
    required IconData icon,
    required bool value,
    required ValueChanged<bool> onChanged,
    required String tooltip,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () => onChanged(value),
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: value ? Colors.white.withValues(alpha: 0.08) : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(icon, size: 14, color: value ? Colors.white : Colors.white30),
        ),
      ),
    );
  }

  Widget _buildTimeRuler(int durationMs, double contentWidth) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: (details) {
        final renderBox = context.findRenderObject() as RenderBox?;
        if (renderBox == null) return;
        final localPos = renderBox.globalToLocal(details.globalPosition);
        // Account for scroll offset and safe padding
        final double scrollOffset = _scrollController.hasClients ? _scrollController.offset : 0.0;
        final double relativeX = localPos.dx + scrollOffset - 16;
        final int targetMs = ((relativeX / pxPerSec) * 1000).round().clamp(0, durationMs);
        final snapPoints = _getSnapPoints(null);
        final snappedMs = _applySnapping(targetMs, snapPoints);
        widget.onSeek?.call(snappedMs);
      },
      onTapDown: (details) {
        final double relativeX = details.localPosition.dx;
        final int targetMs = ((relativeX / pxPerSec) * 1000).round().clamp(0, durationMs);
        final snapPoints = _getSnapPoints(null);
        final snappedMs = _applySnapping(targetMs, snapPoints);
        widget.onSeek?.call(snappedMs);
      },
      child: Container(
        height: 24,
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E22),
          borderRadius: BorderRadius.circular(6),
        ),
        child: CustomPaint(
          size: Size(contentWidth, 24),
          painter: _TimeRulerPainter(
            durationMs: durationMs,
            pxPerSec: pxPerSec,
          ),
        ),
      ),
    );
  }

  Widget _buildVideoTrackLane(double contentWidth) {
    final double height = _videoCollapsed ? 20 : 64;
    final clips = widget.controller.videoClips;

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFF16161A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Stack(
        children: [
          // Track Name label inside
          Positioned(
            left: 8,
            top: 4,
            child: Row(
              children: [
                const Icon(Icons.movie_creation_outlined, size: 10, color: Colors.indigoAccent),
                const SizedBox(width: 4),
                Text(
                  'VIDEO TRACK',
                  style: TextStyle(
                    color: Colors.indigoAccent.withValues(alpha: 0.7),
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          // Clips
          for (final clip in clips)
            Positioned(
              left: (clip.timelineStartMs / 1000.0) * pxPerSec,
              width: (clip.durationMs / 1000.0) * pxPerSec,
              top: _videoCollapsed ? 2 : 16,
              bottom: _videoCollapsed ? 2 : 4,
              child: _VideoTimelineClipBlock(
                clip: clip,
                selected: clip.id == widget.controller.selectedVideoClipId,
                collapsed: _videoCollapsed,
                pxPerSec: pxPerSec,
                snapPoints: _getSnapPoints(clip.id),
                onTap: () => widget.controller.selectVideoClip(clip.id),
                onChanged: (updatedClip) {
                  widget.controller.updateVideoClip(updatedClip);
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAudioTrackLane(double contentWidth) {
    final double height = _audioCollapsed ? 20 : 72;
    final clips = widget.controller.audioClips;

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFF16161A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Stack(
        children: [
          // Track Name label inside
          Positioned(
            left: 8,
            top: 4,
            child: Row(
              children: [
                const Icon(Icons.audiotrack, size: 10, color: Colors.greenAccent),
                const SizedBox(width: 4),
                Text(
                  'AUDIO TRACK',
                  style: TextStyle(
                    color: Colors.greenAccent.withValues(alpha: 0.7),
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          if (clips.isEmpty && !_audioCollapsed)
            const Center(
              child: Text(
                'No background audio tracks. Click Add Audio above.',
                style: TextStyle(color: Colors.white24, fontSize: 10),
              ),
            ),
          // Audio Clips
          for (final clip in clips)
            Positioned(
              left: (clip.timelineStartMs / 1000.0) * pxPerSec,
              width: (clip.durationMs / 1000.0) * pxPerSec,
              top: _audioCollapsed ? 2 : 16,
              bottom: _audioCollapsed ? 2 : 4,
              child: _AudioTimelineClipBlock(
                clip: clip,
                selected: clip.id == widget.controller.selectedAudioClipId,
                collapsed: _audioCollapsed,
                pxPerSec: pxPerSec,
                videoDurationMs: totalDurationMs,
                snapPoints: _getSnapPoints(clip.id),
                onTap: () => widget.controller.selectAudioClip(clip.id),
                onChanged: (updated) {
                  widget.controller.updateAudioClip(updated);
                },
                onRemove: () => widget.controller.removeAudioClip(clip.id),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOverlayTrackLane(double contentWidth) {
    final double height = _overlayCollapsed ? 20 : 64;
    final overlays = widget.controller.overlays;

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFF16161A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Stack(
        children: [
          // Track Name label inside
          Positioned(
            left: 8,
            top: 4,
            child: Row(
              children: [
                const Icon(Icons.layers_outlined, size: 10, color: Colors.purpleAccent),
                const SizedBox(width: 4),
                Text(
                  'OVERLAY TRACK',
                  style: TextStyle(
                    color: Colors.purpleAccent.withValues(alpha: 0.7),
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          if (overlays.isEmpty && !_overlayCollapsed)
            const Center(
              child: Text(
                'No text/emoji overlays. Click Add Text or Emoji above.',
                style: TextStyle(color: Colors.white24, fontSize: 10),
              ),
            ),
          // Overlays
          for (final overlay in overlays)
            Positioned(
              left: (overlay.startMs / 1000.0) * pxPerSec,
              width: ((overlay.endMs - overlay.startMs) / 1000.0) * pxPerSec,
              top: _overlayCollapsed ? 2 : 16,
              bottom: _overlayCollapsed ? 2 : 4,
              child: _OverlayTimelineClipBlock(
                overlay: overlay,
                selected: overlay.id == widget.controller.selectedOverlayId,
                collapsed: _overlayCollapsed,
                pxPerSec: pxPerSec,
                videoDurationMs: totalDurationMs,
                snapPoints: _getSnapPoints(overlay.id),
                onTap: () => widget.controller.selectOverlay(overlay.id),
                onChanged: (updated) {
                  widget.controller.updateOverlay(updated);
                },
                onRemove: () => widget.controller.removeOverlay(overlay.id),
              ),
            ),
        ],
      ),
    );
  }
}

class _TimeRulerPainter extends CustomPainter {
  _TimeRulerPainter({
    required this.durationMs,
    required this.pxPerSec,
  });

  final int durationMs;
  final double pxPerSec;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1.0;

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    // Dynamic grid spacing depending on zoom
    double tickSpacingSecLevel = 1.0;
    if (pxPerSec < 15.0) {
      tickSpacingSecLevel = 10.0;
    } else if (pxPerSec < 35.0) {
      tickSpacingSecLevel = 5.0;
    } else if (pxPerSec > 120.0) {
      tickSpacingSecLevel = 0.5;
    }

    final double step = tickSpacingSecLevel * pxPerSec;

    for (double x = 0; x < size.width; x += step) {
      final double sec = x / pxPerSec;
      if (sec * 1000.0 > durationMs) break;

      // Draw major tick
      canvas.drawLine(Offset(x, size.height - 12), Offset(x, size.height), paint);

      // Label major tick
      final minutes = (sec / 60).floor();
      final seconds = (sec % 60).floor();
      final tenths = ((sec % 1) * 10).floor();

      final label = tickSpacingSecLevel < 1.0
          ? '$minutes:${seconds.toString().padLeft(2, '0')}.$tenths'
          : '$minutes:${seconds.toString().padLeft(2, '0')}';

      textPainter.text = TextSpan(
        text: label,
        style: const TextStyle(color: Colors.white38, fontSize: 8, fontFamily: 'monospace'),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(x + 3, 2));

      // Draw minor sub-ticks
      final double subStep = step / 5;
      for (int i = 1; i < 5; i++) {
        final subX = x + i * subStep;
        if (subX >= size.width) break;
        canvas.drawLine(Offset(subX, size.height - 6), Offset(subX, size.height), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TimeRulerPainter oldDelegate) {
    return oldDelegate.durationMs != durationMs || oldDelegate.pxPerSec != pxPerSec;
  }
}

class _VideoTimelineClipBlock extends StatefulWidget {
  const _VideoTimelineClipBlock({
    required this.clip,
    required this.selected,
    required this.collapsed,
    required this.pxPerSec,
    required this.snapPoints,
    required this.onTap,
    required this.onChanged,
  });

  final VideoTimelineClip clip;
  final bool selected;
  final bool collapsed;
  final double pxPerSec;
  final List<int> snapPoints;
  final VoidCallback onTap;
  final ValueChanged<VideoTimelineClip> onChanged;

  @override
  State<_VideoTimelineClipBlock> createState() => _VideoTimelineClipBlockState();
}

class _VideoTimelineClipBlockState extends State<_VideoTimelineClipBlock> {
  bool _hovered = false;

  int _applySnapping(int targetMs) {
    int closest = targetMs;
    int minDiff = _ModernTimelineState.snapThresholdMs + 1;
    for (final p in widget.snapPoints) {
      final diff = (p - targetMs).abs();
      if (diff < minDiff) {
        minDiff = diff;
        closest = p;
      }
    }
    if (minDiff <= _ModernTimelineState.snapThresholdMs) {
      return closest;
    }
    return targetMs;
  }

  @override
  Widget build(BuildContext context) {
    final clip = widget.clip;
    final isSel = widget.selected;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          decoration: BoxDecoration(
            color: isSel
                ? Colors.indigo.withValues(alpha: 0.6)
                : (_hovered
                    ? Colors.indigo.withValues(alpha: 0.45)
                    : Colors.indigo.withValues(alpha: 0.3)),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isSel ? Colors.white : (_hovered ? Colors.white54 : Colors.indigoAccent.withValues(alpha: 0.3)),
              width: isSel ? 2.0 : 1.0,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              // Title / Time text
              if (!widget.collapsed)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Text(
                      TimelineFormat.ms(clip.durationMs),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              // Trim handles shown when selected or hovered on desktop
              if (!widget.collapsed && (isSel || _hovered)) ...[
                // Left trim handle
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 10,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeLeftRight,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragUpdate: (details) {
                        final dxMs = ((details.delta.dx / widget.pxPerSec) * 1000).round();
                        // Trimming left edge changes sourceStartMs, shifts timelineStartMs (which is done automatically by normalizeClips later,
                        // but here we adjust the local representation)
                        // First, calculate target timeline position of left edge
                        final targetTimelineMs = clip.timelineStartMs + dxMs;
                        final snappedTimelineMs = _applySnapping(targetTimelineMs);
                        final finalDxMs = snappedTimelineMs - clip.timelineStartMs;

                        final newSourceStartMs = (clip.sourceStartMs + finalDxMs).clamp(0, clip.sourceEndMs - 100);
                        if (newSourceStartMs != clip.sourceStartMs) {
                          widget.onChanged(clip.copyWith(
                            sourceStartMs: newSourceStartMs,
                          ));
                        }
                      },
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.white70,
                          borderRadius: BorderRadius.horizontal(left: Radius.circular(5)),
                        ),
                        child: const Center(
                          child: Icon(Icons.drag_indicator, size: 8, color: Colors.black87),
                        ),
                      ),
                    ),
                  ),
                ),
                // Right trim handle
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: 10,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeLeftRight,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragUpdate: (details) {
                        final dxMs = ((details.delta.dx / widget.pxPerSec) * 1000).round();
                        // Trimming right edge changes sourceEndMs
                        final targetTimelineEndMs = clip.timelineStartMs + clip.durationMs + dxMs;
                        final snappedTimelineEndMs = _applySnapping(targetTimelineEndMs);
                        final finalDxMs = snappedTimelineEndMs - (clip.timelineStartMs + clip.durationMs);

                        final newSourceEndMs = (clip.sourceEndMs + finalDxMs).clamp(clip.sourceStartMs + 100, 100000000); // unbounded max for now
                        if (newSourceEndMs != clip.sourceEndMs) {
                          widget.onChanged(clip.copyWith(
                            sourceEndMs: newSourceEndMs,
                          ));
                        }
                      },
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.white70,
                          borderRadius: BorderRadius.horizontal(right: Radius.circular(5)),
                        ),
                        child: const Center(
                          child: Icon(Icons.drag_indicator, size: 8, color: Colors.black87),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AudioTimelineClipBlock extends StatefulWidget {
  const _AudioTimelineClipBlock({
    required this.clip,
    required this.selected,
    required this.collapsed,
    required this.pxPerSec,
    required this.videoDurationMs,
    required this.snapPoints,
    required this.onTap,
    required this.onChanged,
    required this.onRemove,
  });

  final AudioTimelineClip clip;
  final bool selected;
  final bool collapsed;
  final double pxPerSec;
  final int videoDurationMs;
  final List<int> snapPoints;
  final VoidCallback onTap;
  final ValueChanged<AudioTimelineClip> onChanged;
  final VoidCallback onRemove;

  @override
  State<_AudioTimelineClipBlock> createState() => _AudioTimelineClipBlockState();
}

class _AudioTimelineClipBlockState extends State<_AudioTimelineClipBlock> {
  bool _hovered = false;

  int _applySnapping(int targetMs) {
    int closest = targetMs;
    int minDiff = _ModernTimelineState.snapThresholdMs + 1;
    for (final p in widget.snapPoints) {
      final diff = (p - targetMs).abs();
      if (diff < minDiff) {
        minDiff = diff;
        closest = p;
      }
    }
    if (minDiff <= _ModernTimelineState.snapThresholdMs) {
      return closest;
    }
    return targetMs;
  }

  @override
  Widget build(BuildContext context) {
    final clip = widget.clip;
    final isSel = widget.selected;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.grab,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        // Drag center to shift position on timeline
        onHorizontalDragUpdate: (details) {
          final dxMs = ((details.delta.dx / widget.pxPerSec) * 1000).round();
          final targetTimelineMs = clip.timelineStartMs + dxMs;
          final snappedTimelineMs = _applySnapping(targetTimelineMs);
          final clampedStartMs = snappedTimelineMs.clamp(0, widget.videoDurationMs - clip.durationMs);
          
          if (clampedStartMs != clip.timelineStartMs) {
            widget.onChanged(clip.copyWith(
              timelineStartMs: clampedStartMs,
            ));
          }
        },
        child: Container(
          decoration: BoxDecoration(
            color: isSel
                ? Colors.teal.withValues(alpha: 0.6)
                : (_hovered
                    ? Colors.teal.withValues(alpha: 0.45)
                    : Colors.teal.withValues(alpha: 0.3)),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isSel ? Colors.white : (_hovered ? Colors.white54 : Colors.tealAccent.withValues(alpha: 0.3)),
              width: isSel ? 2.0 : 1.0,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              // Waveform representation or simple label
              if (!widget.collapsed) ...[
                Positioned.fill(
                  child: CustomPaint(
                    painter: _SimpleWaveformPainter(color: Colors.tealAccent.withValues(alpha: 0.15)),
                  ),
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  top: 0,
                  bottom: 0,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _basename(clip.sourcePath),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
              // Trim Handles
              if (!widget.collapsed && (isSel || _hovered)) ...[
                // Left trim handle
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 8,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeLeftRight,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragUpdate: (details) {
                        final dxMs = ((details.delta.dx / widget.pxPerSec) * 1000).round();
                        final targetTimelineMs = clip.timelineStartMs + dxMs;
                        final snappedTimelineMs = _applySnapping(targetTimelineMs);
                        final finalDxMs = snappedTimelineMs - clip.timelineStartMs;

                        // Left drag adjustments
                        final newTimelineStart = snappedTimelineMs.clamp(0, clip.timelineEndMs - 100);
                        final newDuration = clip.durationMs - finalDxMs;
                        final newSourceStart = (clip.sourceStartMs + finalDxMs).clamp(0, clip.sourceDurationMs - 100);

                        if (newTimelineStart != clip.timelineStartMs && newDuration > 0 && newSourceStart + newDuration <= clip.sourceDurationMs) {
                          widget.onChanged(clip.copyWith(
                            timelineStartMs: newTimelineStart,
                            durationMs: newDuration,
                            sourceStartMs: newSourceStart,
                          ));
                        }
                      },
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.tealAccent,
                          borderRadius: BorderRadius.horizontal(left: Radius.circular(5)),
                        ),
                      ),
                    ),
                  ),
                ),
                // Right trim handle
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: 8,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeLeftRight,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragUpdate: (details) {
                        final dxMs = ((details.delta.dx / widget.pxPerSec) * 1000).round();
                        final targetTimelineEndMs = clip.timelineStartMs + clip.durationMs + dxMs;
                        final snappedTimelineEndMs = _applySnapping(targetTimelineEndMs);
                        final finalDxMs = snappedTimelineEndMs - (clip.timelineStartMs + clip.durationMs);

                        final newDuration = (clip.durationMs + finalDxMs).clamp(100, clip.sourceDurationMs - clip.sourceStartMs);
                        if (newDuration != clip.durationMs && clip.timelineStartMs + newDuration <= widget.videoDurationMs) {
                          widget.onChanged(clip.copyWith(
                            durationMs: newDuration,
                          ));
                        }
                      },
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.tealAccent,
                          borderRadius: BorderRadius.horizontal(right: Radius.circular(5)),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _basename(String path) {
    final i = path.replaceAll('\\', '/').lastIndexOf('/');
    return i < 0 ? path : path.substring(i + 1);
  }
}

class _OverlayTimelineClipBlock extends StatefulWidget {
  const _OverlayTimelineClipBlock({
    required this.overlay,
    required this.selected,
    required this.collapsed,
    required this.pxPerSec,
    required this.videoDurationMs,
    required this.snapPoints,
    required this.onTap,
    required this.onChanged,
    required this.onRemove,
  });

  final VideoOverlayItem overlay;
  final bool selected;
  final bool collapsed;
  final double pxPerSec;
  final int videoDurationMs;
  final List<int> snapPoints;
  final VoidCallback onTap;
  final ValueChanged<VideoOverlayItem> onChanged;
  final VoidCallback onRemove;

  @override
  State<_OverlayTimelineClipBlock> createState() => _OverlayTimelineClipBlockState();
}

class _OverlayTimelineClipBlockState extends State<_OverlayTimelineClipBlock> {
  bool _hovered = false;

  int _applySnapping(int targetMs) {
    int closest = targetMs;
    int minDiff = _ModernTimelineState.snapThresholdMs + 1;
    for (final p in widget.snapPoints) {
      final diff = (p - targetMs).abs();
      if (diff < minDiff) {
        minDiff = diff;
        closest = p;
      }
    }
    if (minDiff <= _ModernTimelineState.snapThresholdMs) {
      return closest;
    }
    return targetMs;
  }

  @override
  Widget build(BuildContext context) {
    final overlay = widget.overlay;
    final isSel = widget.selected;
    final isText = overlay.isTextOverlay;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.grab,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) {
          final dxMs = ((details.delta.dx / widget.pxPerSec) * 1000).round();
          final duration = overlay.endMs - overlay.startMs;
          
          final targetStartMs = overlay.startMs + dxMs;
          final snappedStartMs = _applySnapping(targetStartMs);
          final clampedStartMs = snappedStartMs.clamp(0, widget.videoDurationMs - duration);
          final clampedEndMs = clampedStartMs + duration;

          if (clampedStartMs != overlay.startMs) {
            widget.onChanged(overlay.copyWith(
              startMs: clampedStartMs,
              endMs: clampedEndMs,
            ));
          }
        },
        child: Container(
          decoration: BoxDecoration(
            color: isSel
                ? Colors.purple.withValues(alpha: 0.6)
                : (_hovered
                    ? Colors.purple.withValues(alpha: 0.45)
                    : Colors.purple.withValues(alpha: 0.3)),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isSel ? Colors.white : (_hovered ? Colors.white54 : Colors.purpleAccent.withValues(alpha: 0.3)),
              width: isSel ? 2.0 : 1.0,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              if (!widget.collapsed)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      isText ? (overlay.resolvedTextSpec?.label ?? 'Text') : 'Emoji Overlay',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              // Trim Handles
              if (!widget.collapsed && (isSel || _hovered)) ...[
                // Left trim handle
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 8,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeLeftRight,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragUpdate: (details) {
                        final dxMs = ((details.delta.dx / widget.pxPerSec) * 1000).round();
                        final targetStartMs = overlay.startMs + dxMs;
                        final snappedStartMs = _applySnapping(targetStartMs);

                        final newStartMs = snappedStartMs.clamp(0, overlay.endMs - 100);
                        if (newStartMs != overlay.startMs) {
                          widget.onChanged(overlay.copyWith(
                            startMs: newStartMs,
                          ));
                        }
                      },
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.purpleAccent,
                          borderRadius: BorderRadius.horizontal(left: Radius.circular(5)),
                        ),
                      ),
                    ),
                  ),
                ),
                // Right trim handle
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: 8,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeLeftRight,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragUpdate: (details) {
                        final dxMs = ((details.delta.dx / widget.pxPerSec) * 1000).round();
                        final targetEndMs = overlay.endMs + dxMs;
                        final snappedEndMs = _applySnapping(targetEndMs);

                        final newEndMs = snappedEndMs.clamp(overlay.startMs + 100, widget.videoDurationMs);
                        if (newEndMs != overlay.endMs) {
                          widget.onChanged(overlay.copyWith(
                            endMs: newEndMs,
                          ));
                        }
                      },
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.purpleAccent,
                          borderRadius: BorderRadius.horizontal(right: Radius.circular(5)),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SimpleWaveformPainter extends CustomPainter {
  _SimpleWaveformPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    final rand = math.Random(12345);
    const double barWidth = 3.0;
    const double gap = 2.0;
    final int count = (size.width / (barWidth + gap)).floor();

    for (int i = 0; i < count; i++) {
      final h = rand.nextDouble() * (size.height - 8) + 4;
      final x = i * (barWidth + gap) + 4;
      final top = (size.height - h) / 2;
      canvas.drawLine(Offset(x, top), Offset(x, top + h), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SimpleWaveformPainter oldDelegate) => false;
}
