import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../media_source.dart';
import '../../track_info.dart';
import '../models.dart';
import '../../player_controller.dart';
import '../utils.dart';
import '../widgets/setting_tile.dart';
import '../widgets/track_tile.dart';

/// VLC-style media information: source, tracks, playback stats.
///
/// Only surfaces data the engine actually reports; unsupported metadata
/// (container, HDR, pixel format, file size) is omitted rather than
/// guessed. Open via [showMediaInformation].
class MediaInformationPanel extends StatelessWidget {
  const MediaInformationPanel({
    super.key,
    required this.controller,
    this.torrentStats,
  });

  final MediaForgePlayerController controller;
  final ValueListenable<MediaPlayerTorrentStats?>? torrentStats;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: controller,
      builder: (context, value, _) {
        final diag = controller.lastDiagnostics;
        final media = controller.media;
        final mediaKind = media == null
            ? '—'
            : switch (media) {
                MediaForgeFile() => 'Local file',
                MediaForgeNetwork() => 'Network stream',
                MediaForgeAsset() => 'Bundled asset',
              };
        final sourceLabel = media == null
            ? '—'
            : switch (media) {
                MediaForgeFile(:final path) => path,
                MediaForgeNetwork(:final url) => url,
                MediaForgeAsset(:final assetKey) => assetKey,
              };
        final videoTrack = value.videoTracks.isEmpty
            ? null
            : value.videoTracks.firstWhere(
                (t) => t.id == value.selectedVideoTrackId,
                orElse: () => value.videoTracks.first,
              );
        final audioTrack = value.audioTracks.isEmpty
            ? null
            : value.audioTracks.firstWhere(
                (t) => t.id == value.selectedAudioTrackId,
                orElse: () => value.audioTracks.first,
              );
        MediaForgeSubtitleTrack? subTrack;
        if (value.subtitleTracks.isEmpty ||
            value.selectedSubtitleTrackId == null) {
          subTrack = null;
        } else {
          final matches = value.subtitleTracks
              .where((t) => t.id == value.selectedSubtitleTrackId)
              .toList();
          subTrack = matches.isEmpty ? null : matches.first;
        }
        final usesGpu = controller.presenter.usesGpuTexture;

        return ListView(
          shrinkWrap: true,
          children: [
            const PanelSectionLabel('File / stream'),
            InfoRow('Source', mediaKind),
            InfoRow('Location', sourceLabel),
            InfoRow('Duration', formatDuration(value.duration)),
            const PanelSectionLabel('Video'),
            InfoRow('Codec', videoTrack?.codec ?? '—'),
            InfoRow(
              'Resolution',
              value.hasVideo
                  ? '${value.videoWidth}×${value.videoHeight}'
                  : '—',
            ),
            if (videoTrack != null && videoTrack.bitrate > 0)
              InfoRow(
                  'Track bitrate', formatBitrate(videoTrack.bitrate)),
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
            if (diag != null) ...[
              InfoRow('Decoded FPS',
                  diag.decodedFps.toStringAsFixed(1)),
              InfoRow('Presented FPS',
                  diag.presentedFps.toStringAsFixed(1)),
            ],
            const PanelSectionLabel('Audio'),
            InfoRow(
              'Active track',
              audioTrack == null
                  ? '—'
                  : trackDisplayName(audioTrack),
            ),
            if (audioTrack != null) ...[
              InfoRow('Codec', audioTrack.codec ?? '—'),
              InfoRow(
                  'Channels', formatChannels(audioTrack.channels)),
              InfoRow('Sample rate',
                  formatSampleRate(audioTrack.sampleRate)),
              if (audioTrack.bitrate > 0)
                InfoRow('Bitrate', formatBitrate(audioTrack.bitrate)),
            ],
            const PanelSectionLabel('Subtitles'),
            InfoRow(
              'Active track',
              subTrack == null ? 'Off' : trackDisplayName(subTrack),
            ),
            if (subTrack != null)
              InfoRow('Format', subTrack.codec ?? '—'),
            if (diag != null)
              InfoRow('Cues buffered', '${diag.subtitleCuesPending}'),
            const PanelSectionLabel('Playback stats'),
            if (diag == null)
              const Padding(
                padding:
                    EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Text(
                  'No diagnostics yet — start playback.',
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ),
            if (diag != null) ...[
              InfoRow('State', diag.state.name),
              InfoRow('Position',
                  '${formatDuration(Duration(milliseconds: diag.mediaTimeMs))} '
                  '/ ${formatDuration(value.duration)}'),
              InfoRow('Buffered ahead',
                  formatDuration(Duration(milliseconds: diag.bufferedDurationMs))),
              InfoRow('A/V drift', '${diag.avDriftMs} ms'),
              InfoRow('Dropped (present)',
                  '${diag.droppedFrames}'),
              InfoRow('Dropped (decoder)',
                  '${diag.decoderDroppedFrames}'),
              InfoRow('Queue depth', '${diag.decoderQueueDepth}'),
              InfoRow('Stream bytes read',
                  formatBytes(diag.bytesRead)),
              InfoRow('Measured bitrate',
                  formatBitrate(diag.readBitrateBps)),
              InfoRow('Render path',
                  usesGpu ? 'GPU texture' : 'CPU fallback'),
            ],
            if (torrentStats != null) ...[
              const PanelSectionLabel('Swarm (app-provided)'),
              ValueListenableBuilder(
                valueListenable: torrentStats!,
                builder: (context, stats, _) {
                  if (stats == null) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(
                          horizontal: 4, vertical: 8),
                      child: Text(
                        'No swarm data.',
                        style: TextStyle(
                            color: Colors.white54, fontSize: 13),
                      ),
                    );
                  }
                  return Column(
                    children: [
                      InfoRow('Download',
                          '${formatBitrate(stats.downloadSpeedBps * 8)}/s'),
                      InfoRow('Upload',
                          '${formatBitrate(stats.uploadSpeedBps * 8)}/s'),
                      InfoRow('Peers', '${stats.peers}'),
                      InfoRow('Seeds', '${stats.seeds}'),
                      InfoRow('Downloaded',
                          '${formatBytes(stats.downloadedBytes)}'
                          ' / ${formatBytes(stats.totalBytes)}'
                          ' (${(stats.progress * 100).toStringAsFixed(1)}%)'),
                      InfoRow('Stream buffer',
                          formatDuration(Duration(
                              milliseconds: stats.streamBufferMs))),
                    ],
                  );
                },
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Opens [MediaInformationPanel] as a bottom sheet (narrow) or dialog (wide).
Future<void> showMediaInformation(
  BuildContext context,
  MediaForgePlayerController controller, {
  ValueListenable<MediaPlayerTorrentStats?>? torrentStats,
}) {
  final wide = MediaQuery.sizeOf(context).width >= 700;
  final panel = MediaInformationPanel(
    controller: controller,
    torrentStats: torrentStats,
  );
  if (wide) {
    return showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: const Color(0xFF14161C),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: ConstrainedBox(
          constraints:
              const BoxConstraints(maxWidth: 560, maxHeight: 640),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Media information',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                Flexible(child: panel),
              ],
            ),
          ),
        ),
      ),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF14161C),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (_, scrollController) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Text(
                'Media information',
                style:
                    TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: MediaInformationPanel(
                  controller: controller,
                  torrentStats: torrentStats,
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
