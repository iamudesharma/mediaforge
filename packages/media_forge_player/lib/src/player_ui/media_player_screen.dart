import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../player_controller.dart';
import '../player_value.dart';
import '../video_widget.dart';
import 'center_playback_controls.dart';
import 'media_controls_overlay.dart';
import 'models.dart';
import 'panels/media_information_panel.dart';
import 'panels/playback_speed_panel.dart';
import 'panels/player_settings_panel.dart';
import 'player_caption_overlay.dart';
import 'utils.dart';
import 'widgets/player_icon_button.dart';

/// Full player experience for [MediaForgePlayerController].
///
/// Immersive video surface with auto-hiding chrome, gestures, desktop
/// keyboard shortcuts, VLC-style settings/info panels and streaming-state
/// layers. Consumes only the public controller/value/diagnostics APIs.
///
/// Capabilities the engine does not expose (audio delay, brightness, PiP
/// hardware, cast, chapters/thumbnails metadata) are either omitted or
/// injected by the app: [chapters], [thumbnailBuilder],
/// [onPictureInPicture], [onToggleFullscreen], [onPrevious]/[onNext],
/// [onPickExternalSubtitle], [torrentStats].
class MediaPlayerScreen extends StatefulWidget {
  const MediaPlayerScreen({
    super.key,
    required this.controller,
    this.title = '',
    this.subtitle,
    this.initialFit = MediaPlayerFit.contain,
    this.chapters = const [],
    this.thumbnailBuilder,
    this.torrentStats,
    this.onPrevious,
    this.onNext,
    this.onToggleFullscreen,
    this.isFullscreen = false,
    this.onPictureInPicture,
    this.onPickExternalSubtitle,
    this.onBack,
    this.onRetry,
    this.autoHide = const Duration(milliseconds: 3500),
  });

  final MediaForgePlayerController controller;
  final String title;
  final String? subtitle;
  final MediaPlayerFit initialFit;
  final List<MediaPlayerChapter> chapters;
  final Future<Widget?> Function(Duration position)? thumbnailBuilder;
  final ValueListenable<MediaPlayerTorrentStats?>? torrentStats;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onToggleFullscreen;
  final bool isFullscreen;
  final VoidCallback? onPictureInPicture;
  final Future<Uri?> Function()? onPickExternalSubtitle;
  final VoidCallback? onBack;
  final Future<void> Function()? onRetry;
  final Duration autoHide;

  @override
  State<MediaPlayerScreen> createState() => _MediaPlayerScreenState();
}

class _MediaPlayerScreenState extends State<MediaPlayerScreen> {
  bool _controlsVisible = true;
  Timer? _hideTimer;
  int _sheetsOpen = 0;

  late MediaPlayerFit _fit = widget.initialFit;
  int _displayQuarterTurns = 0;
  late final ValueNotifier<MediaPlayerSubtitleStyle> _appearance =
      ValueNotifier(const MediaPlayerSubtitleStyle());
  bool _showRemaining = false;

  DateTime? _lastSeekAt;
  Duration? _dragPreview;
  double _dragStartX = 0;
  Duration _dragStartPosition = Duration.zero;
  String? _flashLabel;
  Timer? _flashTimer;
  double? _volumePreview;

  @override
  void dispose() {
    _hideTimer?.cancel();
    _flashTimer?.cancel();
    _appearance.dispose();
    super.dispose();
  }

  // -- helpers ----------------------------------------------------------

  bool get _isDesktop {
    switch (defaultTargetPlatform) {
      case TargetPlatform.macOS:
      case TargetPlatform.linux:
      case TargetPlatform.windows:
        return true;
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.fuchsia:
        return false;
    }
  }

  bool get _wide => MediaQuery.sizeOf(context).width >= 700;

  void _bump() {
    if (!mounted) return;
    setState(() => _controlsVisible = true);
    _hideTimer?.cancel();
    if (_sheetsOpen > 0) return;
    _hideTimer = Timer(widget.autoHide, () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  void _toggleControls() {
    _hideTimer?.cancel();
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _bump();
  }

  Future<void> _seekTo(Duration target) async {
    _lastSeekAt = DateTime.now();
    _bump();
    await widget.controller.seek(target);
  }

  Future<void> _seekBy(Duration delta) async {
    final v = widget.controller.value;
    await _seekTo(v.position + delta);
  }

  Future<void> _togglePlayPause() async {
    _bump();
    final v = widget.controller.value;
    if (v.isPlaying) {
      await widget.controller.pause();
    } else if (v.isCompleted) {
      await widget.controller.seek(Duration.zero);
      await widget.controller.play();
    } else {
      await widget.controller.play();
    }
  }

  Future<void> _setVolume(double v) async {
    _bump();
    await widget.controller.setVolume(v.clamp(0.0, 1.0));
  }

  void _flash(String label) {
    _flashTimer?.cancel();
    setState(() => _flashLabel = label);
    _flashTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _flashLabel = null);
    });
  }

  bool get _recentSeek =>
      _lastSeekAt != null &&
      DateTime.now().difference(_lastSeekAt!) <
          const Duration(milliseconds: 1500);

  String? _statusLabel(MediaForgePlayerValue v) {
    if (v.hasError) return 'Error';
    if (!v.isInitialized) return 'Loading';
    if (v.isCompleted) return 'Ended';
    if (v.isBuffering && _recentSeek) return 'Seeking';
    if (v.isBuffering) return 'Buffering';
    if (v.isPlaying) {
      final hw = widget.controller.lastDiagnostics?.hwDecode;
      return hw == true ? 'Playing · HW' : 'Playing';
    }
    return 'Paused';
  }

  // -- panels -------------------------------------------------------------

  Future<void> _trackSheet(Future<void> Function() open) async {
    _sheetsOpen++;
    _hideTimer?.cancel();
    try {
      await open();
    } finally {
      _sheetsOpen--;
      _bump();
    }
  }

  Future<void> _openSettings(
      {PlayerSettingsTab tab = PlayerSettingsTab.playback}) {
    return _trackSheet(() => showPlayerSettings(
          context,
          controller: widget.controller,
          appearance: _appearance,
          fit: _fit,
          onFitChanged: (f) => setState(() => _fit = f),
          displayQuarterTurns: _displayQuarterTurns,
          onDisplayRotationChanged: (q) =>
              setState(() => _displayQuarterTurns = q),
          onPickExternalSubtitle: widget.onPickExternalSubtitle,
          initialTab: tab,
        ));
  }

  Future<void> _openInfo() {
    return _trackSheet(() => showMediaInformation(
          context,
          widget.controller,
          torrentStats: widget.torrentStats,
        ));
  }

  Future<void> _openSpeed() {
    return _trackSheet(
        () => showPlaybackSpeedSheet(context, widget.controller));
  }

  Future<void> _openMoreMenu() async {
    _bump();
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        box.size.width - 240,
        kToolbarHeight,
        8,
        0,
      ),
      color: const Color(0xFF1B1E26),
      items: [
        PopupMenuItem(
          value: 'audio',
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.audiotrack_outlined, size: 20),
            title: const Text('Audio tracks'),
            trailing: Text(
              '${widget.controller.value.audioTracks.length}',
              style: const TextStyle(color: Colors.white54),
            ),
          ),
        ),
        PopupMenuItem(
          value: 'subs',
          child: ListTile(
            dense: true,
            leading:
                const Icon(Icons.closed_caption_outlined, size: 20),
            title: const Text('Subtitles'),
            trailing: Text(
              widget.controller.value.selectedSubtitleTrackId == null
                  ? 'Off'
                  : '${widget.controller.value.subtitleTracks.length}',
              style: const TextStyle(color: Colors.white54),
            ),
          ),
        ),
        PopupMenuItem(
          value: 'speed',
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.speed_outlined, size: 20),
            title: const Text('Playback speed'),
            trailing: Text(
              '${widget.controller.value.playbackRate}×',
              style: const TextStyle(color: Colors.white54),
            ),
          ),
        ),
        PopupMenuItem(
          value: 'loop',
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.repeat_outlined, size: 20),
            title: const Text('Repeat'),
            trailing: Text(
              widget.controller.looping ? 'On' : 'Off',
              style: const TextStyle(color: Colors.white54),
            ),
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'info',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.info_outline, size: 20),
            title: Text('Media information'),
          ),
        ),
      ],
    );
    if (!mounted) return;
    switch (choice) {
      case 'audio':
        await _openSettings(tab: PlayerSettingsTab.audio);
      case 'subs':
        await _openSettings(tab: PlayerSettingsTab.subtitles);
      case 'speed':
        await _openSpeed();
      case 'loop':
        setState(
            () => widget.controller.looping = !widget.controller.looping);
      case 'info':
        await _openInfo();
    }
  }

  void _openContextMenu(Offset globalPosition) {
    _trackSheet(() async {
      final choice = await showMenu<String>(
        context: context,
        position: RelativeRect.fromLTRB(
          globalPosition.dx,
          globalPosition.dy,
          globalPosition.dx + 1,
          globalPosition.dy + 1,
        ),
        color: const Color(0xFF1B1E26),
        items: [
          PopupMenuItem(
            value: 'play',
            child: Text(widget.controller.value.isPlaying
                ? 'Pause\tSpace'
                : 'Play\tSpace'),
          ),
          PopupMenuItem(
            value: 'mute',
            child: Text(widget.controller.value.isMuted
                ? 'Unmute\tM'
                : 'Mute\tM'),
          ),
          const PopupMenuDivider(),
          const PopupMenuItem(
              value: 'audio', child: Text('Audio tracks…\tA')),
          const PopupMenuItem(
              value: 'subs', child: Text('Subtitles…\tS')),
          const PopupMenuItem(value: 'speed', child: Text('Speed…')),
          const PopupMenuDivider(),
          const PopupMenuItem(
              value: 'info', child: Text('Media information')),
        ],
      );
      if (!mounted) return;
      switch (choice) {
        case 'play':
          await _togglePlayPause();
        case 'mute':
          await widget.controller
              .setMuted(!widget.controller.value.isMuted);
        case 'audio':
          await _openSettings(tab: PlayerSettingsTab.audio);
        case 'subs':
          await _openSettings(tab: PlayerSettingsTab.subtitles);
        case 'speed':
          await _openSpeed();
        case 'info':
          await _openInfo();
      }
    });
  }

  // -- gestures -----------------------------------------------------------

  void _onTap() => _toggleControls();

  void _onDoubleTapDown(TapDownDetails d) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || box.size.width <= 0) return;
    final x = d.localPosition.dx / box.size.width;
    if (x < 1 / 3) {
      _seekBy(const Duration(seconds: -10));
      _flash('−10s');
    } else if (x > 2 / 3) {
      _seekBy(const Duration(seconds: 10));
      _flash('+10s');
    } else {
      _togglePlayPause();
    }
  }

  void _onHorizontalDragStart(DragStartDetails d) {
    _dragStartX = d.globalPosition.dx;
    _dragStartPosition = widget.controller.value.position;
  }

  void _onHorizontalDragUpdate(DragUpdateDetails d) {
    final duration = widget.controller.value.duration;
    if (duration <= Duration.zero) return;
    final box = context.findRenderObject() as RenderBox?;
    final width = box?.size.width ?? 0;
    if (width <= 0) return;
    final dx = d.globalPosition.dx - _dragStartX;
    final target = Duration(
      milliseconds: (_dragStartPosition.inMilliseconds +
              dx / width * duration.inMilliseconds)
          .round()
          .clamp(0, duration.inMilliseconds),
    );
    setState(() => _dragPreview = target);
    _bump();
  }

  Future<void> _onHorizontalDragEnd() async {
    final target = _dragPreview;
    setState(() => _dragPreview = null);
    if (target != null) await _seekTo(target);
  }

  void _onVerticalDragUpdate(DragUpdateDetails d, bool rightSide) {
    if (!rightSide) return; // no brightness control: left side unused.
    final box = context.findRenderObject() as RenderBox?;
    final height = box?.size.height ?? 0;
    if (height <= 0) return;
    final v = widget.controller.value;
    final next = (v.volume - d.delta.dy / height * 1.5).clamp(0.0, 1.0);
    widget.controller.setVolume(next);
    setState(() => _volumePreview = next);
    _bump();
  }

  void _onVerticalDragEnd() {
    setState(() => _volumePreview = null);
  }

  bool _isRightSide(Offset globalPosition) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return true;
    final local = box.globalToLocal(globalPosition);
    return local.dx > box.size.width * 0.6;
  }

  // -- keyboard -------------------------------------------------------------

  Map<ShortcutActivator, Intent> get _shortcuts => {
        const SingleActivator(LogicalKeyboardKey.space):
            const _PlayPauseIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowLeft):
            const _SeekIntent(Duration(seconds: -10)),
        const SingleActivator(LogicalKeyboardKey.arrowRight):
            const _SeekIntent(Duration(seconds: 10)),
        const SingleActivator(LogicalKeyboardKey.arrowUp):
            const _VolumeIntent(0.05),
        const SingleActivator(LogicalKeyboardKey.arrowDown):
            const _VolumeIntent(-0.05),
        const SingleActivator(LogicalKeyboardKey.keyM):
            const _MuteIntent(),
        const SingleActivator(LogicalKeyboardKey.keyF):
            const _FullscreenIntent(),
        const SingleActivator(LogicalKeyboardKey.keyS):
            const _SubtitlesIntent(),
        const SingleActivator(LogicalKeyboardKey.keyA):
            const _AudioIntent(),
        const SingleActivator(LogicalKeyboardKey.equal):
            const _RateIntent(1),
        const SingleActivator(LogicalKeyboardKey.minus):
            const _RateIntent(-1),
        const SingleActivator(LogicalKeyboardKey.keyJ):
            const _SeekIntent(Duration(seconds: -10)),
        const SingleActivator(LogicalKeyboardKey.keyL):
            const _SeekIntent(Duration(seconds: 10)),
        const SingleActivator(LogicalKeyboardKey.home):
            const _EdgeIntent(true),
        const SingleActivator(LogicalKeyboardKey.end):
            const _EdgeIntent(false),
        const SingleActivator(LogicalKeyboardKey.escape):
            const _EscapeIntent(),
      };

  static const _rateSteps = [
    0.25,
    0.5,
    0.75,
    1.0,
    1.25,
    1.5,
    1.75,
    2.0,
    4.0,
  ];

  Future<void> _stepRate(int dir) async {
    final current = widget.controller.value.playbackRate;
    int idx = _rateSteps.indexWhere((s) => (s - current).abs() < 0.001);
    idx = idx < 0 ? _rateSteps.indexOf(1.0) : idx;
    idx = (idx + dir).clamp(0, _rateSteps.length - 1);
    _bump();
    await widget.controller.setPlaybackRate(_rateSteps[idx]);
    _flash('${_rateSteps[idx]}×');
  }

  // -- build ---------------------------------------------------------------

  BoxFit get _boxFit => switch (_fit) {
        MediaPlayerFit.contain => BoxFit.contain,
        MediaPlayerFit.cover => BoxFit.cover,
        MediaPlayerFit.fill => BoxFit.fill,
        MediaPlayerFit.original => BoxFit.none,
      };

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: _shortcuts,
      child: Actions(
        actions: {
          _PlayPauseIntent: CallbackAction<_PlayPauseIntent>(
              onInvoke: (_) => _togglePlayPause()),
          _SeekIntent: CallbackAction<_SeekIntent>(
              onInvoke: (i) => _seekBy(i.delta)),
          _VolumeIntent: CallbackAction<_VolumeIntent>(
              onInvoke: (i) => _setVolume(
                  widget.controller.value.volume + i.delta)),
          _MuteIntent: CallbackAction<_MuteIntent>(
              onInvoke: (_) => widget.controller.setMuted(
                  !widget.controller.value.isMuted)),
          _FullscreenIntent: CallbackAction<_FullscreenIntent>(
              onInvoke: (_) => widget.onToggleFullscreen?.call()),
          _SubtitlesIntent: CallbackAction<_SubtitlesIntent>(
              onInvoke: (_) => widget.controller.setSubtitlesEnabled(
                  !widget.controller.value.subtitlesEnabled)),
          _AudioIntent: CallbackAction<_AudioIntent>(
              onInvoke: (_) =>
                  _openSettings(tab: PlayerSettingsTab.audio)),
          _RateIntent: CallbackAction<_RateIntent>(
              onInvoke: (i) => _stepRate(i.dir)),
          _EdgeIntent: CallbackAction<_EdgeIntent>(
              onInvoke: (i) => i.toStart
                  ? _seekTo(Duration.zero)
                  : _seekTo(widget.controller.value.duration)),
          _EscapeIntent: CallbackAction<_EscapeIntent>(onInvoke: (_) {
            if (widget.isFullscreen) {
              widget.onToggleFullscreen?.call();
            } else {
              _hideTimer?.cancel();
              setState(() => _controlsVisible = false);
            }
            return null;
          }),
        },
        child: Focus(
          autofocus: true,
          child: Listener(
            onPointerSignal: _isDesktop
                ? (signal) {
                    if (signal is PointerScrollEvent) {
                      _setVolume(widget.controller.value.volume -
                          signal.scrollDelta.dy.sign * 0.05);
                    }
                  }
                : null,
            child: MouseRegion(
              onHover: _isDesktop ? (_) => _bump() : null,
              child: ValueListenableBuilder(
                valueListenable: widget.controller,
                builder: (context, value, _) {
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    color: Colors.black,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Center(
                          child: RotatedBox(
                            quarterTurns: _displayQuarterTurns % 4,
                            child: MediaForgeVideo(
                              controller: widget.controller,
                              fit: _boxFit,
                              showSubtitles: false,
                              // State errors render in [_StateLayer]; keep
                              // the surface itself quiet to avoid duplicates.
                              errorBuilder: (_, _) =>
                                  const SizedBox.shrink(),
                            ),
                          ),
                        ),
                        ValueListenableBuilder(
                          valueListenable: _appearance,
                          builder: (context, appearance, _) {
                            final top = appearance.position ==
                                PlayerSubtitlePosition.top;
                            return Positioned(
                              left: 16,
                              right: 16,
                              top: top ? 72 : null,
                              bottom: top ? null : 96,
                              child: Center(
                                child: PlayerCaptionOverlay(
                                  controller: widget.controller,
                                  style: appearance,
                                ),
                              ),
                            );
                          },
                        ),
                        // Gesture layer (below chrome + state buttons).
                        Positioned.fill(
                          child: GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onTap: _onTap,
                            onDoubleTapDown: _onDoubleTapDown,
                            onHorizontalDragStart:
                                _onHorizontalDragStart,
                            onHorizontalDragUpdate:
                                _onHorizontalDragUpdate,
                            onHorizontalDragEnd: (_) =>
                                _onHorizontalDragEnd(),
                            onHorizontalDragCancel: () => setState(
                                () => _dragPreview = null),
                            onVerticalDragUpdate: (d) =>
                                _onVerticalDragUpdate(
                                    d, _isRightSide(d.globalPosition)),
                            onVerticalDragEnd: (_) =>
                                _onVerticalDragEnd(),
                            onSecondaryTapUp: _isDesktop
                                ? (d) => _openContextMenu(
                                    d.globalPosition)
                                : null,
                          ),
                        ),
                        if (_controlsVisible)
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            child: PlayerTopBar(
                              title: widget.title,
                              subtitle: widget.subtitle,
                              statusLabel: _statusLabel(value),
                              onBack: () {
                                if (widget.onBack != null) {
                                  widget.onBack!();
                                } else {
                                  Navigator.of(context).maybePop();
                                }
                              },
                              hasTorrentStats:
                                  widget.torrentStats != null,
                              onShowTorrentStats: _openInfo,
                              onMore: _openMoreMenu,
                            ),
                          ),
                        if (_controlsVisible)
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            child: PlayerBottomBar(
                              position: _dragPreview ?? value.position,
                              buffered: value.buffered,
                              duration: value.duration,
                              isPlaying: value.isPlaying,
                              showRemaining: _showRemaining,
                              onToggleRemaining: () => setState(() =>
                                  _showRemaining = !_showRemaining),
                              onSeekCommitted: _seekTo,
                              onPlayPause: _togglePlayPause,
                              onReplay10: () => _seekBy(
                                  const Duration(seconds: -10)),
                              onForward10: () => _seekBy(
                                  const Duration(seconds: 10)),
                              playbackRate: value.playbackRate,
                              onSpeed: _openSpeed,
                              volume: value.volume,
                              isMuted: value.isMuted,
                              onVolume: _setVolume,
                              onMuteToggle: () =>
                                  widget.controller.setMuted(
                                      !value.isMuted),
                              showVolumeSlider: _wide,
                              subtitleActive:
                                  value.selectedSubtitleTrackId !=
                                          null &&
                                      value.subtitlesEnabled,
                              onSubtitles: () => _openSettings(
                                  tab: PlayerSettingsTab.subtitles),
                              onAudio: () => _openSettings(
                                  tab: PlayerSettingsTab.audio),
                              onSettings: () => _openSettings(),
                              onPrevious: widget.onPrevious,
                              onNext: widget.onNext,
                              onPictureInPicture:
                                  widget.onPictureInPicture,
                              onToggleFullscreen:
                                  widget.onToggleFullscreen,
                              isFullscreen: widget.isFullscreen,
                              chapters: widget.chapters,
                              thumbnailBuilder:
                                  widget.thumbnailBuilder,
                              wide: _wide,
                            ),
                          ),
                        if (_controlsVisible &&
                            !value.hasError &&
                            !value.isCompleted &&
                            !(value.isBuffering &&
                                value.isPlaying) &&
                            value.isInitialized)
                          // Center wrapper is load-bearing: a bare Row
                          // child of StackFit.expand fills the width and
                          // packs its buttons to the left edge.
                          Center(
                            child: CenterPlaybackControls(
                              isPlaying: value.isPlaying,
                              onPlayPause: _togglePlayPause,
                              onReplay10: () => _seekBy(
                                  const Duration(seconds: -10)),
                              onForward10: () => _seekBy(
                                  const Duration(seconds: 10)),
                            ),
                          ),
                        _StateLayer(
                          value: value,
                          recentSeek: _recentSeek,
                          flashLabel: _flashLabel,
                          dragPreview: _dragPreview,
                          duration: value.duration,
                          volumePreview: _volumePreview,
                          volume: value.volume,
                          onRetry: () async {
                            if (widget.onRetry != null) {
                              await widget.onRetry!();
                            } else {
                              final media =
                                  widget.controller.media;
                              if (media != null) {
                                await widget.controller
                                    .open(media, play: true);
                              }
                            }
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Center state indicators (non-interactive) + error/completed actions.
class _StateLayer extends StatelessWidget {
  const _StateLayer({
    required this.value,
    required this.recentSeek,
    required this.flashLabel,
    required this.dragPreview,
    required this.duration,
    required this.volumePreview,
    required this.volume,
    required this.onRetry,
  });

  final MediaForgePlayerValue value;
  final bool recentSeek;
  final String? flashLabel;
  final Duration? dragPreview;
  final Duration duration;
  final double? volumePreview;
  final double volume;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    {
      final List<Widget> layers = [];
      if (!value.isInitialized && !value.hasError) {
        layers.add(const _CenterStatus(
          child: CircularProgressIndicator(color: Colors.white),
          label: 'Loading…',
        ));
      } else if (value.hasError) {
        layers.add(_ErrorCard(
          message: value.errorDescription ?? 'Playback error',
          onRetry: onRetry,
        ));
      } else if (value.isCompleted) {
        layers.add(_ReplayCard(
          onReplay: onRetry,
        ));
      } else if (value.isBuffering && value.isPlaying) {
        layers.add(_CenterStatus(
          child:
              const CircularProgressIndicator(color: Colors.white),
          label: recentSeek ? 'Seeking…' : 'Buffering…',
        ));
      }
      if (flashLabel != null) {
        layers.add(Center(
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              flashLabel!,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ));
      }
      if (dragPreview != null) {
        layers.add(
          Positioned(
            top: 90,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white24),
                ),
                child: Text(
                  '${formatDuration(dragPreview!)} / ${formatDuration(duration)}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ),
        );
      }
      if (volumePreview != null) {
        layers.add(
          Positioned(
            right: 24,
            top: 0,
            bottom: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.volume_up_outlined,
                        color: Colors.white),
                    const SizedBox(height: 6),
                    Text(
                      '${(volume.clamp(0.0, 1.0) * 100).round()}%',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }
      if (layers.isEmpty) return const SizedBox.shrink();
      return Stack(
        fit: StackFit.expand,
        children: [
          for (final layer in layers)
            layer is Positioned || layer is Center
                ? layer
                : Center(child: layer),
        ],
      );
    }
  }
}

class _CenterStatus extends StatelessWidget {
  const _CenterStatus({required this.child, required this.label});
  final Widget child;
  final String label;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: 56, height: 56, child: child),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              label,
              style: const TextStyle(
                  fontSize: 13, color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});
  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 32),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF1B1E26).withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline,
                size: 40, color: Colors.redAccent),
            const SizedBox(height: 12),
            const Text(
              'Playback failed',
              style:
                  TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 12, color: Colors.white60),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () => onRetry(),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReplayCard extends StatelessWidget {
  const _ReplayCard({required this.onReplay});
  final Future<void> Function() onReplay;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: PlayerIconButton(
        icon: Icons.replay,
        tooltip: 'Replay',
        onPressed: () => onReplay(),
        size: 76,
        iconSize: 40,
      ),
    );
  }
}

// -- keyboard intents ---------------------------------------------------------

class _PlayPauseIntent extends Intent {
  const _PlayPauseIntent();
}

class _SeekIntent extends Intent {
  const _SeekIntent(this.delta);
  final Duration delta;
}

class _VolumeIntent extends Intent {
  const _VolumeIntent(this.delta);
  final double delta;
}

class _MuteIntent extends Intent {
  const _MuteIntent();
}

class _FullscreenIntent extends Intent {
  const _FullscreenIntent();
}

class _SubtitlesIntent extends Intent {
  const _SubtitlesIntent();
}

class _AudioIntent extends Intent {
  const _AudioIntent();
}

class _RateIntent extends Intent {
  const _RateIntent(this.dir);
  final int dir;
}

class _EdgeIntent extends Intent {
  const _EdgeIntent(this.toStart);
  final bool toStart;
}

class _EscapeIntent extends Intent {
  const _EscapeIntent();
}
