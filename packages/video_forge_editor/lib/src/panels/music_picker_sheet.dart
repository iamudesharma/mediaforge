import 'package:flutter/material.dart';
import 'package:video_forge_kit/video_forge_kit.dart';

import '../models/recent_audio_track.dart';
import '../services/audio_picker.dart';
import '../theme/lumina_tokens.dart';

/// Custom music browser (device library + files) — no licensed catalog.
class MusicPickerSheet extends StatefulWidget {
  const MusicPickerSheet({
    super.key,
    required this.recentTracks,
    this.selectedClip,
    required this.muteOriginalAudio,
    required this.onMuteOriginalChanged,
    required this.onVolumeChanged,
    required this.onSourceStartChanged,
    required this.onRemoveTrack,
    required this.onTrackPicked,
    this.waveformSamples = const [],
  });

  final List<RecentAudioTrack> recentTracks;
  final AudioTimelineClip? selectedClip;
  final bool muteOriginalAudio;
  final ValueChanged<bool> onMuteOriginalChanged;
  final ValueChanged<double> onVolumeChanged;
  final ValueChanged<int> onSourceStartChanged;
  final VoidCallback onRemoveTrack;
  final Future<void> Function(AudioPickResult pick) onTrackPicked;
  final List<double> waveformSamples;

  static Future<void> show(
    BuildContext context, {
    required List<RecentAudioTrack> recentTracks,
    AudioTimelineClip? selectedClip,
    required bool muteOriginalAudio,
    required ValueChanged<bool> onMuteOriginalChanged,
    required ValueChanged<double> onVolumeChanged,
    required ValueChanged<int> onSourceStartChanged,
    required VoidCallback onRemoveTrack,
    required Future<void> Function(AudioPickResult pick) onTrackPicked,
    List<double> waveformSamples = const [],
  }) {
    debugPrint('[MusicPicker] open selected=${selectedClip?.id}');
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: LuminaTokens.surfaceContainer,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: MusicPickerSheet(
          recentTracks: recentTracks,
          selectedClip: selectedClip,
          muteOriginalAudio: muteOriginalAudio,
          onMuteOriginalChanged: onMuteOriginalChanged,
          onVolumeChanged: onVolumeChanged,
          onSourceStartChanged: onSourceStartChanged,
          onRemoveTrack: onRemoveTrack,
          onTrackPicked: onTrackPicked,
          waveformSamples: waveformSamples,
        ),
      ),
    );
  }

  @override
  State<MusicPickerSheet> createState() => _MusicPickerSheetState();
}

class _MusicPickerSheetState extends State<MusicPickerSheet> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<RecentAudioTrack> get _filteredRecent {
    if (_query.trim().isEmpty) return widget.recentTracks;
    final q = _query.trim().toLowerCase();
    return widget.recentTracks
        .where((t) => t.displayName.toLowerCase().contains(q))
        .toList();
  }

  Future<void> _browse(AudioPickSource source) async {
    final pick = await pickAudioWithPlatformPicker(
      context: context,
      forceSource: source,
    );
    if (pick == null || !mounted) return;
    await widget.onTrackPicked(pick);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _pickRecent(RecentAudioTrack track) async {
    await widget.onTrackPicked(
      AudioPickResult(
        path: track.path,
        source: AudioPickSource.files,
        displayName: track.displayName,
      ),
    );
    if (mounted) Navigator.pop(context);
  }

  String _formatDuration(int ms) {
    final s = (ms / 1000).floor();
    final m = s ~/ 60;
    final r = s % 60;
    return '$m:${r.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final clip = widget.selectedClip;

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          LuminaTokens.space4,
          LuminaTokens.space2,
          LuminaTokens.space4,
          LuminaTokens.space6,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Add music',
                    style: TextStyle(
                      color: LuminaTokens.onSurface,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done'),
                ),
              ],
            ),
            TextField(
              controller: _searchCtrl,
              style: const TextStyle(color: LuminaTokens.onSurface),
              decoration: InputDecoration(
                hintText: 'Search your music…',
                hintStyle: const TextStyle(color: LuminaTokens.onSurfaceMuted),
                prefixIcon: const Icon(Icons.search, color: LuminaTokens.onSurfaceVariant),
                filled: true,
                fillColor: LuminaTokens.surfaceContainerHigh,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(LuminaTokens.radiusMd),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: LuminaTokens.space4),
            if (_filteredRecent.isNotEmpty) ...[
              const Text(
                'Recent',
                style: TextStyle(
                  color: LuminaTokens.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: LuminaTokens.space2),
              ..._filteredRecent.map((track) {
                final selected = clip?.sourcePath == track.path;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.music_note,
                    color: selected ? LuminaTokens.accent : LuminaTokens.onSurfaceVariant,
                  ),
                  title: Text(
                    track.displayName,
                    style: TextStyle(
                      color: selected ? LuminaTokens.accent : LuminaTokens.onSurface,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _formatDuration(track.durationMs),
                        style: const TextStyle(
                          color: LuminaTokens.onSurfaceMuted,
                          fontSize: 12,
                        ),
                      ),
                      if (selected) ...[
                        const SizedBox(width: LuminaTokens.space2),
                        const Icon(Icons.check_circle, color: LuminaTokens.accent, size: 18),
                      ],
                    ],
                  ),
                  onTap: () => _pickRecent(track),
                );
              }),
              const SizedBox(height: LuminaTokens.space4),
            ],
            const Text(
              'Browse',
              style: TextStyle(
                color: LuminaTokens.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: LuminaTokens.space2),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _browse(AudioPickSource.musicLibrary),
                    icon: const Icon(Icons.library_music_outlined),
                    label: const Text('Music library'),
                  ),
                ),
                const SizedBox(width: LuminaTokens.space2),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _browse(AudioPickSource.files),
                    icon: const Icon(Icons.folder_outlined),
                    label: const Text('Files'),
                  ),
                ),
              ],
            ),
            if (clip != null) ...[
              const SizedBox(height: LuminaTokens.space5),
              const Text(
                'Selected',
                style: TextStyle(
                  color: LuminaTokens.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: LuminaTokens.space2),
              Text(
                clip.sourcePath.split('/').last,
                style: const TextStyle(
                  color: LuminaTokens.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (widget.waveformSamples.isNotEmpty) ...[
                const SizedBox(height: LuminaTokens.space3),
                SizedBox(
                  height: 40,
                  child: CustomPaint(
                    painter: _WaveformPainter(samples: widget.waveformSamples),
                    child: const SizedBox.expand(),
                  ),
                ),
              ],
              const SizedBox(height: LuminaTokens.space3),
              Row(
                children: [
                  const Text('Volume', style: TextStyle(color: LuminaTokens.onSurfaceVariant)),
                  Expanded(
                    child: Slider(
                      value: clip.volume,
                      min: 0,
                      max: 1,
                      activeColor: LuminaTokens.accent,
                      onChanged: widget.onVolumeChanged,
                    ),
                  ),
                  Text(
                    '${(clip.volume * 100).round()}%',
                    style: const TextStyle(
                      color: LuminaTokens.onSurfaceMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Mute original video audio',
                  style: TextStyle(color: LuminaTokens.onSurface, fontSize: 13),
                ),
                value: widget.muteOriginalAudio,
                activeThumbColor: LuminaTokens.accent,
                onChanged: widget.onMuteOriginalChanged,
              ),
              if (clip.sourceDurationMs > clip.durationMs) ...[
                const Text(
                  'Trim clip in song',
                  style: TextStyle(
                    color: LuminaTokens.onSurfaceVariant,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: LuminaTokens.space2),
                AudioRangeScrubber(
                  sourceDurationMs: clip.sourceDurationMs,
                  windowDurationMs: clip.durationMs,
                  sourceStartMs: clip.sourceStartMs,
                  onSourceStartChanged: widget.onSourceStartChanged,
                ),
              ],
              const SizedBox(height: LuminaTokens.space2),
              TextButton.icon(
                onPressed: () {
                  widget.onRemoveTrack();
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.delete_outline, color: LuminaTokens.error),
                label: const Text(
                  'Remove music',
                  style: TextStyle(color: LuminaTokens.error),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({required this.samples});

  final List<double> samples;

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty) return;
    final paint = Paint()
      ..color = LuminaTokens.accent.withValues(alpha: 0.7)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final mid = size.height / 2;
    final step = size.width / samples.length;
    for (var i = 0; i < samples.length; i++) {
      final amp = samples[i].clamp(0.0, 1.0) * mid;
      final x = i * step + step / 2;
      canvas.drawLine(Offset(x, mid - amp), Offset(x, mid + amp), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.samples != samples;
  }
}
