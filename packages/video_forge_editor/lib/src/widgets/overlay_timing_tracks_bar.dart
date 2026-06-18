import 'package:flutter/material.dart';
import 'package:video_forge_kit/video_forge_kit.dart';

import '../theme/lumina_tokens.dart';

/// Instagram-style strip of text + audio timing blocks below the preview.
class OverlayTimingTracksBar extends StatelessWidget {
  const OverlayTimingTracksBar({
    super.key,
    required this.overlays,
    required this.audioClips,
    required this.videoDurationMs,
    required this.selectedOverlayId,
    required this.selectedAudioId,
    required this.onSelectOverlay,
    required this.onSelectAudio,
  });

  final List<VideoOverlayItem> overlays;
  final List<AudioTimelineClip> audioClips;
  final int videoDurationMs;
  final String? selectedOverlayId;
  final String? selectedAudioId;
  final ValueChanged<String?> onSelectOverlay;
  final ValueChanged<String?> onSelectAudio;

  @override
  Widget build(BuildContext context) {
    final duration = videoDurationMs.clamp(1, 1 << 30);

    return Container(
      color: LuminaTokens.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(
        horizontal: LuminaTokens.space3,
        vertical: LuminaTokens.space2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (overlays.isNotEmpty) ...[
            const Text(
              'Text',
              style: TextStyle(
                color: LuminaTokens.onSurfaceVariant,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: LuminaTokens.space1),
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: overlays.length,
                separatorBuilder: (_, __) => const SizedBox(width: LuminaTokens.space2),
                itemBuilder: (context, i) {
                  final o = overlays[i];
                  final label = o.resolvedTextSpec?.label ?? 'Text';
                  final selected = o.id == selectedOverlayId;
                  return _TrackChip(
                    label: label,
                    startMs: o.startMs,
                    endMs: o.endMs,
                    durationMs: duration,
                    color: const Color(0xFF9C27B0),
                    selected: selected,
                    onTap: () => onSelectOverlay(selected ? null : o.id),
                  );
                },
              ),
            ),
          ],
          if (audioClips.isNotEmpty) ...[
            const SizedBox(height: LuminaTokens.space2),
            const Text(
              'Audio',
              style: TextStyle(
                color: LuminaTokens.onSurfaceVariant,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: LuminaTokens.space1),
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: audioClips.length,
                separatorBuilder: (_, __) => const SizedBox(width: LuminaTokens.space2),
                itemBuilder: (context, i) {
                  final clip = audioClips[i];
                  final name = clip.sourcePath.split('/').last;
                  final selected = clip.id == selectedAudioId;
                  return _TrackChip(
                    label: name,
                    startMs: clip.timelineStartMs,
                    endMs: clip.timelineStartMs + clip.durationMs,
                    durationMs: duration,
                    color: const Color(0xFF43A047),
                    selected: selected,
                    onTap: () => onSelectAudio(selected ? null : clip.id),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TrackChip extends StatelessWidget {
  const _TrackChip({
    required this.label,
    required this.startMs,
    required this.endMs,
    required this.durationMs,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int startMs;
  final int endMs;
  final int durationMs;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final widthFactor = ((endMs - startMs) / durationMs).clamp(0.12, 1.0);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 120 * widthFactor + 48,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.55) : color.withValues(alpha: 0.28),
          borderRadius: BorderRadius.circular(LuminaTokens.radiusMd),
          border: Border.all(
            color: selected ? LuminaTokens.accent : color.withValues(alpha: 0.6),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: LuminaTokens.onSurface,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
