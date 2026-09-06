import 'package:flutter/material.dart';

import '../../player_controller.dart';
import '../widgets/setting_tile.dart';
import '../widgets/track_tile.dart';

/// Audio settings: track list, source-audio mute, volume.
///
/// The engine exposes no per-track disable or audio-delay control, so this
/// panel only offers engine-backed actions: [selectAudioTrack],
/// [setEmbeddedAudioMuted] ("Mute original audio"), volume and mute.
class AudioTracksPanel extends StatelessWidget {
  const AudioTracksPanel({
    super.key,
    required this.controller,
    required this.embeddedAudioMuted,
    required this.onEmbeddedAudioMutedChanged,
  });

  final MediaForgePlayerController controller;
  final bool embeddedAudioMuted;
  final ValueChanged<bool> onEmbeddedAudioMutedChanged;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: controller,
      builder: (context, value, _) {
        final tracks = value.audioTracks;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PanelSectionLabel('Audio tracks'),
            if (tracks.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Text(
                  'No audio tracks discovered.',
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: tracks.length,
                itemBuilder: (context, i) {
                  final t = tracks[i];
                  return TrackTile(
                    title: trackDisplayName(t),
                    subtitle: audioTrackDetails(t),
                    selected: value.selectedAudioTrackId == t.id ||
                        (value.selectedAudioTrackId == null &&
                            i == 0 &&
                            tracks.length == 1),
                    onTap: () => controller.selectAudioTrack(t.id),
                  );
                },
              ),
            ),
            const PanelSectionLabel('Output'),
            SettingTile(
              icon: Icons.volume_off_outlined,
              title: 'Mute original audio',
              subtitle: 'Embedded track silent, overlays keep playing',
              trailing: Switch(
                value: embeddedAudioMuted,
                onChanged: (v) {
                  controller.setEmbeddedAudioMuted(v);
                  onEmbeddedAudioMutedChanged(v);
                },
              ),
              onTap: () {
                final next = !embeddedAudioMuted;
                controller.setEmbeddedAudioMuted(next);
                onEmbeddedAudioMutedChanged(next);
              },
            ),
            SettingTile(
              icon: value.isMuted
                  ? Icons.volume_off
                  : Icons.volume_up_outlined,
              title: 'Mute all audio',
              trailing: Switch(
                value: value.isMuted,
                onChanged: controller.setMuted,
              ),
              onTap: () => controller.setMuted(!value.isMuted),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  const Icon(Icons.volume_down_outlined,
                      size: 20, color: Colors.white70),
                  Expanded(
                    child: Slider(
                      min: 0,
                      max: 1,
                      value: value.volume,
                      onChanged: controller.setVolume,
                    ),
                  ),
                  SizedBox(
                    width: 44,
                    child: Text(
                      '${(value.volume * 100).round()}%',
                      textAlign: TextAlign.end,
                      style: const TextStyle(
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
