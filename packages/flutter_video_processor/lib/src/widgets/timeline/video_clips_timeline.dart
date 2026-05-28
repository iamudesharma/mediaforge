import 'package:flutter/material.dart';

import '../../timeline/timeline_controller.dart';
import '../../timeline/timeline_format.dart';
import '../../timeline/timeline_models.dart';

/// Visual lane for video clip split / merge / delete (Sprint 20).
class VideoClipsTimeline extends StatelessWidget {
  const VideoClipsTimeline({
    super.key,
    required this.controller,
    required this.playheadMs,
    this.height = 56,
    this.onSplitAtPlayhead,
    this.onClipSelected,
  });

  final TimelineController controller;
  final int playheadMs;
  final double height;
  final VoidCallback? onSplitAtPlayhead;
  final ValueChanged<String>? onClipSelected;

  @override
  Widget build(BuildContext context) {
    final duration = controller.durationMs.clamp(1, 1 << 30);
    final clips = controller.videoClips;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.movie_outlined, size: 16, color: Colors.white70),
            const SizedBox(width: 6),
            Text(
              'Video · ${clips.length} clip${clips.length == 1 ? '' : 's'}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const Spacer(),
            Text(
              TimelineFormat.clock(playheadMs),
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: height,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final playheadX = width * (playheadMs / duration).clamp(0.0, 1.0);

              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF252525),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      children: [
                        for (final clip in clips)
                          Expanded(
                            flex: clip.durationMs.clamp(1, duration),
                            child: _ClipBlock(
                              clip: clip,
                              selected:
                                  clip.id == controller.selectedVideoClipId,
                              onTap: () {
                                controller.selectVideoClip(clip.id);
                                onClipSelected?.call(clip.id);
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                  Positioned(
                    left: playheadX.clamp(0.0, width - 2),
                    top: 0,
                    bottom: 0,
                    child: Container(
                      width: 2,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            FilledButton.tonalIcon(
              onPressed: onSplitAtPlayhead,
              icon: const Icon(Icons.content_cut, size: 18),
              label: const Text('Split at playhead'),
            ),
            OutlinedButton.icon(
              onPressed: controller.selectedVideoClipId == null
                  ? null
                  : () {
                      final id = controller.selectedVideoClipId!;
                      controller.mergeWithNext(id);
                    },
              icon: const Icon(Icons.merge, size: 18),
              label: const Text('Merge next'),
            ),
            OutlinedButton.icon(
              onPressed: controller.selectedVideoClipId == null ||
                      controller.videoClips.length <= 1
                  ? null
                  : () {
                      controller.deleteVideoClip(controller.selectedVideoClipId!);
                    },
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Delete clip'),
            ),
          ],
        ),
      ],
    );
  }
}

class _ClipBlock extends StatelessWidget {
  const _ClipBlock({
    required this.clip,
    required this.selected,
    required this.onTap,
  });

  final VideoTimelineClip clip;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: selected
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.45)
              : const Color(0xFF3D5AFE).withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: selected ? Colors.white : Colors.white24,
            width: selected ? 2 : 1,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          TimelineFormat.ms(clip.durationMs),
          style: const TextStyle(color: Colors.white, fontSize: 10),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
