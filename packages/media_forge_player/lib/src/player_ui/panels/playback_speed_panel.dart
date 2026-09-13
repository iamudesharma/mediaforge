import 'package:flutter/material.dart';

import '../../player_controller.dart';
import '../widgets/setting_tile.dart';

/// Playback-speed presets clamped to the engine range (0.25–4.0).
const List<double> kPlaybackSpeedPresets = [
  0.25,
  0.5,
  0.75,
  1.0,
  1.25,
  1.5,
  1.75,
  2.0,
  3.0,
  4.0,
];

/// Speed selector used standalone (quick sheet) and in settings.
class PlaybackSpeedPanel extends StatelessWidget {
  const PlaybackSpeedPanel({super.key, required this.controller});

  final MediaForgePlayerController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: controller,
      builder: (context, value, _) {
        final current = value.playbackRate;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PanelSectionLabel('Playback speed'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final speed in kPlaybackSpeedPresets)
                  ChoiceChip(
                    label: Text(
                      '${speed.toStringAsFixed(speed < 1 ? 2 : (speed % 1 == 0 ? 0 : 2))}×',
                    ),
                    selected: (current - speed).abs() < 0.001,
                    onSelected: (_) => controller.setPlaybackRate(speed),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.speed,
                    size: 20, color: Colors.white70),
                Expanded(
                  child: Slider(
                    min: 0.25,
                    max: 4.0,
                    divisions: 15,
                    value: current.clamp(0.25, 4.0),
                    label: '${current.toStringAsFixed(2)}×',
                    onChanged: (v) => controller.setPlaybackRate(v),
                  ),
                ),
                SizedBox(
                  width: 52,
                  child: Text(
                    '${current.toStringAsFixed(2)}×',
                    textAlign: TextAlign.end,
                    style: const TextStyle(
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// Opens [PlaybackSpeedPanel] as a bottom sheet.
Future<void> showPlaybackSpeedSheet(
  BuildContext context,
  MediaForgePlayerController controller,
) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF14161C),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: PlaybackSpeedPanel(controller: controller),
      ),
    ),
  );
}
