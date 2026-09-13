import 'package:flutter/material.dart';

import '../models.dart';
import '../../player_controller.dart';
import '../utils.dart';
import '../widgets/setting_tile.dart';

/// Display (fit/rotation) plus detected video information.
///
/// Fit and display rotation are UI-level; decoder/HW state is read from
/// the engine diagnostics snapshot ([MediaForgePlayerController.lastDiagnostics]).
class VideoSettingsPanel extends StatelessWidget {
  const VideoSettingsPanel({
    super.key,
    required this.controller,
    required this.fit,
    required this.onFitChanged,
    required this.displayQuarterTurns,
    required this.onDisplayRotationChanged,
  });

  final MediaForgePlayerController controller;
  final MediaPlayerFit fit;
  final ValueChanged<MediaPlayerFit> onFitChanged;

  /// UI-level display rotation in quarter turns clockwise (0–3).
  final int displayQuarterTurns;
  final ValueChanged<int> onDisplayRotationChanged;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: controller,
      builder: (context, value, _) {
        final diag = controller.lastDiagnostics;
        final videoTrack = value.videoTracks.isEmpty
            ? null
            : value.videoTracks.firstWhere(
                (t) => t.id == value.selectedVideoTrackId,
                orElse: () => value.videoTracks.first,
              );
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PanelSectionLabel('Display'),
            Row(
              children: [
                const Icon(Icons.aspect_ratio_outlined,
                    size: 20, color: Colors.white70),
                const SizedBox(width: 8),
                const Text('Fit'),
                const Spacer(),
                SegmentedButton<MediaPlayerFit>(
                  showSelectedIcon: false,
                  style: SegmentedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  segments: const [
                    ButtonSegment(
                        value: MediaPlayerFit.contain, label: Text('Fit')),
                    ButtonSegment(
                        value: MediaPlayerFit.cover, label: Text('Fill')),
                    ButtonSegment(
                        value: MediaPlayerFit.fill, label: Text('Stretch')),
                    ButtonSegment(
                        value: MediaPlayerFit.original,
                        label: Text('1:1')),
                  ],
                  selected: {fit},
                  onSelectionChanged: (s) => onFitChanged(s.single),
                ),
              ],
            ),
            Row(
              children: [
                const Icon(Icons.rotate_right_outlined,
                    size: 20, color: Colors.white70),
                const SizedBox(width: 8),
                const Text('Rotate display'),
                const Spacer(),
                SegmentedButton<int>(
                  showSelectedIcon: false,
                  style: SegmentedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  segments: const [
                    ButtonSegment(value: 0, label: Text('0°')),
                    ButtonSegment(value: 1, label: Text('90°')),
                    ButtonSegment(value: 2, label: Text('180°')),
                    ButtonSegment(value: 3, label: Text('270°')),
                  ],
                  selected: {displayQuarterTurns % 4},
                  onSelectionChanged: (s) =>
                      onDisplayRotationChanged(s.single % 4),
                ),
              ],
            ),
            const PanelSectionLabel('Detected video'),
            InfoRow(
              'Resolution',
              value.hasVideo
                  ? '${value.videoWidth}×${value.videoHeight}'
                  : '—',
            ),
            if (value.rotationDegrees != 0)
              InfoRow('Container rotation', '${value.rotationDegrees}°'),
            InfoRow('Codec', videoTrack?.codec ?? '—'),
            if (videoTrack != null && videoTrack.bitrate > 0)
              InfoRow('Track bitrate', formatBitrate(videoTrack.bitrate)),
            InfoRow(
              'Decoder',
              diag == null || diag.activeDecoder.isEmpty
                  ? '—'
                  : diag.activeDecoder,
            ),
            InfoRow(
              'Hardware decode',
              diag == null ? '—' : (diag.hwDecode ? 'Active' : 'Software'),
            ),
            InfoRow(
              'A/V drift',
              diag == null ? '—' : '${diag.avDriftMs} ms',
            ),
          ],
        );
      },
    );
  }
}
