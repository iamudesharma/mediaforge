import 'package:flutter/material.dart';

import '../buffered_range.dart';
import 'models.dart';
import 'player_timeline.dart';
import 'utils.dart';
import 'widgets/player_icon_button.dart';
import 'widgets/player_slider.dart';

/// Frosted glass bar shared by the top and bottom chrome.
class _ChromeBar extends StatelessWidget {
  const _ChromeBar({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.55),
            Colors.black.withValues(alpha: 0.25),
            Colors.transparent,
          ],
        ),
      ),
      child: child,
    );
  }
}

/// Top overlay: back, title/metadata, status, swarm shortcut, more menu.
class PlayerTopBar extends StatelessWidget {
  const PlayerTopBar({
    super.key,
    required this.title,
    this.subtitle,
    this.statusLabel,
    this.onBack,
    this.onShowTorrentStats,
    this.hasTorrentStats = false,
    this.onMore,
  });

  final String title;
  final String? subtitle;
  final String? statusLabel;
  final VoidCallback? onBack;
  final VoidCallback? onShowTorrentStats;
  final bool hasTorrentStats;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    return _ChromeBar(
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              PlayerIconButton(
                icon: Icons.arrow_back,
                tooltip: 'Back (Esc)',
                onPressed: onBack,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty)
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white70,
                        ),
                      ),
                  ],
                ),
              ),
              if (statusLabel != null)
                Container(
                  margin: const EdgeInsets.only(right: 4),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    statusLabel!,
                    style: const TextStyle(
                        fontSize: 11, color: Colors.white70),
                  ),
                ),
              if (hasTorrentStats)
                PlayerIconButton(
                  icon: Icons.hub_outlined,
                  tooltip: 'Swarm stats',
                  onPressed: onShowTorrentStats,
                ),
              PlayerIconButton(
                icon: Icons.more_vert,
                tooltip: 'More options',
                onPressed: onMore,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom overlay: timeline + transport + toggles.
///
/// [wide] switches between the full desktop row and the compact mobile
/// row. Buttons without a handler are hidden (no invented controls).
///
/// Bottom-right order (responsive): speed, subtitles, audio, PiP
/// (optional), fullscreen, settings. The fullscreen button is visible by
/// default unless [fullscreenEnabled] is false or [onToggleFullscreen] is
/// explicitly null *and* fullscreen was disabled — legacy callers that
/// pass [onToggleFullscreen] keep full control (backward compat).
class PlayerBottomBar extends StatelessWidget {
  const PlayerBottomBar({
    super.key,
    required this.position,
    required this.buffered,
    required this.duration,
    this.bufferedRanges = const [],
    this.externalBufferedRanges = const [],
    required this.isPlaying,
    required this.showRemaining,
    required this.onToggleRemaining,
    required this.onSeekCommitted,
    required this.onPlayPause,
    required this.onReplay10,
    required this.onForward10,
    required this.playbackRate,
    required this.onSpeed,
    required this.volume,
    required this.isMuted,
    required this.onVolume,
    required this.onMuteToggle,
    required this.showVolumeSlider,
    required this.subtitleActive,
    required this.onSubtitles,
    required this.onAudio,
    required this.onSettings,
    this.onPrevious,
    this.onNext,
    this.onPictureInPicture,
    this.onToggleFullscreen,
    this.isFullscreen = false,
    this.fullscreenEnabled = true,
    this.chapters = const [],
    this.thumbnailBuilder,
    this.wide = false,
  });

  final Duration position;
  final Duration buffered;
  final Duration duration;

  /// Engine-derived availability ranges (see [PlayerTimeline]).
  final List<MediaForgeBufferedRange> bufferedRanges;

  /// Host-provided cache ranges merged for display (generic, no torrents).
  final List<MediaForgeBufferedRange> externalBufferedRanges;
  final bool isPlaying;
  final bool showRemaining;
  final VoidCallback onToggleRemaining;
  final ValueChanged<Duration> onSeekCommitted;
  final VoidCallback onPlayPause;
  final VoidCallback onReplay10;
  final VoidCallback onForward10;
  final double playbackRate;
  final VoidCallback onSpeed;
  final double volume;
  final bool isMuted;
  final ValueChanged<double> onVolume;
  final VoidCallback onMuteToggle;
  final bool showVolumeSlider;
  final bool subtitleActive;
  final VoidCallback onSubtitles;
  final VoidCallback onAudio;
  final VoidCallback onSettings;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onPictureInPicture;
  final VoidCallback? onToggleFullscreen;
  final bool isFullscreen;

  /// When false the fullscreen button is hidden (app explicitly disables
  /// fullscreen). Defaults to true: the icon is visible in normal mode.
  final bool fullscreenEnabled;
  final List<MediaPlayerChapter> chapters;
  final Future<Widget?> Function(Duration position)? thumbnailBuilder;
  final bool wide;

  /// Whether the fullscreen control is shown.
  bool get showFullscreenButton =>
      fullscreenEnabled && onToggleFullscreen != null;

  @override
  Widget build(BuildContext context) {
    final remaining = duration - position;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.65),
            Colors.black.withValues(alpha: 0.3),
            Colors.transparent,
          ],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  _TimeLabel(
                    text: formatDuration(position),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: PlayerTimeline(
                        position: position,
                        buffered: buffered,
                        duration: duration,
                        bufferedRanges: bufferedRanges,
                        externalBufferedRanges: externalBufferedRanges,
                        onSeekCommitted: onSeekCommitted,
                        chapters: chapters,
                        thumbnailBuilder: thumbnailBuilder,
                        enabled: duration > Duration.zero,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: onToggleRemaining,
                    child: _TimeLabel(
                      text: showRemaining
                          ? '-${formatDuration(remaining.isNegative ? Duration.zero : remaining)}'
                          : formatDuration(duration),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  if (onPrevious != null)
                    PlayerIconButton(
                      icon: Icons.skip_previous,
                      tooltip: 'Previous',
                      onPressed: onPrevious,
                    ),
                  PlayerIconButton(
                    icon: Icons.replay_10,
                    tooltip: 'Back 10 seconds (Left arrow)',
                    onPressed: onReplay10,
                  ),
                  PlayerIconButton(
                    icon: isPlaying ? Icons.pause : Icons.play_arrow,
                    tooltip:
                        isPlaying ? 'Pause (Space)' : 'Play (Space)',
                    onPressed: onPlayPause,
                    size: 52,
                    iconSize: 30,
                  ),
                  PlayerIconButton(
                    icon: Icons.forward_10,
                    tooltip: 'Forward 10 seconds (Right arrow)',
                    onPressed: onForward10,
                  ),
                  if (onNext != null)
                    PlayerIconButton(
                      icon: Icons.skip_next,
                      tooltip: 'Next',
                      onPressed: onNext,
                    ),
                  if (wide) ...[
                    const SizedBox(width: 4),
                    PlayerIconButton(
                      icon: isMuted
                          ? Icons.volume_off
                          : Icons.volume_up_outlined,
                      tooltip: 'Mute (M)',
                      selected: isMuted,
                      onPressed: onMuteToggle,
                      size: 40,
                    ),
                    if (showVolumeSlider)
                      SizedBox(
                        width: 90,
                        child: PlayerSlider(
                          value: isMuted ? 0 : volume,
                          onChanged: onVolume,
                          semanticLabel: 'Volume',
                        ),
                      ),
                  ] else
                    PlayerIconButton(
                      icon: isMuted
                          ? Icons.volume_off
                          : Icons.volume_up_outlined,
                      tooltip: 'Mute (M)',
                      selected: isMuted,
                      onPressed: onMuteToggle,
                    ),
                  const Spacer(),
                  // Bottom-right cluster (responsive): speed, subtitles,
                  // audio, PiP (optional), fullscreen, settings. Audio and
                  // fullscreen stay reachable on narrow screens; only the
                  // speed presentation (text vs icon) and the volume slider
                  // collapse.
                  if (wide)
                    TextButton(
                      onPressed: onSpeed,
                      child: Text(
                        '${playbackRate.toStringAsFixed(playbackRate % 1 == 0 ? 0 : 2)}×',
                        style: const TextStyle(
                          color: Colors.white,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    )
                  else
                    PlayerIconButton(
                      icon: Icons.speed_outlined,
                      tooltip: 'Playback speed',
                      onPressed: onSpeed,
                    ),
                  PlayerIconButton(
                    icon: Icons.closed_caption_outlined,
                    tooltip: 'Subtitles (S)',
                    selected: subtitleActive,
                    onPressed: onSubtitles,
                  ),
                  PlayerIconButton(
                    icon: Icons.audiotrack_outlined,
                    tooltip: 'Audio tracks (A)',
                    onPressed: onAudio,
                  ),
                  if (onPictureInPicture != null)
                    PlayerIconButton(
                      icon: Icons.picture_in_picture_outlined,
                      tooltip: 'Picture in picture',
                      onPressed: onPictureInPicture,
                    ),
                  if (showFullscreenButton)
                    PlayerIconButton(
                      icon: isFullscreen
                          ? Icons.fullscreen_exit
                          : Icons.fullscreen,
                      tooltip: isFullscreen
                          ? 'Exit fullscreen'
                          : 'Enter fullscreen',
                      onPressed: onToggleFullscreen,
                    ),
                  PlayerIconButton(
                    icon: Icons.tune_outlined,
                    tooltip: 'Settings',
                    onPressed: onSettings,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimeLabel extends StatelessWidget {
  const _TimeLabel({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        color: Colors.white,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
    );
  }
}
