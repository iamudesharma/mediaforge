import 'package:flutter/material.dart';

import '../../timeline/timeline_controller.dart';
import '../../timeline/timeline_format.dart';
import '../../timeline/timeline_models.dart';

/// Background audio tracks: volume, offset, mute (Sprint 20 — preview in host app).
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
    final duration = controller.durationMs.clamp(1, 1 << 30);

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
          SizedBox(
            height: height,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: clips.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final clip = clips[index];
                final selected = clip.id == controller.selectedAudioClipId;
                final widthFactor = clip.durationMs / duration;
                return SizedBox(
                  width: (MediaQuery.sizeOf(context).width * 0.55 * widthFactor)
                      .clamp(120.0, 280.0),
                  child: _AudioClipCard(
                    clip: clip,
                    selected: selected,
                    durationMs: duration,
                    onSelect: () => controller.selectAudioClip(clip.id),
                    onChanged: controller.updateAudioClip,
                    onRemove: () => controller.removeAudioClip(clip.id),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _AudioClipCard extends StatelessWidget {
  const _AudioClipCard({
    required this.clip,
    required this.selected,
    required this.durationMs,
    required this.onSelect,
    required this.onChanged,
    required this.onRemove,
  });

  final AudioTimelineClip clip;
  final bool selected;
  final int durationMs;
  final VoidCallback onSelect;
  final ValueChanged<AudioTimelineClip> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
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
                'Start ${TimelineFormat.clock(clip.timelineStartMs)} · '
                '${TimelineFormat.ms(clip.durationMs)}',
                style: const TextStyle(color: Colors.white54, fontSize: 10),
              ),
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
              Slider(
                value: clip.timelineStartMs.toDouble(),
                min: 0,
                max: (durationMs - clip.durationMs).clamp(0, durationMs).toDouble(),
                onChanged: (v) {
                  onChanged(clip.copyWith(timelineStartMs: v.round()));
                },
              ),
              const Text(
                'Timeline offset',
                style: TextStyle(color: Colors.white38, fontSize: 9),
              ),
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
