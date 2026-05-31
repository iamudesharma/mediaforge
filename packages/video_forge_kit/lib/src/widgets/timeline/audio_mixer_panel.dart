import 'package:flutter/material.dart';

import '../../timeline/timeline_controller.dart';
import '../../timeline/timeline_format.dart';
import '../../timeline/timeline_models.dart';
import 'audio_range_scrubber.dart';

/// Background audio tracks: volume, source range, timeline offset (Sprint 20).
class AudioMixerPanel extends StatelessWidget {
  const AudioMixerPanel({
    super.key,
    required this.controller,
    this.onAddAudio,
    this.height = 48,
  });

  final TimelineController controller;
  final VoidCallback? onAddAudio;
  final double height;

  @override
  Widget build(BuildContext context) {
    final clips = controller.audioClips;
    final duration = controller.videoDurationMs.clamp(1, 1 << 30);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.audiotrack, size: 16, color: Colors.white70),
            const SizedBox(width: 6),
            Text(
              'Audio · ${clips.length} track${clips.length == 1 ? '' : 's'}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: onAddAudio,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add track'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (clips.isEmpty)
          Container(
            height: height,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF252525),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white12),
            ),
            child: const Text(
              'No background audio — tap Add track',
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: clips.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final clip = clips[index];
              final selected = clip.id == controller.selectedAudioClipId;
              return _AudioClipCard(
                clip: clip,
                selected: selected,
                videoDurationMs: duration,
                onSelect: () => controller.selectAudioClip(clip.id),
                onChanged: controller.updateAudioClip,
                onRemove: () => controller.removeAudioClip(clip.id),
              );
            },
          ),
      ],
    );
  }
}

class _AudioClipCard extends StatelessWidget {
  const _AudioClipCard({
    required this.clip,
    required this.selected,
    required this.videoDurationMs,
    required this.onSelect,
    required this.onChanged,
    required this.onRemove,
  });

  final AudioTimelineClip clip;
  final bool selected;
  final int videoDurationMs;
  final VoidCallback onSelect;
  final ValueChanged<AudioTimelineClip> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final maxTimelineStart =
        (videoDurationMs - clip.durationMs).clamp(0, videoDurationMs);

    return Material(
      color: selected ? const Color(0xFF2E7D32) : const Color(0xFF1B3D1F),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onSelect,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _basename(clip.sourcePath),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    onPressed: onRemove,
                    icon: const Icon(Icons.close, size: 16, color: Colors.white54),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  ),
                ],
              ),
              Text(
                'Clip ${TimelineFormat.ms(clip.durationMs)} · '
                'source ${TimelineFormat.clock(clip.sourceStartMs)}–'
                '${TimelineFormat.clock(clip.sourceEndMs)} / '
                '${TimelineFormat.clock(clip.sourceDurationMs)}',
                style: const TextStyle(color: Colors.white54, fontSize: 10),
              ),
              if (clip.sourceDurationMs > clip.durationMs) ...[
                const SizedBox(height: 6),
                const Text(
                  'Drag window — which part of the track plays',
                  style: TextStyle(color: Colors.white38, fontSize: 9),
                ),
                const SizedBox(height: 4),
                AudioRangeScrubber(
                  sourceDurationMs: clip.sourceDurationMs,
                  windowDurationMs: clip.durationMs,
                  sourceStartMs: clip.sourceStartMs,
                  onSourceStartChanged: (ms) {
                    onChanged(clip.copyWith(sourceStartMs: ms));
                  },
                ),
              ],
              Row(
                children: [
                  Icon(
                    clip.muted ? Icons.volume_off : Icons.volume_up,
                    size: 14,
                    color: Colors.white70,
                  ),
                  Expanded(
                    child: Slider(
                      value: clip.muted ? 0 : clip.volume,
                      onChanged: (v) {
                        onChanged(clip.copyWith(volume: v, muted: v == 0));
                      },
                    ),
                  ),
                ],
              ),
              if (maxTimelineStart > 0) ...[
                Slider(
                  value: clip.timelineStartMs.toDouble(),
                  min: 0,
                  max: maxTimelineStart.toDouble(),
                  onChanged: (v) {
                    onChanged(clip.copyWith(timelineStartMs: v.round()));
                  },
                ),
                const Text(
                  'Start on video timeline',
                  style: TextStyle(color: Colors.white38, fontSize: 9),
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
