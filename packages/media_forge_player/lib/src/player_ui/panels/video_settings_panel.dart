import 'package:flutter/material.dart';

import '../models.dart';
import '../../player_controller.dart';
import '../../video_enhancement.dart';
import '../utils.dart';
import '../widgets/setting_tile.dart';

/// Display (fit/rotation) plus detected video information.
///
/// Fit and display rotation are UI-level; decoder/HW state is read from
/// the engine diagnostics snapshot ([MediaForgePlayerController.lastDiagnostics]).
///
/// The experimental GPU enhancement section is included only when the device
/// reports a backend for it, so unsupported platforms never see a dead
/// control.
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
            ValueListenableBuilder(
              valueListenable: controller.enhancementCapabilities,
              builder: (context, _, _) =>
                  _VideoEnhancementSection(controller: controller),
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

/// Experimental GPU enhancement: mode picker + live diagnostics.
class _VideoEnhancementSection extends StatelessWidget {
  const _VideoEnhancementSection({required this.controller});

  final MediaForgePlayerController controller;

  @override
  Widget build(BuildContext context) {
    final caps = controller.videoEnhancementCapabilities;
    // Probe on first build so the section reflects the real device, then
    // rebuild through the notifier.
    if (caps == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        controller.probeVideoEnhancement();
      });
      return const SizedBox.shrink();
    }
    if (!caps.supported) return const SizedBox.shrink();

    final status = controller.videoEnhancementStatus;
    final selected = controller.value.videoEnhancementMode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const PanelSectionLabel('Video enhancement'),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'EXPERIMENTAL',
                style: TextStyle(
                  fontSize: 9,
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w700,
                  color: Colors.amber,
                ),
              ),
            ),
            const Spacer(),
          ],
        ),
        for (final mode in caps.supportedModes)
          SettingTile(
            icon: _iconFor(mode),
            title: mode.displayName,
            subtitle: mode.description,
            trailing: selected == mode
                ? const Icon(Icons.check, size: 18, color: Colors.white)
                : null,
            onTap: () => controller.setVideoEnhancementMode(mode),
          ),
        if (status != null && status.requestedMode.isActive) ...[
          const SizedBox(height: 4),
          InfoRow('Active mode', status.activeMode.displayName +
              (status.isDowngraded ? ' (reduced)' : '')),
          if (status.outputWidth > 0)
            InfoRow('Processing', status.resolutionLabel),
          InfoRow('GPU path', status.path.isEmpty ? '—' : status.path),
          InfoRow(
            'Frame time',
            status.deadlineMs > 0
                ? '${status.lastFrameMs.toStringAsFixed(2)} ms / '
                    '${status.deadlineMs.toStringAsFixed(1)} ms budget'
                : '${status.lastFrameMs.toStringAsFixed(2)} ms',
          ),
          InfoRow('Deadline misses', '${status.deadlineMisses}'),
          if (status.fallbackReason.isNotEmpty)
            InfoRow('Fallback', status.fallbackReason),
        ],
      ],
    );
  }

  static IconData _iconFor(VideoEnhancementMode mode) => switch (mode) {
        VideoEnhancementMode.off => Icons.block_outlined,
        VideoEnhancementMode.sharp => Icons.details_outlined,
        VideoEnhancementMode.enhanced => Icons.auto_awesome_outlined,
        VideoEnhancementMode.highQuality => Icons.hd_outlined,
      };
}
