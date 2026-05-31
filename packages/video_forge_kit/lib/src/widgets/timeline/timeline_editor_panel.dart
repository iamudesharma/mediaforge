import 'package:flutter/material.dart';

import '../../timeline/timeline_controller.dart';
import 'audio_mixer_panel.dart';
import 'overlay_timeline_panel.dart';
import 'video_clips_timeline.dart';

/// Combined Sprint 20 editor: video clips, audio mixer, overlay layers.
class TimelineEditorPanel extends StatelessWidget {
  const TimelineEditorPanel({
    super.key,
    required this.controller,
    required this.playheadMs,
    this.onAddAudio,
    this.onAddText,
    this.onAddEmoji,
    this.onSplitAtPlayhead,
  });

  final TimelineController controller;
  final int playheadMs;
  final VoidCallback? onAddAudio;
  final VoidCallback? onAddText;
  final VoidCallback? onAddEmoji;
  final VoidCallback? onSplitAtPlayhead;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return Card(
          color: const Color(0xFF141414),
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Timeline',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 12),
                VideoClipsTimeline(
                  controller: controller,
                  playheadMs: playheadMs,
                  onSplitAtPlayhead: onSplitAtPlayhead,
                ),
                const Divider(color: Colors.white12, height: 24),
                AudioMixerPanel(
                  controller: controller,
                  onAddAudio: onAddAudio,
                ),
                const Divider(color: Colors.white12, height: 24),
                OverlayTimelinePanel(
                  controller: controller,
                  playheadMs: playheadMs,
                  onAddText: onAddText,
                  onAddEmoji: onAddEmoji,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
