import 'package:flutter/material.dart';

import '../models.dart';
import '../../player_controller.dart';
import 'audio_tracks_panel.dart';
import 'playback_speed_panel.dart';
import 'subtitle_tracks_panel.dart';
import 'video_settings_panel.dart';

/// VLC-style settings: playback, audio, subtitles, video display.
///
/// Sections are the standalone panel widgets (also usable outside this
/// sheet). Opens via [showPlayerSettings], which picks a bottom sheet on
/// narrow screens and a side panel dialog on wide screens.
class PlayerSettingsPanel extends StatefulWidget {
  const PlayerSettingsPanel({
    super.key,
    required this.controller,
    required this.appearance,
    required this.fit,
    required this.onFitChanged,
    required this.displayQuarterTurns,
    required this.onDisplayRotationChanged,
    this.onPickExternalSubtitle,
    this.initialTab = PlayerSettingsTab.playback,
  });

  final MediaForgePlayerController controller;
  final ValueNotifier<MediaPlayerSubtitleStyle> appearance;
  final MediaPlayerFit fit;
  final ValueChanged<MediaPlayerFit> onFitChanged;
  final int displayQuarterTurns;
  final ValueChanged<int> onDisplayRotationChanged;
  final Future<Uri?> Function()? onPickExternalSubtitle;
  final PlayerSettingsTab initialTab;

  @override
  State<PlayerSettingsPanel> createState() => _PlayerSettingsPanelState();
}

enum PlayerSettingsTab { playback, audio, subtitles, video }

class _PlayerSettingsPanelState extends State<PlayerSettingsPanel> {
  late PlayerSettingsTab _tab = widget.initialTab;
  bool _embeddedAudioMuted = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SegmentedButton<PlayerSettingsTab>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
              value: PlayerSettingsTab.playback,
              label: Text('Playback'),
              icon: Icon(Icons.speed_outlined, size: 16),
            ),
            ButtonSegment(
              value: PlayerSettingsTab.audio,
              label: Text('Audio'),
              icon: Icon(Icons.volume_up_outlined, size: 16),
            ),
            ButtonSegment(
              value: PlayerSettingsTab.subtitles,
              label: Text('Subs'),
              icon: Icon(Icons.closed_caption_outlined, size: 16),
            ),
            ButtonSegment(
              value: PlayerSettingsTab.video,
              label: Text('Video'),
              icon: Icon(Icons.movie_outlined, size: 16),
            ),
          ],
          selected: {_tab},
          onSelectionChanged: (s) => setState(() => _tab = s.single),
        ),
        const SizedBox(height: 8),
        Flexible(
          child: SingleChildScrollView(
            child: _tabBody(),
          ),
        ),
      ],
    );
  }

  Widget _tabBody() {
    switch (_tab) {
      case PlayerSettingsTab.playback:
        return _PlaybackTab(
          controller: widget.controller,
          fit: widget.fit,
          onFitChanged: widget.onFitChanged,
        );
      case PlayerSettingsTab.audio:
        return AudioTracksPanel(
          controller: widget.controller,
          embeddedAudioMuted: _embeddedAudioMuted,
          onEmbeddedAudioMutedChanged: (v) =>
              setState(() => _embeddedAudioMuted = v),
        );
      case PlayerSettingsTab.subtitles:
        return SubtitleTracksPanel(
          controller: widget.controller,
          appearance: widget.appearance,
          onPickExternalSubtitle: widget.onPickExternalSubtitle,
        );
      case PlayerSettingsTab.video:
        return VideoSettingsPanel(
          controller: widget.controller,
          fit: widget.fit,
          onFitChanged: widget.onFitChanged,
          displayQuarterTurns: widget.displayQuarterTurns,
          onDisplayRotationChanged: widget.onDisplayRotationChanged,
        );
    }
  }
}

/// Playback tab: speed, loop, A/V drift readout.
class _PlaybackTab extends StatelessWidget {
  const _PlaybackTab({
    required this.controller,
    required this.fit,
    required this.onFitChanged,
  });

  final MediaForgePlayerController controller;
  final MediaPlayerFit fit;
  final ValueChanged<MediaPlayerFit> onFitChanged;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: controller,
      builder: (context, value, _) {
        final drift = controller.lastDiagnostics?.avDriftMs;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PlaybackSpeedPanel(controller: controller),
            _LoopTile(controller: controller),
            if (drift != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 4, vertical: 6),
                child: Row(
                  children: [
                    const Icon(Icons.sync_outlined,
                        size: 20, color: Colors.white70),
                    const SizedBox(width: 12),
                    const Text('A/V drift',
                        style: TextStyle(fontSize: 14)),
                    const Spacer(),
                    Text(
                      '$drift ms',
                      style: const TextStyle(
                        fontFeatures: [FontFeature.tabularFigures()],
                        color: Colors.white70,
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

/// Loop switch needs a rebuild host (controller.looping is a plain field).
class _LoopTile extends StatefulWidget {
  const _LoopTile({required this.controller});
  final MediaForgePlayerController controller;

  @override
  State<_LoopTile> createState() => _LoopTileState();
}

class _LoopTileState extends State<_LoopTile> {
  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      secondary: const Icon(Icons.repeat_outlined,
          size: 20, color: Colors.white70),
      title: const Text('Repeat', style: TextStyle(fontSize: 14)),
      subtitle: const Text(
        'Loop the current media',
        style: TextStyle(fontSize: 12, color: Colors.white54),
      ),
      value: widget.controller.looping,
      onChanged: (v) =>
          setState(() => widget.controller.looping = v),
    );
  }
}

/// Opens [PlayerSettingsPanel]: bottom sheet when narrow, side panel when wide.
Future<void> showPlayerSettings(
  BuildContext context, {
  required MediaForgePlayerController controller,
  required ValueNotifier<MediaPlayerSubtitleStyle> appearance,
  required MediaPlayerFit fit,
  required ValueChanged<MediaPlayerFit> onFitChanged,
  required int displayQuarterTurns,
  required ValueChanged<int> onDisplayRotationChanged,
  Future<Uri?> Function()? onPickExternalSubtitle,
  PlayerSettingsTab initialTab = PlayerSettingsTab.playback,
}) {
  Widget panel() => PlayerSettingsPanel(
        controller: controller,
        appearance: appearance,
        fit: fit,
        onFitChanged: onFitChanged,
        displayQuarterTurns: displayQuarterTurns,
        onDisplayRotationChanged: onDisplayRotationChanged,
        onPickExternalSubtitle: onPickExternalSubtitle,
        initialTab: initialTab,
      );

  if (MediaQuery.sizeOf(context).width >= 700) {
    return showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF14161C),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: ConstrainedBox(
          constraints:
              const BoxConstraints(maxWidth: 560, maxHeight: 640),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Text(
                      'Settings',
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
                Flexible(
                  child: SingleChildScrollView(child: panel()),
                ),
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
      initialChildSize: 0.7,
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
              Expanded(child: panel()),
            ],
          ),
        ),
      ),
      ),
    );
  }
