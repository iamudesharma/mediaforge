import 'package:flutter/material.dart';

import '../models.dart';
import '../../player_controller.dart';
import '../utils.dart';
import '../widgets/setting_tile.dart';
import '../widgets/track_tile.dart';

/// Subtitle settings: enable, track list, external load, delay, appearance.
///
/// Styling (size/weight/background/position) is applied Dart-side through
/// [appearance]; only delay/enable/selection touch the engine.
class SubtitleTracksPanel extends StatelessWidget {
  const SubtitleTracksPanel({
    super.key,
    required this.controller,
    required this.appearance,
    this.onPickExternalSubtitle,
  });

  final MediaForgePlayerController controller;
  final ValueNotifier<MediaPlayerSubtitleStyle> appearance;

  /// App-provided file picker (`null` hides the "Load file" row).
  final Future<Uri?> Function()? onPickExternalSubtitle;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: controller,
      builder: (context, value, _) {
        final tracks = value.subtitleTracks;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SettingTile(
              icon: Icons.closed_caption_outlined,
              title: 'Subtitles',
              subtitle: value.subtitlesEnabled ? 'On' : 'Off',
              trailing: Switch(
                value: value.subtitlesEnabled,
                onChanged: controller.setSubtitlesEnabled,
              ),
              onTap: () => controller
                  .setSubtitlesEnabled(!value.subtitlesEnabled),
            ),
            const PanelSectionLabel('Tracks'),
            TrackTile(
              title: 'Off',
              selected: value.selectedSubtitleTrackId == null,
              onTap: () => controller.selectSubtitleTrack(null),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: tracks.length,
                itemBuilder: (context, i) {
                  final t = tracks[i];
                  return TrackTile(
                    title: trackDisplayName(t),
                    subtitle: subtitleTrackDetails(t),
                    selected:
                        value.selectedSubtitleTrackId == t.id,
                    onTap: () => controller.selectSubtitleTrack(t.id),
                  );
                },
              ),
            ),
            if (onPickExternalSubtitle != null)
              SettingTile(
                icon: Icons.file_open_outlined,
                title: 'Load external subtitle…',
                subtitle: 'Sidecar .srt/.vtt/.ass file or URL',
                trailing: const Icon(Icons.chevron_right,
                    color: Colors.white54),
                onTap: () async {
                  final uri = await onPickExternalSubtitle!();
                  if (uri == null) return;
                  final id = await controller.addExternalSubtitle(uri);
                  await controller.selectSubtitleTrack(id);
                },
              ),
            if (value.subtitleTracks.any((t) => !t.isEmbedded))
              SettingTile(
                icon: Icons.delete_outline,
                title: 'Remove external subtitles',
                trailing: const Icon(Icons.chevron_right,
                    color: Colors.white54),
                onTap: controller.closeExternalSubtitles,
              ),
            const PanelSectionLabel('Synchronization'),
            _DelayStepper(
              delay: value.subtitleDelay,
              onChanged: controller.setSubtitleDelay,
            ),
            const PanelSectionLabel('Appearance'),
            ValueListenableBuilder(
              valueListenable: appearance,
              builder: (context, style, _) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.text_fields_outlined,
                            size: 20, color: Colors.white70),
                        Expanded(
                          child: Slider(
                            min: 10,
                            max: 28,
                            divisions: 18,
                            value: style.fontSize.clamp(10, 28),
                            label:
                                '${style.fontSize.toStringAsFixed(0)} pt',
                            onChanged: (v) => appearance.value =
                                style.copyWith(fontSize: v),
                          ),
                        ),
                        SizedBox(
                          width: 52,
                          child: Text(
                            '${style.fontSize.toStringAsFixed(0)} pt',
                            textAlign: TextAlign.end,
                            style: const TextStyle(
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        const Icon(Icons.contrast_outlined,
                            size: 20, color: Colors.white70),
                        Expanded(
                          child: Slider(
                            min: 0,
                            max: 1,
                            value: style.backgroundOpacity,
                            label:
                                '${(style.backgroundOpacity * 100).round()}%',
                            onChanged: (v) => appearance.value =
                                style.copyWith(backgroundOpacity: v),
                          ),
                        ),
                        SizedBox(
                          width: 52,
                          child: Text(
                            '${(style.backgroundOpacity * 100).round()}%',
                            textAlign: TextAlign.end,
                            style: const TextStyle(
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        const Icon(Icons.format_bold_outlined,
                            size: 20, color: Colors.white70),
                        const SizedBox(width: 8),
                        const Text('Bold'),
                        const Spacer(),
                        Switch(
                          value: style.bold,
                          onChanged: (v) => appearance.value =
                              style.copyWith(bold: v),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        const Icon(Icons.vertical_align_bottom_outlined,
                            size: 20, color: Colors.white70),
                        const SizedBox(width: 8),
                        const Text('Position'),
                        const Spacer(),
                        SegmentedButton<PlayerSubtitlePosition>(
                          showSelectedIcon: false,
                          style: SegmentedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                          segments: const [
                            ButtonSegment(
                              value: PlayerSubtitlePosition.top,
                              label: Text('Top'),
                            ),
                            ButtonSegment(
                              value: PlayerSubtitlePosition.bottom,
                              label: Text('Bottom'),
                            ),
                          ],
                          selected: {style.position},
                          onSelectionChanged: (s) => appearance.value =
                              style.copyWith(position: s.single),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }
}

/// −0.5s / value / +0.5s stepper bound to [MediaForgePlayerController.setSubtitleDelay].
class _DelayStepper extends StatelessWidget {
  const _DelayStepper({required this.delay, required this.onChanged});

  final Duration delay;
  final ValueChanged<Duration> onChanged;

  @override
  Widget build(BuildContext context) {
    String label() {
      final ms = delay.inMilliseconds;
      final sign = ms < 0 ? '−' : '+';
      return '$sign${formatDuration(Duration(milliseconds: ms.abs()))}';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          const Icon(Icons.timer_outlined,
              size: 20, color: Colors.white70),
          const SizedBox(width: 12),
          FilledButton.tonal(
            onPressed: () =>
                onChanged(delay - const Duration(milliseconds: 500)),
            child: const Text('−0.5s'),
          ),
          Expanded(
            child: Text(
              label(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFeatures: [FontFeature.tabularFigures()],
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          FilledButton.tonal(
            onPressed: () =>
                onChanged(delay + const Duration(milliseconds: 500)),
            child: const Text('+0.5s'),
          ),
          TextButton(
            onPressed: () => onChanged(Duration.zero),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }
}
