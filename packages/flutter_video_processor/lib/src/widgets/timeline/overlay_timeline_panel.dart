import 'package:flutter/material.dart';

import '../../compositor/video_overlay_item.dart';
import '../../timeline/timeline_controller.dart';
import '../../timeline/timeline_format.dart';

/// Edit overlay visibility windows and fade transitions (Sprint 20).
class OverlayTimelinePanel extends StatelessWidget {
  const OverlayTimelinePanel({
    super.key,
    required this.controller,
    required this.playheadMs,
    this.onAddText,
    this.onAddEmoji,
  });

  final TimelineController controller;
  final int playheadMs;
  final VoidCallback? onAddText;
  final VoidCallback? onAddEmoji;

  @override
  Widget build(BuildContext context) {
    final duration = controller.durationMs.clamp(1, 1 << 30);
    final overlays = controller.overlays;
    final selectedId = controller.selectedOverlayId;
    VideoOverlayItem? selected;
    if (selectedId != null) {
      for (final o in overlays) {
        if (o.id == selectedId) {
          selected = o;
          break;
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.layers_outlined, size: 16, color: Colors.white70),
            const SizedBox(width: 6),
            Text(
              'Layers · ${overlays.length}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const Spacer(),
            if (onAddText != null)
              IconButton(
                onPressed: onAddText,
                icon: const Icon(Icons.title, color: Colors.white70),
                tooltip: 'Add text',
              ),
            if (onAddEmoji != null)
              IconButton(
                onPressed: onAddEmoji,
                icon: const Icon(Icons.emoji_emotions_outlined, color: Colors.white70),
                tooltip: 'Add emoji',
              ),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 40,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              return Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF252525),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: CustomPaint(
                      size: Size(w, 40),
                      painter: _OverlayLanePainter(
                        overlays: overlays,
                        durationMs: duration,
                        selectedId: selectedId,
                      ),
                    ),
                  ),
                  Positioned(
                    left: w * (playheadMs / duration).clamp(0.0, 1.0),
                    top: 0,
                    bottom: 0,
                    child: Container(width: 2, color: Colors.amberAccent),
                  ),
                ],
              );
            },
          ),
        ),
        if (overlays.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'No overlays — add text or emoji at the playhead',
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
          )
        else
          SizedBox(
            height: 72,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: overlays.length,
              itemBuilder: (context, i) {
                final o = overlays[i];
                final isSel = o.id == selectedId;
                return Padding(
                  padding: const EdgeInsets.only(right: 8, top: 8),
                  child: ChoiceChip(
                    label: Text(
                      '${o.id} · ${TimelineFormat.clock(o.startMs)}',
                      style: const TextStyle(fontSize: 10),
                    ),
                    selected: isSel,
                    onSelected: (_) => controller.selectOverlay(o.id),
                  ),
                );
              },
            ),
          ),
        if (selected != null) ...[
          const SizedBox(height: 8),
          _OverlayEditor(
            item: selected,
            durationMs: duration,
            onChanged: controller.updateOverlay,
            onDelete: () => controller.removeOverlay(selected!.id),
          ),
        ],
      ],
    );
  }
}

class _OverlayEditor extends StatelessWidget {
  const _OverlayEditor({
    required this.item,
    required this.durationMs,
    required this.onChanged,
    required this.onDelete,
  });

  final VideoOverlayItem item;
  final int durationMs;
  final ValueChanged<VideoOverlayItem> onChanged;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF1E1E1E),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  'Layer ${item.id}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline, color: Colors.white54),
                ),
              ],
            ),
            Text(
              'Visible ${TimelineFormat.clock(item.startMs)} → '
              '${TimelineFormat.clock(item.endMs)}',
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
            RangeSlider(
              values: RangeValues(
                item.startMs.toDouble(),
                item.endMs.toDouble().clamp(
                  item.startMs + 100,
                  durationMs.toDouble(),
                ),
              ),
              min: 0,
              max: durationMs.toDouble(),
              onChanged: (r) {
                onChanged(
                  item.copyWith(
                    startMs: r.start.round(),
                    endMs: r.end.round(),
                  ),
                );
              },
            ),
            Row(
              children: [
                const Text('Fade in', style: TextStyle(color: Colors.white70, fontSize: 11)),
                Expanded(
                  child: Slider(
                    value: item.fadeInMs.toDouble(),
                    min: 0,
                    max: 800,
                    divisions: 16,
                    label: '${item.fadeInMs}ms',
                    onChanged: (v) {
                      onChanged(item.copyWith(fadeInMs: v.round()));
                    },
                  ),
                ),
              ],
            ),
            Row(
              children: [
                const Text('Fade out', style: TextStyle(color: Colors.white70, fontSize: 11)),
                Expanded(
                  child: Slider(
                    value: item.fadeOutMs.toDouble(),
                    min: 0,
                    max: 800,
                    divisions: 16,
                    label: '${item.fadeOutMs}ms',
                    onChanged: (v) {
                      onChanged(item.copyWith(fadeOutMs: v.round()));
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OverlayLanePainter extends CustomPainter {
  _OverlayLanePainter({
    required this.overlays,
    required this.durationMs,
    required this.selectedId,
  });

  final List<VideoOverlayItem> overlays;
  final int durationMs;
  final String? selectedId;

  @override
  void paint(Canvas canvas, Size size) {
    for (final o in overlays) {
      final left = size.width * (o.startMs / durationMs);
      final right = size.width * (o.endMs / durationMs);
      final rect = Rect.fromLTRB(left, 8, right, size.height - 8);
      final paint = Paint()
        ..color = o.id == selectedId
            ? Colors.amber.withValues(alpha: 0.55)
            : Colors.purpleAccent.withValues(alpha: 0.4);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _OverlayLanePainter oldDelegate) => true;
}
