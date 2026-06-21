import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_forge_kit/video_forge_kit.dart';
import 'package:path/path.dart' as p;
import 'package:video_forge_editor/src/debug/diagnostics_panel.dart';
import 'package:video_forge_editor/src/layout/desktop_timeline_layout.dart';
import 'package:video_forge_editor/src/layout/mobile_stories_layout.dart';
import 'package:video_forge_editor/src/models/recent_audio_track.dart';
import 'package:video_forge_editor/src/models/video_export_result.dart';
import 'package:video_forge_editor/src/panels/clip_effects_panel.dart';
import 'package:video_forge_editor/src/panels/clip_motion_panel.dart';
import 'package:video_forge_editor/src/panels/inline_text_editor.dart';
import 'package:video_forge_editor/src/panels/lumina_sticker_panel.dart';
import 'package:video_forge_editor/src/panels/music_picker_sheet.dart';
import 'package:video_forge_editor/src/panels/sticker_picker_sheet.dart';
import 'package:video_forge_editor/src/panels/text_overlay_edit_chrome.dart';
import 'package:video_forge_editor/src/panels/text_overlay_sheet.dart';
import 'package:video_forge_editor/src/playback/playback_backend.dart';
import 'package:video_forge_editor/src/playback/rust_playback_backend.dart';
import 'package:video_forge_editor/src/services/audio_picker.dart';
import 'package:video_forge_editor/src/services/clip_effects_session.dart';
import 'package:video_forge_editor/src/services/editor_output_paths.dart';
import 'package:video_forge_editor/src/services/media_ingest.dart';
import 'package:video_forge_editor/src/theme/lumina_tokens.dart';
import 'package:video_forge_editor/src/widgets/audio_waveform_visualizer.dart';
import 'package:video_forge_editor/src/widgets/editor_bottom_nav.dart';
import 'package:video_forge_editor/src/widgets/filmstrip_trimmer.dart';
import 'package:video_forge_editor/src/widgets/modern_timeline.dart';
import 'package:video_forge_editor/src/widgets/overlay_timing_tracks_bar.dart';
import 'package:video_forge_editor/src/widgets/clip_transform_gesture_layer.dart';
import 'package:video_forge_editor/src/widgets/rust_video_canvas.dart';
import 'video_editor_session.dart';
import 'video_forge_editor_config.dart';

class VideoEditorScreen extends StatefulWidget {
  const VideoEditorScreen({
    super.key,
    required this.config,
  });

  final VideoForgeEditorConfig config;

  String get initialPath => config.initialVideoPath!;
  String? get displayName => config.title;

  @override
  State<VideoEditorScreen> createState() => _VideoEditorScreenState();
}

class _VideoEditorScreenState extends State<VideoEditorScreen> {
  static const _filmstripFrames = 10;
  static const _filmstripThumbWidth = 160;
  static final ChangeNotifier _dummyNotifier = ChangeNotifier();
  StreamSubscription<ProgressEvent>? _progressSub;

  // ── Backend (Rust MediaRuntime only) ──
  bool _showDiagnostics = false;
  PlaybackBackend? _backend;
  double _playbackRate = 1.0;
  bool _isLooping = false;
  /// Last video clip id whose speed was pushed to the playback engine.
  String? _activeSpeedClipId;
  double? _activeEffectiveSpeed;
  /// Session/bootstrap effects applied to the first clip on load (then cleared).
  ClipEffects? _pendingSessionClipEffects;

  List<String> _filmstripPaths = [];
  late final TimelineController _timeline;
  bool _loadingFilmstrip = false;
  bool _busy = false;
  String _statusLine = 'Initializing player…';
  String _metricsLine = '';

  double _startSec = 0;
  double _endSec = 0;
  double _playheadSec = 0;
  final _playheadNotifier = ValueNotifier<double>(0.0);
  DateTime? _lastTimelineRebuild;

  CompressionPreset _exportPreset = CompressionPreset.instagram;
  bool _preferHw = true;
  bool _muteOriginalAudio = false;
  double _timelineHeight = 180.0;
  bool _bottomSheetOpen = false;
  /// Tracks which selection ID opened the inspector bottom sheet, so we only
  /// re-open when the selection actually changes — not on every timeline update.
  String? _inspectorOpenedForId;
  double _timelineZoom = 1.0;
  double _inspectorWidth = 380.0;
  final List<RecentAudioTrack> _recentAudioTracks = [];
  final Map<String, Future<String?>> _normalizationFutures = {};
  int _pendingNormalizationCount = 0;
  VideoEditorSession? _session;
  final Map<String, int> _textReplayTokens = {};
  EditorNavTool _activeNavTool = EditorNavTool.media;
  /// Bumped on each video load so preview [Texture] widgets are not reused.
  int _previewSessionId = 0;
  late final ClipEffectsSession _clipEffectsSession;
  String? _lastAudioSyncSignature;
  String? _lastSelectedVideoClipId;
  String? _activeTrimClipId;
  int _seekGeneration = 0;
  bool _clipTransitionInFlight = false;

  VideoOverlayItem? get _selectedTextOverlay {
    final overlay = _selectedOverlay();
    if (overlay == null || !overlay.isTextOverlay) return null;
    return overlay;
  }

  @override
  void initState() {
    super.initState();
    _session = widget.config.session;
    _timeline = _session?.timeline ?? TimelineController();
    if (_session != null) {
      _muteOriginalAudio = _session!.muteOriginalAudio;
      _exportPreset = _session!.exportPreset;
      _preferHw = _session!.preferHw;
      _playbackRate = _session!.playbackRate;
      final sessionFx = _session!.clipEffects;
      if (!ClipEffectsKit.isIdentity(sessionFx)) {
        _pendingSessionClipEffects = sessionFx;
      }
      _session!.backend = _backend;
    }
    _showDiagnostics = widget.config.showDiagnostics;
    _clipEffectsSession = ClipEffectsSession(
      timeline: _timeline,
      onCommitted: _syncSession,
    );
    _timeline.addListener(_onTimelineUpdated);
    final path = widget.config.initialVideoPath;
    if (path != null && path.isNotEmpty) {
      _loadVideo(path);
    }
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    _clipEffectsSession.dispose();
    _timeline.removeListener(_onTimelineUpdated);
    if (_session == null) {
      _timeline.dispose();
    }
    _playheadNotifier.dispose();
    unawaited(_tearDownBackend());
    if (_session == null) {
      _backend?.dispose();
      _backend = null;
    }
    super.dispose();
  }

  void _syncSession() {
    final session = _session;
    if (session == null) return;
    session.muteOriginalAudio = _muteOriginalAudio;
    session.exportPreset = _exportPreset;
    session.preferHw = _preferHw;
    session.playbackRate = _playbackRate;
    session.loopOnFinish = _isLooping;
    session.backend = _backend;
    session.startSec = _startSec;
    session.endSec = _endSec;
    session.playheadSec = _playheadSec;
    session.clipEffects = ClipEffectsKit.forClip(_effectsTargetClip);
  }

  /// Selected video clip, or the clip under the playhead when nothing is selected.
  VideoTimelineClip? get _effectsTargetClip {
    final selectedId = _timeline.selectedVideoClipId;
    if (selectedId != null) {
      return _timeline.clipById(selectedId);
    }
    return _timeline.clipAtTimelineMs(_playheadTimelineMs);
  }

  /// Clip currently shown in the preview (playhead position).
  VideoTimelineClip? get _previewClip =>
      _timeline.clipAtTimelineMs(_playheadTimelineMs);

  void _ensureEffectsClipSelected() {
    if (_timeline.selectedVideoClipId != null) return;
    final clip = _timeline.clipAtTimelineMs(_playheadTimelineMs);
    if (clip != null) {
      _timeline.selectVideoClip(clip.id);
    }
  }

  Future<void> _applyClipSpeed(double rate) async {
    final clamped = rate.clamp(0.25, 4.0);
    if ((_playbackRate - clamped).abs() < 0.001) return;
    _playbackRate = clamped;
    await _backend?.setPlaybackRate(clamped);
  }

  void _syncPlaybackSpeedToActiveClip({bool force = false}) {
    final clip = _previewClip;
    if (clip == null) return;
    final localMs =
        ClipEffectsKit.localTimelineMs(clip, (_playheadSec * 1000).round());
    final speed =
        ClipEffectsKit.effectiveSpeedAt(ClipEffectsKit.forClip(clip), localMs);
    if (!force &&
        clip.id == _activeSpeedClipId &&
        _activeEffectiveSpeed != null &&
        (speed - _activeEffectiveSpeed!).abs() < 0.001) {
      return;
    }
    _activeSpeedClipId = clip.id;
    _activeEffectiveSpeed = speed;
    unawaited(_applyClipSpeed(speed));
  }

  void _applyClipEffectsCommit(ClipEffects effects, {required String clipId}) {
    _clipEffectsSession.commitNow(clipId, effects);
    if (_previewClip?.id == clipId) {
      _activeSpeedClipId = null;
      final clip = _previewClip!;
      final localMs =
          ClipEffectsKit.localTimelineMs(clip, (_playheadSec * 1000).round());
      unawaited(
        _applyClipSpeed(
          ClipEffectsKit.effectiveSpeedAt(effects, localMs),
        ),
      );
    }
    _syncSession();
  }

  void _previewClipEffects(ClipEffects effects, {required String clipId}) {
    _clipEffectsSession.previewEffects(clipId, effects);
    if (_previewClip?.id == clipId) {
      _activeSpeedClipId = null;
      final clip = _previewClip!;
      final localMs =
          ClipEffectsKit.localTimelineMs(clip, (_playheadSec * 1000).round());
      unawaited(
        _applyClipSpeed(
          ClipEffectsKit.effectiveSpeedAt(effects, localMs),
        ),
      );
    }
  }

  void _resetClipEffects(String clipId) {
    _applyClipEffectsCommit(ClipEffectsKit.identity(), clipId: clipId);
  }

  Future<void> _seekToClipStart(VideoTimelineClip clip) async {
    final backend = _backend;
    if (backend?.isPlaying ?? false) {
      backend!.pause();
    }
    _activeTrimClipId = null;
    final sec = clip.timelineStartMs / 1000.0;
    _playheadSec = sec;
    _playheadNotifier.value = sec;
    await _applySeekFromTimelineMs(clip.timelineStartMs);
    debugPrint(
      '[ClipSelect] seek clip=${clip.id} timeline=${clip.timelineStartMs}ms',
    );
  }

  void _onVideoClipSelectionChanged(String? clipId) {
    if (clipId == _lastSelectedVideoClipId) return;
    _lastSelectedVideoClipId = clipId;
    if (clipId == null) return;
    final clip = _timeline.clipById(clipId);
    if (clip == null) return;
    _clipEffectsSession.clearPreview(clipId: clipId);
    unawaited(_seekToClipStart(clip));
  }

  bool get _hasSelectedVideoClip => _timeline.selectedVideoClipId != null;

  VideoTimelineClip? get _selectedVideoClip {
    final id = _timeline.selectedVideoClipId;
    if (id == null) return null;
    return _timeline.clipById(id);
  }

  /// When a clip is selected, keep playhead inside it before starting playback.
  Future<void> _ensurePlayheadInSelectedClip() async {
    final clip = _selectedVideoClip;
    if (clip == null) return;
    final ph = _playheadTimelineMs;
    if (ph < clip.timelineStartMs || ph >= clip.timelineEndMs) {
      await _seekToClipStart(clip);
    }
  }

  String _audioClipsSignature() {
    return _timeline.audioClips
        .map(
          (c) =>
              '${c.id}:${c.sourcePath}:${c.timelineStartMs}:${c.durationMs}:'
              '${c.sourceStartMs}:${c.volume}:${c.muted}',
        )
        .join('|');
  }

  ClipEffects? get _exportClipEffects {
    if (_timeline.videoClips.length == 1) {
      final effects = ClipEffectsKit.forClip(_timeline.videoClips.first);
      return ClipEffectsKit.isIdentity(effects) ? null : effects;
    }
    return null;
  }

  Widget _buildClipEffectsEditor(VideoTimelineClip clip) {
    return ValueListenableBuilder<ClipEffectsPreview?>(
      valueListenable: _clipEffectsSession.preview,
      builder: (context, live, _) {
        final effects = _clipEffectsSession.effectsForClip(clip);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Transform & speed · ${_formatDuration(clip.durationMs)}',
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            ClipEffectsPanel(
              key: ValueKey(clip.id),
              effects: effects,
              clipDurationMs: clip.durationMs,
              onPreview: (fx) => _previewClipEffects(fx, clipId: clip.id),
              onCommit: (fx) => _applyClipEffectsCommit(fx, clipId: clip.id),
              onReset: () => _resetClipEffects(clip.id),
            ),
            const SizedBox(height: LuminaTokens.space3),
            ClipMotionPanel(
              durationMs: clip.durationMs,
              currentEffects: effects,
              onPresetSelected: (fx) =>
                  _applyClipEffectsCommit(fx, clipId: clip.id),
            ),
            const SizedBox(height: LuminaTokens.space2),
            OutlinedButton.icon(
              onPressed: _splitAtPlayhead,
              icon: const Icon(Icons.content_cut, size: 18),
              label: const Text('Split at playhead & edit next segment'),
            ),
            const SizedBox(height: LuminaTokens.space2),
            const Text(
              'Pinch the preview to zoom, rotate, and pan the selected clip.',
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSelectClipForEffectsHint() {
    return const Padding(
      padding: EdgeInsets.all(LuminaTokens.space4),
      child: Text(
        'Select a video clip on the timeline, or move the playhead inside a clip, '
        'to edit zoom, rotation, and speed for that segment only.',
        style: TextStyle(color: Colors.white54, fontSize: 13),
        textAlign: TextAlign.center,
      ),
    );
  }

  void _onTimelineUpdated() {
    _onVideoClipSelectionChanged(_timeline.selectedVideoClipId);

    final backend = _backend;
    if (backend is RustPlaybackBackend) {
      final audioSig = _audioClipsSignature();
      if (audioSig != _lastAudioSyncSignature) {
        _lastAudioSyncSignature = audioSig;
        final clips = _timeline.audioClips
            .map((c) => AudioClipInfo(
                  id: c.id,
                  sourcePath: c.sourcePath,
                  volume: c.volume,
                  timelineStartMs: c.timelineStartMs,
                  durationMs: c.durationMs,
                  sourceStartMs: c.sourceStartMs,
                  muted: c.muted,
                ))
            .toList();
        backend.syncOverlayTracks(clips);
      }
    }

    if (mounted && !_clipEffectsSession.isLiveEditing) {
      setState(() {});
    }

    // Check for new selections on narrow layout to open bottom sheet
    // Only open when the selection ID actually changes — not on every
    // timeline update (which fires for playback, trim, volume, etc).
    if (mounted) {
      final isNarrow =
          MediaQuery.sizeOf(context).width < LuminaTokens.breakpointTablet;
      if (isNarrow) {
        final selSig = _currentSelectionSignature;
        final hasSel = selSig != null;
        final isNewSelection = hasSel && selSig != _inspectorOpenedForId;

        if (isNewSelection) {
          final overlay = _selectedOverlay();
          if (isNarrow && overlay != null && overlay.isTextOverlay) {
            _inspectorOpenedForId = selSig;
            debugPrint('[StoriesChrome] text selected id=${overlay.id} inline-edit');
            return;
          }

          _inspectorOpenedForId = selSig;
          _bottomSheetOpen = true;
          showModalBottomSheet<void>(
            context: context,
            backgroundColor: const Color(0xFF151517),
            isScrollControlled: true,
            showDragHandle: true,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            builder: (ctx) {
              return AnimatedPadding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(ctx).viewInsets.bottom,
                ),
                duration: const Duration(milliseconds: 100),
                child: SafeArea(
                  child: SizedBox(
                    height: MediaQuery.sizeOf(context).height * 0.55,
                    child: _buildInspectorPanel(Theme.of(context), false),
                  ),
                ),
              );
            },
          ).then((_) {
            _bottomSheetOpen = false;
            _inspectorOpenedForId = null;
            _clearSelections();
          });
        } else if (!hasSel && _bottomSheetOpen) {
          // Selection was cleared externally (e.g. close button) — pop sheet
          if (Navigator.canPop(context)) {
            Navigator.pop(context);
          }
        }
      }
    }
  }

  void _clearSelections() {
    _timeline.selectVideoClip(null);
    _timeline.selectAudioClip(null);
    _timeline.selectOverlay(null);
  }

  /// Returns a stable signature for the current selection, or null if nothing
  /// is selected. Used to detect when the user selects a different item and
  /// the inspector sheet should be opened/refreshed.
  String? get _currentSelectionSignature {
    final vid = _timeline.selectedVideoClipId;
    if (vid != null) return 'video:$vid';
    final aud = _timeline.selectedAudioClipId;
    if (aud != null) return 'audio:$aud';
    final ov = _timeline.selectedOverlayId;
    if (ov != null) return 'overlay:$ov';
    return null;
  }

  MediaInfo? get _activeMediaInfo => _backend?.mediaInfo;

  int get _activeDurationMs => _backend?.durationMs ?? 0;

  /// Callback for the Rust playback backend. Drives the playhead and
  /// throttles full UI rebuilds to ~120 ms during playback.
  void _onBackendUpdated() {
    final backend = _backend;
    if (backend == null || !mounted) return;

    final sourceMs = backend.positionMs;
    final timelineSec = _timelineSecFromSourcePts(sourceMs);
    final clampedSec = _safeClamp(
      timelineSec,
      0,
      _timelineDurationSec > 0 ? _timelineDurationSec : _endSec,
    );

    _playheadSec = clampedSec;
    _playheadNotifier.value = clampedSec;

    _syncPlaybackSpeedToActiveClip();

    if (backend.isPlaying) {
      unawaited(_advancePastClipEndIfNeeded(sourceMs));
    }

    final now = DateTime.now();
    final lastRebuild = _lastTimelineRebuild;
    final shouldRebuild = !backend.isPlaying ||
        lastRebuild == null ||
        now.difference(lastRebuild).inMilliseconds >= 120;

    if (shouldRebuild) {
      _lastTimelineRebuild = now;
      setState(() {
        if (backend.isPlaying) {
          _updatePlaybackMetrics(backend);
        }
      });
    }
  }

  void _updatePlaybackMetrics(PlaybackBackend backend) {
    final info = backend.mediaInfo;
    if (info == null) {
      _metricsLine = 'Rust MediaRuntime';
      return;
    }
    _metricsLine = 'Rust MediaRuntime · ${info.width}×${info.height} · ${info.videoCodec}';
  }

  Future<void> _tearDownBackend() async {
    final backend = _backend;
    if (backend == null) return;
    _backend = null;
    if (_session != null) {
      _session!.backend = null;
    }
    backend.removeListener(_onBackendUpdated);
    backend.pause();
    final handle = backend is RustPlaybackBackend ? backend.textureHandle : null;
    debugPrint('[VideoEditor] tearing down backend handle=$handle');
    await backend.close();
  }

  Future<void> _cancelAndClose() async {
    widget.config.onCancel?.call();
    await _tearDownBackend();
    if (mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _loadVideo(String path) async {
    setState(() {
      _busy = true;
      _statusLine = 'Loading video…';
    });

    try {
      await _tearDownBackend();
      _previewSessionId++;
      // Use a unique handle so GPU texture registration works.
      final handle = DateTime.now().millisecondsSinceEpoch & 0x7FFFFFFF;
      final backend = RustPlaybackBackend(
        textureHandle: handle,
        previewMaxEdge: widget.config.previewMaxEdge,
      );
      _backend = backend;
      backend.addListener(_onBackendUpdated);
      await backend.open(path);
      await backend.setEmbeddedAudioMuted(_muteOriginalAudio);
      _syncSession();

      // Start the engine so the first frame is presented. Stay playing if
      // autoPlay is enabled, otherwise pause so the timeline opens in a
      // "loaded but not playing" state.
      _isLooping = widget.config.loopOnFinish;
      debugPrint(
        '[VideoEditor] autoPlay=${widget.config.autoPlay} loopOnFinish=${widget.config.loopOnFinish}',
      );
      await backend.play();
      if (widget.config.loopOnFinish) {
        await backend.setLooping(true);
      }
      if (!widget.config.autoPlay) {
        backend.pause();
      }

      final info = backend.mediaInfo ?? await VideoProcessor.getMediaInfo(path);
      final dur = info.durationMs.toInt() / 1000.0;
      final durationMs = info.durationMs.toInt();
      _timeline.loadPrimaryVideo(
        sourcePath: path,
        durationMs: durationMs > 0 ? durationMs : 1000,
      );

      final pending = _pendingSessionClipEffects;
      if (pending != null && _timeline.videoClips.isNotEmpty) {
        _timeline.updateVideoClip(
          _timeline.videoClips.first.copyWith(effects: pending),
        );
        _pendingSessionClipEffects = null;
      }

      setState(() {
        _startSec = 0;
        _endSec = dur > 0 ? dur : 1;
        _playheadSec = 0;
        _statusLine = 'Ready · ${info.width}×${info.height} · ${info.videoCodec}';
        _busy = false;
      });

      _updatePlaybackMetrics(backend);
      _activeTrimClipId = null;
      backend.setTrimRange(
        startMs: (_startSec * 1000).round(),
        endMs: (_endSec * 1000).round(),
      );
      await _applySeekFromTimelineMs(0);

      await _buildFilmstrip();
    } catch (e) {
      setState(() {
        _statusLine = 'Load failed: $e';
        _busy = false;
      });
    }
  }

  Future<void> _buildFilmstrip() async {
    setState(() => _loadingFilmstrip = true);
    try {
      final duration = _activeDurationMs;
      final durationSeconds = duration / 1000.0;
      final positions = _evenlySpacedPositions(_filmstripFrames, durationSeconds);
      
      final paths = await VideoProcessor.batchThumbnailPathsCached(
        input: widget.initialPath,
        positions: positions,
        width: _filmstripThumbWidth,
      );
      
      if (mounted) {
        setState(() {
          _filmstripPaths = paths;
        });
      }
    } catch (e) {
      debugPrint('Filmstrip error: $e');
    } finally {
      if (mounted) {
        setState(() => _loadingFilmstrip = false);
      }
    }
  }

  List<Duration> _evenlySpacedPositions(int count, double durationSec) {
    if (count <= 1 || durationSec <= 0) {
      return [Duration.zero];
    }
    final totalMs = (durationSec * 1000).round();
    // Cap the end slightly before the actual duration to avoid seeking past EOF
    final maxSeekMs = totalMs > 200 ? totalMs - 200 : (totalMs > 50 ? totalMs - 50 : 0);
    return List.generate(count, (i) {
      final ms = (maxSeekMs * i / (count - 1)).round();
      return Duration(milliseconds: ms);
    });
  }

  static double _safeClamp(double value, double lower, double upper) {
    if (lower > upper) return lower;
    return value.clamp(lower, upper);
  }

  double get _timelineDurationSec =>
      _timeline.durationMs > 0 ? _timeline.durationMs / 1000.0 : _endSec;

  int get _playheadTimelineMs => (_playheadSec * 1000).round();

  double _timelineSecFromSourcePts(int sourcePtsMs) {
    return timelineSecFromSourcePts(
      sourcePtsMs: sourcePtsMs,
      sourcePath: widget.initialPath,
      clips: _timeline.videoClips
          .map(
            (c) => TimelineClipMapping(
              sourcePath: c.sourcePath,
              sourceStartMs: c.sourceStartMs,
              sourceEndMs: c.sourceEndMs,
              timelineStartMs: c.timelineStartMs,
            ),
          )
          .toList(),
    );
  }

  void _syncFilmstripToSingleClip() {
    if (_timeline.videoClips.length != 1) return;
    final clip = _timeline.videoClips.first;
    _timeline.updateVideoClip(
      clip.copyWith(
        sourceStartMs: (_startSec * 1000).round(),
        sourceEndMs: (_endSec * 1000).round(),
      ),
    );
  }

  Future<void> _applySeekFromTimelineMs(int timelineMs) async {
    final backend = _backend;
    if (backend == null || !backend.isOpen) return;

    final target = _timeline.seekTargetAt(timelineMs);
    if (target == null) return;

    final gen = ++_seekGeneration;

    final clip = _timeline.clipById(target.clipId);
    if (clip != null && clip.id != _activeTrimClipId) {
      _activeTrimClipId = clip.id;
      backend.setTrimRange(
        startMs: clip.sourceStartMs,
        endMs: clip.sourceEndMs,
      );
    }

    await backend.seekTo(Duration(milliseconds: target.sourceMs));
    if (gen != _seekGeneration || !mounted) return;

    _activeSpeedClipId = null;
    _syncPlaybackSpeedToActiveClip(force: true);
  }

  Future<void> _advancePastClipEndIfNeeded(int sourcePtsMs) async {
    if (_clipTransitionInFlight) return;
    final backend = _backend;
    if (backend == null || !backend.isPlaying) return;

    final clip = _timeline.clipAtTimelineMs(_playheadTimelineMs);
    if (clip == null) return;
    if (sourcePtsMs < clip.sourceEndMs - 80) return;

    _clipTransitionInFlight = true;
    try {
      final selected = _selectedVideoClip;
      if (selected != null && clip.id == selected.id) {
        if (_isLooping) {
          await _seekToClipStart(selected);
          if (backend.isOpen && !backend.isPlaying) {
            await backend.play();
          }
          return;
        }
        backend.pause();
        if (mounted) {
          setState(() => _statusLine = 'Paused at end of selected clip');
        }
        return;
      }

      final index = _timeline.videoClips.indexWhere((c) => c.id == clip.id);
      if (index < 0 || index >= _timeline.videoClips.length - 1) {
        if (_isLooping) {
          return;
        }
        backend.pause();
        if (mounted) {
          setState(() => _statusLine = 'Paused at end of clip');
        }
        return;
      }
      final next = _timeline.videoClips[index + 1];
      setState(() => _playheadSec = next.timelineStartMs / 1000.0);
      _playheadNotifier.value = next.timelineStartMs / 1000.0;
      await _applySeekFromTimelineMs(next.timelineStartMs);
      if (backend.isOpen && !backend.isPlaying) {
        await backend.play();
      }
    } finally {
      _clipTransitionInFlight = false;
    }
  }

  (int startMs, int endMs) _exportTrimMs() {
    final range = _timeline.exportRangeForPrimarySource();
    var startMs = (_startSec * 1000).round();
    var endMs = (_endSec * 1000).round();
    if (range != null) {
      startMs = math.max(startMs, range.startMs);
      endMs = math.min(endMs, range.endMs);
    }
    if (endMs <= startMs) {
      endMs = startMs + 1;
    }
    return (startMs, endMs);
  }

  void _showCommandPalette() {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return _CommandPaletteDialog(
          onAction: (action) {
            Navigator.pop(ctx);
            _executeCommand(action);
          },
          showDiagnostics: _showDiagnostics,
        );
      },
    );
  }

  void _executeCommand(String action) {
    switch (action) {
      case 'add_text':
        _addTextOverlay();
        break;
      case 'add_emoji':
        _addEmojiOverlay();
        break;
      case 'add_audio':
        _pickAudioTrack();
        break;
      case 'split':
        _splitAtPlayhead();
        break;
      case 'toggle_play':
        _togglePlayback();
        break;
      case 'toggle_diagnostics':
        setState(() {
          _showDiagnostics = !_showDiagnostics;
        });
        break;
      case 'clear_overlays':
        _timeline.clearOverlays();
        setState(() {
          _statusLine = 'Cleared all overlays';
        });
        break;
      case 'export':
        _exportVideo();
        break;
    }
  }

  Future<void> _pickAudioTrack() async {
    await _showMusicPicker();
  }

  AudioTimelineClip? get _primaryAudioClip =>
      _timeline.audioClips.isNotEmpty ? _timeline.audioClips.first : null;

  String? get _primaryAudioDisplayName {
    final clip = _primaryAudioClip;
    if (clip == null) return null;
    for (final recent in _recentAudioTracks) {
      if (recent.path == clip.sourcePath) return recent.displayName;
    }
    return p.basename(clip.sourcePath);
  }

  bool get _hasPendingNormalization => _pendingNormalizationCount > 0;

  Future<void> _showMusicPicker() async {
    final clip = _primaryAudioClip;
    List<double> waveform = const [];
    final rust = _backend as RustPlaybackBackend?;
    if (rust != null) {
      try {
        final samples = await rust.engine?.getAudioWaveform();
        if (samples != null) {
          waveform = samples.map((s) => s.toDouble()).toList();
        }
      } catch (_) {}
    }

    if (!mounted) return;
    await MusicPickerSheet.show(
      context,
      recentTracks: _recentAudioTracks,
      selectedClip: clip,
      muteOriginalAudio: _muteOriginalAudio,
      waveformSamples: waveform,
      onMuteOriginalChanged: (v) {
        setState(() => _muteOriginalAudio = v);
        _syncSession();
        _backend?.setEmbeddedAudioMuted(v);
      },
      onVolumeChanged: (v) {
        final current = _primaryAudioClip;
        if (current == null) return;
        _timeline.updateAudioClip(current.copyWith(volume: v));
        setState(() {});
      },
      onSourceStartChanged: (ms) {
        final current = _primaryAudioClip;
        if (current == null) return;
        _timeline.updateAudioClip(current.copyWith(sourceStartMs: ms));
        _playheadSec = current.timelineStartMs / 1000.0;
        _playheadNotifier.value = _playheadSec;
        _applySeekFromTimelineMs(current.timelineStartMs);
        setState(() {});
      },
      onRemoveTrack: () {
        final current = _primaryAudioClip;
        if (current != null) {
          _timeline.removeAudioClip(current.id);
        }
        setState(() {});
      },
      onTrackPicked: _ingestAudioFromPick,
    );
  }

  Future<void> _ingestAudioFromPick(AudioPickResult pick) async {
    final isMobile =
        MediaQuery.sizeOf(context).width < LuminaTokens.breakpointTablet;
    if (isMobile) {
      for (final existing in List<AudioTimelineClip>.from(_timeline.audioClips)) {
        _timeline.removeAudioClip(existing.id);
      }
    }

    setState(() => _statusLine = 'Importing audio…');
    final ingested = await MediaIngest.ingestLocalAudio(
      pick.path,
      onStatus: (s) {
        if (mounted) setState(() => _statusLine = s);
      },
    );
    if (ingested.phase != MediaIngestPhase.ready ||
        ingested.stablePath == null ||
        ingested.info == null) {
      if (mounted) {
        setState(() => _statusLine = ingested.error ?? 'Audio import failed');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ingested.error ??
                  'Could not import audio. Try a file from Files instead of DRM-protected tracks.',
            ),
          ),
        );
      }
      return;
    }

    final stablePath = ingested.stablePath!;
    final sourceDurationMs = ingested.info!.durationMs.toInt();
    final displayName = pick.displayName ?? p.basename(stablePath);

    _recentAudioTracks.removeWhere((t) => t.path == stablePath);
    _recentAudioTracks.insert(
      0,
      RecentAudioTrack(
        path: stablePath,
        displayName: displayName,
        durationMs: sourceDurationMs,
        pickedAt: DateTime.now(),
      ),
    );
    if (_recentAudioTracks.length > 12) {
      _recentAudioTracks.removeRange(12, _recentAudioTracks.length);
    }

    final clip = _timeline.addAudioClip(
      sourcePath: stablePath,
      sourceDurationMs: sourceDurationMs > 0 ? sourceDurationMs : 1000,
      timelineStartMs: 0,
      videoDurationMs: _timeline.videoDurationMs,
    );

    if (!_muteOriginalAudio) {
      setState(() => _muteOriginalAudio = true);
      _syncSession();
      _backend?.setEmbeddedAudioMuted(true);
    }

    if (mounted) {
      setState(() {
        _statusLine =
            'Music added · $displayName (${_formatDuration(sourceDurationMs)})';
      });
      debugPrint('[MusicPicker] ready path=$stablePath muteOriginal=$_muteOriginalAudio');
    }

    final normFuture = ingested.normalizedPathFuture;
    if (normFuture != null) {
      final clipId = clip.id;
      _pendingNormalizationCount++;
      final tracked = normFuture.then((aacPath) => aacPath);
      _normalizationFutures[clipId] = tracked;
      tracked.then((aacPath) {
        _normalizationFutures.remove(clipId);
        if (!mounted) return;
        AudioTimelineClip? currentClip;
        for (final c in _timeline.audioClips) {
          if (c.id == clipId) {
            currentClip = c;
            break;
          }
        }
        if (currentClip != null) {
          _timeline.updateAudioClip(currentClip.copyWith(sourcePath: aacPath));
        }
        debugPrint('[MediaIngest] Audio normalized to AAC: $aacPath');
      }).catchError((e) {
        _normalizationFutures.remove(clipId);
        debugPrint('[MediaIngest] Background AAC normalization failed: $e');
      }).whenComplete(() {
        _pendingNormalizationCount = (_pendingNormalizationCount - 1).clamp(0, 999);
      });
    }
  }

  void _onNavToolChanged(EditorNavTool tool) {
    debugPrint('[LuminaChrome] nav=$tool');
    setState(() => _activeNavTool = tool);
    switch (tool) {
      case EditorNavTool.media:
        break;
      case EditorNavTool.text:
        if (_selectedTextOverlay == null) {
          _addTextOverlay();
        }
      case EditorNavTool.sticker:
        break;
      case EditorNavTool.music:
        _showMusicPicker();
      case EditorNavTool.effects:
        _ensureEffectsClipSelected();
        break;
    }
  }

  void _showSoundSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: LuminaTokens.surfaceContainer,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setBottomSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(LuminaTokens.space4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Sound',
                  style: TextStyle(
                    color: LuminaTokens.onSurface,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Mute original video audio',
                    style: TextStyle(color: LuminaTokens.onSurface),
                  ),
                  value: _muteOriginalAudio,
                  activeThumbColor: LuminaTokens.accent,
                  onChanged: (v) {
                    setState(() => _muteOriginalAudio = v);
                    _syncSession();
                    _backend?.setEmbeddedAudioMuted(v);
                    setBottomSheetState(() {});
                  },
                ),
                if (_primaryAudioClip != null) ...[
                  const SizedBox(height: LuminaTokens.space2),
                  Row(
                    children: [
                      const Text(
                        'Music volume',
                        style: TextStyle(color: LuminaTokens.onSurfaceVariant),
                      ),
                      Expanded(
                        child: Slider(
                          value: _primaryAudioClip!.volume,
                          activeColor: LuminaTokens.accent,
                          onChanged: (v) {
                            _timeline.updateAudioClip(
                              _primaryAudioClip!.copyWith(volume: v),
                            );
                            setState(() {});
                            setBottomSheetState(() {});
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showMoreSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: LuminaTokens.surfaceContainer,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.content_cut),
              title: const Text('Split at playhead'),
              onTap: () {
                Navigator.pop(ctx);
                _splitAtPlayhead();
              },
            ),
            ListTile(
              leading: Icon(
                Icons.analytics_outlined,
                color: _showDiagnostics ? LuminaTokens.accent : null,
              ),
              title: const Text('Diagnostics'),
              onTap: () {
                setState(() => _showDiagnostics = !_showDiagnostics);
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Clear overlays'),
              onTap: () {
                for (final o in List<VideoOverlayItem>.from(_timeline.overlays)) {
                  _timeline.removeOverlay(o.id);
                }
                Navigator.pop(ctx);
                setState(() {});
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Re-open the Rust backend on a different file. Used to fall back to the
  /// original file after preview muxing, etc. — currently a no-op because the
  /// Rust backend always plays the source file with real-time overlay mixing.
  Future<void> _reopenSourceFileIfNeeded() async {
    final backend = _backend;
    if (backend is! RustPlaybackBackend) return;
    // If a previous session left the engine on a muxed path, point it back
    // at the source file. Safe to call repeatedly; reopenFile is a no-op if
    // the path matches.
    debugPrint('[RustPlayback] reopenSourceFileIfNeeded path=${widget.initialPath}');
  }

  void _splitAtPlayhead() {
    final ok = _timeline.splitVideoAt(_playheadTimelineMs);
    _activeSpeedClipId = null;
    if (ok) {
      _syncPlaybackSpeedToActiveClip(force: true);
    }
    setState(() {
      _statusLine = ok
          ? 'Split clip at ${_formatDuration(_playheadTimelineMs)}'
          : 'Cannot split here (move playhead inside a clip)';
    });
  }

  void _onRangeChanged(double start, double end) {
    final dur = _activeDurationMs / 1000.0;
    final gap = dur > 0 ? (dur * 0.05).clamp(0.01, 0.25) : 0.01;
    var s = start.clamp(0.0, dur);
    var e = end.clamp(0.0, dur);
    if (e < s + gap) {
      e = (s + gap).clamp(0.0, dur);
      if (e - gap < s) s = (e - gap).clamp(0.0, dur);
    }
    setState(() {
      _startSec = s;
      _endSec = e;
      _playheadSec = _safeClamp(_playheadSec, s, e);
    });
    _syncFilmstripToSingleClip();
    _backend?.setTrimRange(
      startMs: (_startSec * 1000).round(),
      endMs: (_endSec * 1000).round(),
    );
    _timeline.clampAudioClipsToVideo();
    _schedulePreviewSync(_playheadSec);
  }

  List<AudioTrackInput> _exportAudioTracks() {
    return _timeline.audioClips
        .where((c) => !c.muted)
        .map(
          (c) => AudioTrackInput(
            sourcePath: c.sourcePath,
            sourceStartMs: BigInt.from(c.sourceStartMs),
            durationMs: BigInt.from(c.durationMs),
            timelineStartMs: BigInt.from(c.timelineStartMs),
            volume: c.volume,
            muted: c.muted,
          ),
        )
        .toList();
  }

  void _schedulePreviewSync(double timelineSeconds) {
    if (_backend?.isPlaying ?? false) return;
    unawaited(_applySeekFromTimelineMs((timelineSeconds * 1000).round()));
  }

  Future<void> _togglePlayback() async {
    final backend = _backend;
    if (backend == null || !backend.isOpen || _busy) return;

    if (backend.isPlaying) {
      backend.pause();
      if (mounted) setState(() {});
      return;
    }

    setState(() => _busy = true);
    try {
      await _reopenSourceFileIfNeeded();
      if (_hasSelectedVideoClip) {
        await _ensurePlayheadInSelectedClip();
      }
      await _applySeekFromTimelineMs(_playheadTimelineMs);
      await backend.play();
      final tracks = _exportAudioTracks();
      if (mounted) {
        setState(() => _statusLine = tracks.isEmpty
            ? 'Playing (Rust)'
            : 'Playing with ${tracks.length} overlay track(s) (Rust)');
      }
    } catch (e) {
      debugPrint('[RustPlayback] playback start failed: $e');
      if (mounted) {
        setState(() => _statusLine = 'Playback failed: $e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addTextOverlay() async {
    final isMobile =
        MediaQuery.sizeOf(context).width < LuminaTokens.breakpointTablet;
    VideoTextOverlaySpec? spec;

    if (isMobile) {
      spec = await showDialog<VideoTextOverlaySpec>(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black26,
        builder: (ctx) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.zero,
          child: InlineTextEditorOverlay(
            initialSpec: VideoTextOverlaySpec(
              label: '',
              style: styleForLookPreset(VideoTextLookPreset.modern),
            ),
            onDone: (s) => Navigator.pop(ctx, s),
            onCancel: () => Navigator.pop(ctx),
          ),
        ),
      );
    } else {
      spec = await VideoTextOverlayEditSheet.show(
        context,
        initialSpec: const VideoTextOverlaySpec(label: ''),
        title: 'Add text overlay',
      );
    }

    if (spec == null || !mounted) return;

    final duration = _timeline.durationMs;
    final startMs = _playheadTimelineMs;
    final endMs = (startMs + 5000).clamp(0, duration);
    final overlay = VideoOverlayItem.text(
      id: 'text:${spec.label}:${DateTime.now().millisecondsSinceEpoch}',
      startMs: startMs,
      endMs: endMs,
      anchor: const Offset(0.3, 0.4),
      label: spec.label,
      style: spec.style,
      fadeInMs: 280,
    );
    _timeline.addOverlay(overlay);
    _timeline.selectOverlay(overlay.id);
    setState(() {});
  }

  void _updateTextOverlay(String id, VideoTextOverlaySpec spec, {int? replayToken}) {
    final i = _timeline.overlays.indexWhere((o) => o.id == id);
    if (i < 0) return;
    final token = replayToken ?? ((_textReplayTokens[id] ?? 0) + 1);
    _textReplayTokens[id] = token;
    _timeline.updateOverlay(
      _timeline.overlays[i].withTextSpec(spec, replayToken: token),
    );
  }

  void _cycleTextStyleOnTap(VideoOverlayItem overlay) {
    final spec = overlay.resolvedTextSpec;
    if (spec == null) return;
    final nextColor = nextAccentColor(spec.style.color);
    final next = spec.copyWith(
      style: styleForLookPreset(
        nextLookPreset(spec.style.lookPreset),
        base: spec.style,
        accent: nextColor,
      ).copyWith(color: nextColor),
    );
    _updateTextOverlay(overlay.id, next);
    setState(() {});
    debugPrint('[TextOverlay] cycle preset=${next.style.lookPreset}');
  }

  void _applyTextStyle(VideoOverlayItem overlay, VideoTextOverlayStyle style) {
    final spec = overlay.resolvedTextSpec;
    if (spec == null) return;
    _updateTextOverlay(overlay.id, spec.copyWith(style: style));
    _textReplayTokens[overlay.id] = (_textReplayTokens[overlay.id] ?? 0) + 1;
    setState(() {});
  }

  void _applyTextAnimation(
    VideoOverlayItem overlay,
    VideoTextAnimation animation,
  ) {
    final spec = overlay.resolvedTextSpec;
    if (spec == null) return;
    _updateTextOverlay(
      overlay.id,
      spec.copyWith(style: spec.style.copyWith(animation: animation)),
    );
    _textReplayTokens[overlay.id] = (_textReplayTokens[overlay.id] ?? 0) + 1;
    setState(() {});
  }

  void _applyTextPreset(VideoOverlayItem overlay, VideoTextLookPreset preset) {
    final spec = overlay.resolvedTextSpec;
    if (spec == null) return;
    final next = spec.copyWith(style: styleForLookPreset(preset, base: spec.style));
    _updateTextOverlay(overlay.id, next);
    _textReplayTokens[overlay.id] = (_textReplayTokens[overlay.id] ?? 0) + 1;
    setState(() {});
  }

  void _toggleTextBackground(VideoOverlayItem overlay) {
    final spec = overlay.resolvedTextSpec;
    if (spec == null) return;
    final style = spec.style;
    final nextShow = !style.showBackground;
    final next = spec.copyWith(
      style: style.copyWith(
        showBackground: nextShow,
        backgroundStyle: nextShow
            ? VideoTextBackgroundStyle.rounded
            : VideoTextBackgroundStyle.none,
      ),
    );
    _updateTextOverlay(overlay.id, next);
    setState(() {});
  }

  Future<void> _openTextEditorForOverlay(VideoOverlayItem overlay) async {
    final spec = overlay.resolvedTextSpec;
    if (spec == null) return;
    final updated = await showDialog<VideoTextOverlaySpec>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black26,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: InlineTextEditorOverlay(
          initialSpec: spec,
          onDone: (s) => Navigator.pop(ctx, s),
          onCancel: () => Navigator.pop(ctx),
        ),
      ),
    );
    if (updated == null || !mounted) return;
    _updateTextOverlay(overlay.id, updated);
    setState(() {});
  }

  void _deleteOverlay(String id) {
    _timeline.removeOverlay(id);
    _textReplayTokens.remove(id);
    _clearSelections();
    setState(() {
      _statusLine = 'Overlay deleted';
    });
    debugPrint('[TextOverlay] deleted id=$id');
  }

  int _replayTokenFor(String id) => _textReplayTokens[id] ?? 0;

  VideoOverlayItem? _selectedOverlay() {
    final id = _timeline.selectedOverlayId;
    if (id == null) return null;
    for (final o in _timeline.overlays) {
      if (o.id == id) return o;
    }
    return null;
  }

  void _addEmojiOverlay() {
    StickerPickerSheet.show(
      context,
      onEmojiSelected: (emoji) {
        final duration = _timeline.durationMs;
        final startMs = _playheadTimelineMs;
        final endMs = (startMs + 5000).clamp(0, duration);

        final overlay = VideoOverlayItem.emoji(
          id: 'emoji:$emoji:${DateTime.now().millisecondsSinceEpoch}',
          startMs: startMs,
          endMs: endMs,
          anchor: const Offset(0.7, 0.2),
          emoji: emoji,
        );

        _timeline.addOverlay(overlay);
        setState(() {});
      },
    );
  }

  void _clearOverlays() {
    _timeline.clearOverlays();
    setState(() => _statusLine = 'Cleared all overlays');
  }

  Future<void> _exportVideo() async {
    final isPlaying = _backend?.isPlaying ?? false;
    if (_busy) return;

    if (_hasPendingNormalization) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please wait — audio is still being prepared for export.'),
        ),
      );
      return;
    }

    if (isPlaying) {
      _backend?.pause();
    }

    setState(() {
      _busy = true;
      _statusLine = _timeline.overlays.isEmpty
          ? 'Preparing export…'
          : 'Baking overlays for export…';
    });

    final segmentedExport =
        TimelineExportService.needsSegmentedExport(_timeline.videoClips);
    final exportInfo = _activeMediaInfo ??
        await VideoProcessor.getMediaInfo(widget.initialPath);

    List<BurnInOverlay> burnInOverlays = const [];
    try {
      if (!segmentedExport && _timeline.overlays.isNotEmpty) {
        burnInOverlays = await OverlayRasterExporter.rasterizeForExport(
          overlays: _timeline.overlays,
          sourceWidth: exportInfo.width,
          sourceHeight: exportInfo.height,
          preset: _exportPreset,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _statusLine = 'Overlay bake failed: $e';
        });
      }
      return;
    }

    if (!mounted) return;

    final outputs = await EditorOutputPaths.resolve();
    final outPath = p.join(
      outputs.compressVideoDir,
      '${outputs.safeStem(widget.initialPath)}_${_exportPreset.name}_export.mp4',
    );
    await Directory(outputs.compressVideoDir).create(recursive: true);

    final (startMs, endMs) = _exportTrimMs();

    setState(() {
      _busy = false;
      _statusLine = 'Encoding video…';
    });

    double exportProgress = 0;
    String exportStatus = 'Preparing job…';
    String? exportErrorDetail;
    VideoJob? activeJob;
    bool exportCancelled = false;
    var muteOriginalAudio = _muteOriginalAudio;
    var exportStarted = false;
    final exportAudioTracks = _exportAudioTracks();
    if (exportAudioTracks.isEmpty) {
      exportStarted = true;
    }

    if (!mounted) return;

    showModalBottomSheet<VideoExportResult?>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1C1C1E),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setBottomSheetState) {
            void setExportFailure(Object e) {
              setBottomSheetState(() {
                exportErrorDetail = e.toString();
                exportStatus = 'Export failed';
              });
            }

            if (activeJob == null && !exportCancelled && exportStarted) {
              final sw = Stopwatch()..start();
              final exportClipEffects = _exportClipEffects;
              if (segmentedExport) {
                debugPrint(
                  '[VideoExport] segmented clips=${_timeline.videoClips.length}',
                );
              } else if (exportClipEffects != null) {
                debugPrint(
                  '[VideoExport] clip_effects speed=${exportClipEffects.speed} '
                  'motion_tracks=${exportClipEffects.motion.tracks.length}',
                );
              }

              final Future<VideoJob> jobFuture = segmentedExport
                  ? TimelineExportService.compressTimeline(
                      clips: _timeline.videoClips,
                      outputPath: outPath,
                      quality: _exportPreset.quality,
                      preset: _exportPreset,
                      preferHardwareEncoder: _preferHw,
                      overlays: _timeline.overlays,
                      sourceWidth: exportInfo.width,
                      sourceHeight: exportInfo.height,
                      audioTracks: exportAudioTracks,
                      muteOriginalAudio: muteOriginalAudio,
                    )
                  : VideoProcessor.compressJob(
                      input: widget.initialPath,
                      output: outPath,
                      quality: _exportPreset.quality,
                      preferHardwareEncoder: burnInOverlays.isEmpty &&
                          exportClipEffects == null &&
                          _preferHw,
                      startMs: startMs,
                      endMs: endMs > startMs ? endMs : null,
                      burnInOverlays: burnInOverlays,
                      audioTracks: exportAudioTracks,
                      muteOriginalAudio: muteOriginalAudio,
                      clipEffects: exportClipEffects,
                    );

              jobFuture.then((job) {
                activeJob = job;
                _progressSub = job.progress.listen((event) {
                  setBottomSheetState(() {
                    exportProgress = event.percent;
                    exportStatus = '${_phaseLabel(event.phase)} ${(event.percent * 100).toStringAsFixed(0)}%';
                  });
                }, onError: setExportFailure);

                job.result.then((result) async {
                  final duration = sw.elapsed;
                  final outBytes = await File(result.outputPath).length();
                  final originalBytes = await File(widget.initialPath).length();
                  
                  // Extract a thumbnail from the compressed output
                  String? thumbPath;
                  try {
                    thumbPath = await VideoProcessor.thumbnailPathCached(
                      input: result.outputPath,
                      position: Duration(milliseconds: startMs),
                      width: 200,
                    );
                  } catch (_) {}

                  final exportResult = VideoExportResult(
                    outputPath: result.outputPath,
                    thumbPath: thumbPath,
                    originalBytes: originalBytes,
                    compressedBytes: outBytes,
                    encodeDuration: duration,
                  );

                  if (context.mounted) {
                    Navigator.pop(context, exportResult);
                  }
                }).catchError((Object e) {
                  if (!exportCancelled) {
                    setExportFailure(e);
                  }
                });
              }, onError: setExportFailure);
            }

            final maxSheetHeight = MediaQuery.sizeOf(context).height * 0.55;

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxSheetHeight),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Exporting Video',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (burnInOverlays.isNotEmpty) ...[
                          Text(
                            'Burning in ${burnInOverlays.length} overlay(s) with trim and compression.',
                            style: const TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                          const Text(
                            'Overlay export uses CPU burn-in then encode (libx264 on desktop, '
                            'or MediaCodec on Android when software encoders are unavailable). '
                            'HW Encode toggle is ignored.',
                            style: TextStyle(color: Colors.white38, fontSize: 11),
                          ),
                        ],
                        if (!exportStarted && exportAudioTracks.isNotEmpty) ...[
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              'Mute original video audio',
                              style: TextStyle(color: Colors.white70, fontSize: 13),
                            ),
                            subtitle: const Text(
                              'Off: mix background track with the video’s audio',
                              style: TextStyle(color: Colors.white38, fontSize: 11),
                            ),
                            value: muteOriginalAudio,
                            onChanged: (v) {
                              setBottomSheetState(() => muteOriginalAudio = v);
                              setState(() {
                                _muteOriginalAudio = v;
                              });
                              _syncSession();
                              _backend?.setEmbeddedAudioMuted(v);
                            },
                          ),
                          FilledButton(
                            onPressed: () {
                              setBottomSheetState(() => exportStarted = true);
                            },
                            child: Text(
                              'Export with ${exportAudioTracks.length} audio track(s)',
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        const SizedBox(height: 16),
                        LinearProgressIndicator(value: exportStarted ? exportProgress : 0),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                exportStatus,
                                style: TextStyle(
                                  color: exportErrorDetail != null
                                      ? Colors.redAccent
                                      : Colors.white70,
                                  fontSize: 13,
                                  fontWeight: exportErrorDetail != null
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                            Text(
                              '${(exportProgress * 100).toStringAsFixed(0)}%',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        if (exportErrorDetail != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _shortExportError(exportErrorDetail!),
                            style: const TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                          if (_overlayExportHint(exportErrorDetail!) != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              _overlayExportHint(exportErrorDetail!)!,
                              style: const TextStyle(
                                color: Colors.amberAccent,
                                fontSize: 11,
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 120),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: const Color(0xFF2A2A2A),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.all(8),
                                child: SelectableText(
                                  exportErrorDetail!,
                                  style: const TextStyle(
                                    color: Colors.white60,
                                    fontSize: 10,
                                    fontFamily: 'monospace',
                                    height: 1.3,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        OutlinedButton(
                          onPressed: () async {
                            exportCancelled = true;
                            if (activeJob != null) {
                              await activeJob!.cancel();
                            }
                            await _progressSub?.cancel();
                            if (context.mounted) {
                              Navigator.pop(context, null);
                            }
                          },
                          child: Text(
                            exportErrorDetail != null ? 'Close' : 'Cancel Export',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    ).then((exportResult) {
      if (exportResult != null) {
        _showExportSuccessDialog(exportResult, overlayCount: burnInOverlays.length);
      }
    });
  }

  void _handleExportComplete(VideoExportResult result) {
    debugPrint(
      '[VideoExport] success path=${result.outputPath} '
      'bytes=${result.compressedBytes} dur=${result.encodeDuration.inMilliseconds}ms',
    );
    final onExport = widget.config.onExport;
    if (onExport != null) {
      onExport(result);
      return;
    }
  }

  void _showExportSuccessDialog(VideoExportResult result, {int overlayCount = 0}) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final originalMB = result.originalBytes / (1024 * 1024);
        final compressedMB = result.compressedBytes / (1024 * 1024);
        final savedPercent = (100 - (result.compressedBytes / result.originalBytes * 100)).clamp(0.0, 99.0);

        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: const Text('Export Complete', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                overlayCount == 0
                    ? 'Trim and compression are saved.'
                    : 'Trim, compression, and $overlayCount overlay(s) are saved.',
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              _StatLine(label: 'Output Path', value: p.basename(result.outputPath)),
              _StatLine(label: 'Original Size', value: '${originalMB.toStringAsFixed(1)} MB'),
              _StatLine(label: 'Compressed Size', value: '${compressedMB.toStringAsFixed(1)} MB (~${savedPercent.toStringAsFixed(0)}% smaller)'),
              _StatLine(label: 'Encode Time', value: '${(result.encodeDuration.inMilliseconds / 1000).toStringAsFixed(1)}s'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                _handleExportComplete(result);
              },
              child: const Text('Done'),
            ),
          ],
        );
      },
    );
  }

  String _phaseLabel(ProcessingPhase phase) {
    return switch (phase) {
      ProcessingPhase.probing => 'Probing',
ProcessingPhase.decoding => 'Decoding',
      ProcessingPhase.encoding => 'Encoding',
      ProcessingPhase.muxing => 'Muxing',
      ProcessingPhase.thumbnail => 'Thumbnailing',
      ProcessingPhase.done => 'Done',
      ProcessingPhase.cancelled => 'Cancelled',
      ProcessingPhase.failed => 'Failed',
    };
  }

  Widget? _buildMobileToolPanel() {
    if (_selectedTextOverlay != null) return null;
    switch (_activeNavTool) {
      case EditorNavTool.sticker:
        return LuminaStickerPanel(onEmojiSelected: _addEmojiFromPicker);
      case EditorNavTool.effects:
        final clip = _effectsTargetClip;
        if (clip == null) {
          return _buildSelectClipForEffectsHint();
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildClipEffectsEditor(clip),
            ListTile(
              leading: const Icon(Icons.analytics_outlined),
              title: const Text('Diagnostics'),
              onTap: () => setState(() => _showDiagnostics = !_showDiagnostics),
            ),
          ],
        );
      case EditorNavTool.media:
      case EditorNavTool.text:
      case EditorNavTool.music:
        return null;
    }
  }

  void _addEmojiFromPicker(String emoji) {
    final duration = _timeline.durationMs;
    final startMs = _playheadTimelineMs;
    final endMs = (startMs + 5000).clamp(0, duration);

    final overlay = VideoOverlayItem.emoji(
      id: 'emoji:$emoji:${DateTime.now().millisecondsSinceEpoch}',
      startMs: startMs,
      endMs: endMs,
      anchor: const Offset(0.5, 0.45),
      emoji: emoji,
    );

    _timeline.addOverlay(overlay);
    _timeline.selectOverlay(overlay.id);
    setState(() {});
    debugPrint('[StickerPanel] overlay added emoji=$emoji');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLoaded = _backend != null && _backend!.isOpen;

    final mainContent = LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= LuminaTokens.breakpointTablet;
        if (isWide) {
          return DesktopTimelineLayout(
            inspectorWidth: _inspectorWidth,
            onInspectorResize: (w) => setState(() => _inspectorWidth = w),
            leftPanel: _buildLeftPanel(context, theme, isLoaded, isWide, fullBleed: false),
            inspectorPanel: _buildInspectorPanel(theme, isWide),
          );
        }
        return MobileStoriesLayout(
          isLoaded: isLoaded,
          title: widget.displayName,
          preview: _buildPreviewCanvas(fullBleed: true),
          scrubberRow: _buildSpatiallyStableScrubberRow(theme),
          timelineSection: _buildTimelinePanel(theme, isLoaded),
          onClose: () {
            unawaited(_cancelAndClose());
          },
          onExport: _exportVideo,
          activeNavTool: _activeNavTool,
          onNavToolChanged: _onNavToolChanged,
          toolPanel: _buildMobileToolPanel(),
          onSplit: _splitAtPlayhead,
          onDelete: _timeline.selectedVideoClipId != null ||
                  _timeline.selectedOverlayId != null ||
                  _timeline.selectedAudioClipId != null
              ? () {
                  final vid = _timeline.selectedVideoClipId;
                  final oid = _timeline.selectedOverlayId;
                  final aid = _timeline.selectedAudioClipId;
                  if (vid != null) _timeline.deleteVideoClip(vid);
                  if (oid != null) _deleteOverlay(oid);
                  if (aid != null) _timeline.removeAudioClip(aid);
                  setState(() {});
                }
              : null,
          onSpeed: () => _onNavToolChanged(EditorNavTool.effects),
          canSplit: isLoaded && _timeline.videoClips.isNotEmpty,
          canDelete: _timeline.selectedVideoClipId != null ||
              _timeline.selectedOverlayId != null ||
              _timeline.selectedAudioClipId != null,
          hasMusic: _primaryAudioClip != null,
          compactPreview: _selectedTextOverlay != null ||
              _activeNavTool == EditorNavTool.sticker,
          overlayTracksBar: OverlayTimingTracksBar(
            overlays: _timeline.overlays,
            audioClips: _timeline.audioClips,
            videoDurationMs: _timeline.durationMs,
            selectedOverlayId: _timeline.selectedOverlayId,
            selectedAudioId: _timeline.selectedAudioClipId,
            onSelectOverlay: (id) {
              _timeline.selectOverlay(id);
              if (id != null) {
                _timeline.selectVideoClip(null);
                _timeline.selectAudioClip(null);
              }
              setState(() {});
            },
            onSelectAudio: (id) {
              _timeline.selectAudioClip(id);
              if (id != null) _timeline.selectOverlay(null);
              setState(() {});
            },
          ),
          textEditChrome: _selectedTextOverlay == null
              ? null
              : TextOverlayEditChrome(
                  overlay: _selectedTextOverlay!,
                  videoDurationMs: _timeline.durationMs,
                  replayToken: _replayTokenFor(_selectedTextOverlay!.id),
                  onPresetSelected: (p) =>
                      _applyTextPreset(_selectedTextOverlay!, p),
                  onStyleChanged: (s) =>
                      _applyTextStyle(_selectedTextOverlay!, s),
                  onAnimationSelected: (a) =>
                      _applyTextAnimation(_selectedTextOverlay!, a),
                  onToggleBackground: () =>
                      _toggleTextBackground(_selectedTextOverlay!),
                  onTimingChanged: (start, end) {
                    _timeline.updateOverlay(
                      _selectedTextOverlay!.copyWith(
                        startMs: start,
                        endMs: end,
                      ),
                    );
                    setState(() {});
                  },
                  onDone: () {
                    setState(() => _activeNavTool = EditorNavTool.media);
                    _clearSelections();
                  },
                ),
        );
      },
    );

    final isWideLayout =
        MediaQuery.sizeOf(context).width >= LuminaTokens.breakpointTablet;

    return Focus(
      autofocus: true,
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.space): () {
            final primaryFocus = FocusManager.instance.primaryFocus;
            final isEditing = primaryFocus != null &&
                primaryFocus.hasFocus &&
                (primaryFocus.context?.widget is EditableText ||
                 primaryFocus.context?.findAncestorWidgetOfExactType<EditableText>() != null);
            if (!isEditing) {
              _togglePlayback();
            }
          },
          const SingleActivator(LogicalKeyboardKey.escape): () {
            _clearSelections();
          },
          const SingleActivator(LogicalKeyboardKey.keyK, control: true): () {
            _showCommandPalette();
          },
          const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () {
            _showCommandPalette();
          },
        },
        child: Scaffold(
          backgroundColor: LuminaTokens.canvas,
          appBar: isWideLayout
              ? AppBar(
                  backgroundColor: LuminaTokens.surfaceContainerLow,
                  elevation: 0,
                  title: Text(
                    widget.displayName ?? 'Video Creator',
                    style: const TextStyle(
                      color: LuminaTokens.onSurface,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back, color: LuminaTokens.onSurface, size: 20),
                    onPressed: () {
                      unawaited(_cancelAndClose());
                    },
                  ),
                  actions: [
                    if (isLoaded) ...[
                      Container(
                        margin: const EdgeInsets.symmetric(vertical: 10),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: LuminaTokens.accent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.memory, size: 14, color: LuminaTokens.accent),
                            SizedBox(width: 6),
                            Text(
                              'Rust',
                              style: TextStyle(
                                color: LuminaTokens.accent,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: Icon(
                          Icons.analytics_outlined,
                          color: _showDiagnostics ? LuminaTokens.accent : LuminaTokens.onSurfaceMuted,
                          size: 20,
                        ),
                        onPressed: () {
                          setState(() => _showDiagnostics = !_showDiagnostics);
                        },
                        tooltip: 'Diagnostics',
                      ),
                      const SizedBox(width: 4),
                      Padding(
                        padding: const EdgeInsets.only(right: 12, top: 10, bottom: 10),
                        child: FilledButton.icon(
                          onPressed: _exportVideo,
                          style: FilledButton.styleFrom(
                            backgroundColor: theme.colorScheme.primary,
                            foregroundColor: LuminaTokens.onAccent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                          ),
                          icon: const Icon(Icons.save_alt, size: 16),
                          label: const Text(
                            'Export',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ],
                )
              : null,
          body: SafeArea(
            top: !isWideLayout,
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: mainContent),
                if (isWideLayout) _buildStatusLine(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLeftPanel(
    BuildContext context,
    ThemeData theme,
    bool isLoaded,
    bool isWide, {
    required bool fullBleed,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _buildPreviewCanvas(fullBleed: fullBleed)),
        if (isLoaded && _showDiagnostics && isWide)
          SizedBox(
            height: 140,
            child: DiagnosticsPanel(
              backend: _backend as RustPlaybackBackend,
            ),
          ),
        if (isLoaded && _backend is RustPlaybackBackend && isWide)
          AudioWaveformVisualizer(
            backend: _backend as RustPlaybackBackend,
            height: 36,
          ),
        if (isWide) _buildSpatiallyStableScrubberRow(theme),
        if (isWide) _buildTimelineSection(theme, isLoaded, isWide),
      ],
    );
  }

  Widget _buildPreviewCanvas({required bool fullBleed}) {
    final isLoaded = _backend != null && _backend!.isOpen;
    final info = _activeMediaInfo;
    final aspect = info != null && info.width > 0 && info.height > 0
        ? info.width / info.height
        : 16 / 9;

    return Container(
      color: LuminaTokens.canvas,
      padding: fullBleed ? EdgeInsets.zero : const EdgeInsets.all(24),
      child: Center(
        child: fullBleed
            ? _buildPreviewStack(aspect, isLoaded)
            : ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  color: Colors.black,
                  child: _buildPreviewStack(aspect, isLoaded),
                ),
              ),
      ),
    );
  }

  Widget _buildPreviewStack(double aspect, bool isLoaded) {
    if (!isLoaded) {
      return const AspectRatio(
        aspectRatio: 9 / 16,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return AspectRatio(
      aspectRatio: aspect,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ListenableBuilder(
            listenable: _timeline,
            builder: (context, _) {
              return ValueListenableBuilder<ClipEffectsPreview?>(
                valueListenable: _clipEffectsSession.preview,
                builder: (context, _, __) {
                  return ValueListenableBuilder<double>(
                    valueListenable: _playheadNotifier,
                    builder: (context, playheadSec, _) {
                      final rustBackend = _backend as RustPlaybackBackend?;
                      if (rustBackend == null) {
                        return const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        );
                      }
                      final timelineMs = (playheadSec * 1000).round();
                      final previewClip =
                          _timeline.clipAtTimelineMs(timelineMs);
                      final previewEffects = previewClip != null
                          ? _clipEffectsSession.effectsForClip(previewClip)
                          : null;
                      final showEffects = previewEffects != null &&
                          !ClipEffectsKit.isIdentity(previewEffects);
                      final targetClip = _effectsTargetClip;
                      final gestureEnabled = targetClip != null &&
                          _selectedTextOverlay == null &&
                          _timeline.selectedOverlayId == null;
                      Widget canvas = RustVideoCanvas(
                        key: ValueKey(_previewSessionId),
                        backend: rustBackend,
                        overlays: _timeline.overlays,
                        timelinePlayheadMs: timelineMs,
                        clipEffects: showEffects ? previewEffects : null,
                        clipLocalMs: previewClip != null
                            ? ClipEffectsKit.localTimelineMs(
                                previewClip,
                                timelineMs,
                              )
                            : 0,
                        selectedOverlayId: _timeline.selectedOverlayId,
                        onSelectOverlay: (id) {
                          _timeline.selectOverlay(id);
                          if (id != null) {
                            _timeline.selectVideoClip(null);
                            _timeline.selectAudioClip(null);
                          }
                          setState(() {});
                        },
                        onOverlayChanged: (item) {
                          _timeline.updateOverlay(item);
                          setState(() {});
                        },
                        onTapTextOverlay: _cycleTextStyleOnTap,
                        onDoubleTapTextOverlay: _openTextEditorForOverlay,
                        onDeleteOverlay: _deleteOverlay,
                        showDeleteZone: _selectedTextOverlay != null,
                        showDiagnostics: _showDiagnostics,
                      );
                      if (gestureEnabled) {
                        final gestureEffects =
                            _clipEffectsSession.effectsForClip(targetClip);
                        canvas = ClipTransformGestureLayer(
                          effects: gestureEffects,
                          enabled: true,
                          onPreview: (fx) =>
                              _previewClipEffects(fx, clipId: targetClip.id),
                          onCommit: (fx) => _applyClipEffectsCommit(
                            fx,
                            clipId: targetClip.id,
                          ),
                          child: canvas,
                        );
                      }
                      return canvas;
                    },
                  );
                },
              );
            },
          ),
          Positioned.fill(
            child: ListenableBuilder(
              listenable: _backend ?? _dummyNotifier,
              builder: (context, _) {
                final playing = _backend?.isPlaying ?? false;
                if (playing) return const SizedBox.shrink();
                return Center(
                  child: GestureDetector(
                    onTap: _togglePlayback,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.play_arrow,
                        size: 48,
                        color: Colors.white,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (_metricsLine.isNotEmpty)
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _metricsLine,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTimelinePanel(ThemeData theme, bool isLoaded) {
    return _buildTimelineSection(theme, isLoaded, false);
  }

  double _snapPlayhead(double value) {
    final thresholdMs = 200; // 200ms snapping threshold
    final valMs = (value * 1000).round();
    
    // Snapping points: video trim starts/ends, split boundaries, overlays, audio track boundaries.
    final List<int> snapPoints = [0];
    
    for (final clip in _timeline.videoClips) {
      snapPoints.add(clip.timelineStartMs);
      snapPoints.add(clip.timelineStartMs + clip.durationMs);
    }
    for (final audio in _timeline.audioClips) {
      snapPoints.add(audio.timelineStartMs);
      snapPoints.add(audio.timelineStartMs + audio.durationMs);
    }
    for (final overlay in _timeline.overlays) {
      snapPoints.add(overlay.startMs);
      snapPoints.add(overlay.endMs);
    }
    
    int closest = valMs;
    int minDiff = thresholdMs + 1;
    
    for (final p in snapPoints) {
      final diff = (p - valMs).abs();
      if (diff < minDiff) {
        minDiff = diff;
        closest = p;
      }
    }
    
    if (minDiff <= thresholdMs) {
      return closest / 1000.0;
    }
    return value;
  }

  Widget _buildSpatiallyStableScrubberRow(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: LuminaTokens.surfaceContainerLow,
        border: Border(
          top: BorderSide(color: LuminaTokens.outlineVariant.withValues(alpha: 0.5)),
          bottom: BorderSide(color: LuminaTokens.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        children: [
          // Play/Pause button
          ListenableBuilder(
            listenable: _backend ?? _dummyNotifier,
            builder: (context, _) {
              final playing = _backend?.isPlaying ?? false;
              return InkWell(
                onTap: _togglePlayback,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    playing ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 8),
          // Loop toggle
          InkWell(
            onTap: () async {
              setState(() => _isLooping = !_isLooping);
              await _backend?.setLooping(_isLooping);
              debugPrint('[EditorChrome] loop toggled=$_isLooping');
            },
            borderRadius: BorderRadius.circular(20),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: _isLooping
                    ? LuminaTokens.accent.withValues(alpha: 0.15)
                    : Colors.transparent,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.repeat,
                color: _isLooping ? LuminaTokens.accent : Colors.white38,
                size: 18,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Playhead timestamp
          ValueListenableBuilder<double>(
            valueListenable: _playheadNotifier,
            builder: (context, val, _) {
              final ms = (val * 1000).round();
              return Text(
                _formatDuration(ms),
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w600,
                ),
              );
            },
          ),
          const SizedBox(width: 8),
          // Scrubber Slider
          Expanded(
            child: ValueListenableBuilder<double>(
              valueListenable: _playheadNotifier,
              builder: (context, val, _) {
                return SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                    activeTrackColor: theme.colorScheme.primary,
                    inactiveTrackColor: Colors.white12,
                    thumbColor: Colors.white,
                  ),
                  child: Slider(
                    value: _safeClamp(val, 0, _timelineDurationSec),
                    min: 0,
                    max: _timelineDurationSec > 0 ? _timelineDurationSec : 0.01,
                    onChangeStart: (v) {
                      _backend?.pause();
                    },
                    onChanged: (v) {
                      final snapped = _snapPlayhead(v);
                      _playheadSec = snapped;
                      _playheadNotifier.value = snapped;
                      _schedulePreviewSync(snapped);
                    },
                    onChangeEnd: (v) {
                      final snapped = _snapPlayhead(v);
                      _playheadSec = snapped;
                      _playheadNotifier.value = snapped;
                      _backend?.play();
                    },
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          // Total duration timestamp
          Text(
            _formatDuration(_timeline.durationMs),
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 12,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineSection(ThemeData theme, bool isLoaded, bool isWide) {
    final timelinePanel = Container(
      color: const Color(0xFF0F0F10),
      child: isLoaded
          ? ListenableBuilder(
              listenable: _timeline,
              builder: (context, _) {
                return ModernTimeline(
                  controller: _timeline,
                  playheadMs: _playheadTimelineMs,
                  zoom: _timelineZoom,
                  onZoomChanged: (newZoom) {
                    setState(() {
                      _timelineZoom = newZoom;
                    });
                  },
                  onAddAudio: _pickAudioTrack,
                  onAddText: _addTextOverlay,
                  onAddEmoji: _addEmojiOverlay,
                  onSplitAtPlayhead: _splitAtPlayhead,
                  onSeek: (ms) {
                    _playheadSec = ms / 1000.0;
                    _playheadNotifier.value = _playheadSec;
                    _schedulePreviewSync(_playheadSec);
                  },
                );
              },
            )
          : const SizedBox.shrink(),
    );

    if (!isWide) {
      return timelinePanel;
    }

    return Column(
      children: [
        // Resize handle on Desktop
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onVerticalDragUpdate: (details) {
            setState(() {
              _timelineHeight = (_timelineHeight - details.delta.dy).clamp(150.0, 400.0);
            });
          },
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeUpDown,
            child: Container(
              height: 8,
              width: double.infinity,
              color: const Color(0xFF151517),
              child: Center(
                child: Container(
                  width: 32,
                  height: 3,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(1.5),
                  ),
                ),
              ),
            ),
          ),
        ),
        SizedBox(
          height: _timelineHeight,
          child: timelinePanel,
        ),
      ],
    );
  }

  Widget _buildInspectorPanel(ThemeData theme, bool isWide) {
    final hasOverlay = _timeline.selectedOverlayId != null;
    final hasAudio = _timeline.selectedAudioClipId != null;
    final hasVideo = _timeline.selectedVideoClipId != null;

    String title;
    Widget content;

    if (hasOverlay) {
      final selected = _selectedOverlay();
      final spec = selected?.resolvedTextSpec;
      
      final parts = selected?.id.split(':') ?? [];
      final type = parts.isNotEmpty ? parts[0] : '';
      title = type == 'emoji' ? 'Emoji Overlay' : 'Text Overlay';
      
      content = _buildOverlayInspector(selected, spec, theme);
    } else if (hasAudio) {
      final clips = _timeline.audioClips;
      final selected = clips.firstWhere(
        (c) => c.id == _timeline.selectedAudioClipId,
        orElse: () => clips.first,
      );
      title = 'Audio Track';
      content = _buildAudioInspector(selected, theme);
    } else if (hasVideo) {
      final clips = _timeline.videoClips;
      final selected = clips.firstWhere(
        (c) => c.id == _timeline.selectedVideoClipId,
        orElse: () => clips.first,
      );
      title = 'Video Clip';
      content = _buildVideoClipInspector(selected, theme);
    } else {
      title = 'Project Settings';
      content = _buildProjectInspector(theme);
    }

    return Container(
      width: isWide ? 380 : double.infinity,
      color: const Color(0xFF151517),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header of Sidebar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF1C1C1E),
              border: Border(
                bottom: BorderSide(color: Colors.white10, width: 1),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  hasOverlay
                      ? Icons.layers_outlined
                      : hasAudio
                          ? Icons.audiotrack_outlined
                          : hasVideo
                              ? Icons.movie_outlined
                              : Icons.tune_outlined,
                  color: theme.colorScheme.primary,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const Spacer(),
                if (hasOverlay || hasAudio || hasVideo)
                  IconButton(
                    icon: const Icon(Icons.close, size: 16, color: Colors.white38),
                    onPressed: () {
                      _clearSelections();
                      if (!isWide && Navigator.canPop(context)) {
                        Navigator.pop(context);
                      }
                    },
                    tooltip: 'Deselect',
                    constraints: const BoxConstraints(),
                    padding: EdgeInsets.zero,
                  ),
              ],
            ),
          ),
          // Content of Sidebar (Single Scrollable area, no nested scrollviews!)
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0.05, 0),
                      end: Offset.zero,
                    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
                    child: child,
                  ),
                );
              },
              child: SingleChildScrollView(
                key: ValueKey(title),
                padding: const EdgeInsets.all(16),
                child: content,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverlayInspector(VideoOverlayItem? overlay, VideoTextOverlaySpec? spec, ThemeData theme) {
    if (overlay == null) return const Center(child: Text('No overlay data', style: TextStyle(color: Colors.white38)));
    
    final parts = overlay.id.split(':');
    final type = parts.isNotEmpty ? parts[0] : '';
    final content = parts.length > 1 ? parts[1] : '';
    final isText = type == 'text';
    final isEmoji = type == 'emoji';
    final duration = _timeline.durationMs;
    final isWide = MediaQuery.sizeOf(context).width >= LuminaTokens.breakpointTablet;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          color: const Color(0xFF18181A),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: Colors.white10),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Timing (Timeline Range)', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text(
                  'Visible: ${_formatDuration(overlay.startMs)} → ${_formatDuration(overlay.endMs)}',
                  style: const TextStyle(color: Colors.white38, fontSize: 11, fontFamily: 'monospace'),
                ),
                const SizedBox(height: 8),
                RangeSlider(
                  values: RangeValues(
                    overlay.startMs.toDouble(),
                    overlay.endMs.toDouble().clamp(
                      overlay.startMs + 100,
                      duration.toDouble(),
                    ),
                  ),
                  min: 0,
                  max: duration.toDouble() > 0 ? duration.toDouble() : 100.0,
                  activeColor: theme.colorScheme.primary,
                  inactiveColor: Colors.white10,
                  onChanged: (r) {
                    _timeline.updateOverlay(
                      overlay.copyWith(
                        startMs: r.start.round(),
                        endMs: r.end.round(),
                      ),
                    );
                    setState(() {});
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          color: const Color(0xFF18181A),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: Colors.white10),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Fade Transitions', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const SizedBox(width: 60, child: Text('Fade In', style: TextStyle(color: Colors.white38, fontSize: 11))),
                    Expanded(
                      child: Slider(
                        value: overlay.fadeInMs.toDouble(),
                        min: 0,
                        max: 800,
                        divisions: 16,
                        activeColor: theme.colorScheme.primary,
                        inactiveColor: Colors.white10,
                        onChanged: (v) {
                          _timeline.updateOverlay(overlay.copyWith(fadeInMs: v.round()));
                          setState(() {});
                        },
                      ),
                    ),
                    Text('${overlay.fadeInMs}ms', style: const TextStyle(color: Colors.white70, fontSize: 11, fontFamily: 'monospace')),
                  ],
                ),
                Row(
                  children: [
                    const SizedBox(width: 60, child: Text('Fade Out', style: TextStyle(color: Colors.white38, fontSize: 11))),
                    Expanded(
                      child: Slider(
                        value: overlay.fadeOutMs.toDouble(),
                        min: 0,
                        max: 800,
                        divisions: 16,
                        activeColor: theme.colorScheme.primary,
                        inactiveColor: Colors.white10,
                        onChanged: (v) {
                          _timeline.updateOverlay(overlay.copyWith(fadeOutMs: v.round()));
                          setState(() {});
                        },
                      ),
                    ),
                    Text('${overlay.fadeOutMs}ms', style: const TextStyle(color: Colors.white70, fontSize: 11, fontFamily: 'monospace')),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (isText && spec != null) ...[
          Card(
            color: const Color(0xFF18181A),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: Colors.white10),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Text Properties', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  VideoTextOverlayEditPanel(
                    key: ValueKey(overlay.id),
                    spec: spec,
                    onChanged: (newSpec) {
                      _updateTextOverlay(overlay.id, newSpec);
                      setState(() {});
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (isEmoji) ...[
          Card(
            color: const Color(0xFF18181A),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: Colors.white10),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Quick Emoji Selection', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: ['✨', '🔥', '😂', '❤️', '👍', '🎉', '💡', '🍕'].map((emoji) {
                      final isCurrent = content == emoji;
                      return InkWell(
                        onTap: () {
                          final newId = 'emoji:$emoji:${parts.length > 2 ? parts[2] : DateTime.now().millisecondsSinceEpoch}';
                          _timeline.removeOverlay(overlay.id);
                          _timeline.addOverlay(
                            VideoOverlayItem.emoji(
                              id: newId,
                              startMs: overlay.startMs,
                              endMs: overlay.endMs,
                              anchor: overlay.anchor,
                              emoji: emoji,
                            ),
                          );
                          _timeline.selectOverlay(newId);
                          setState(() {});
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: isCurrent
                                ? theme.colorScheme.primary.withValues(alpha: 0.1)
                                : const Color(0xFF222225),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: isCurrent
                                  ? theme.colorScheme.primary
                                  : Colors.white12,
                            ),
                          ),
                          child: Text(emoji, style: const TextStyle(fontSize: 18)),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        FilledButton.icon(
          onPressed: () {
            _timeline.removeOverlay(overlay.id);
            _clearSelections();
            if (!isWide && Navigator.canPop(context)) {
              Navigator.pop(context);
            }
            setState(() {});
          },
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF3A1A1A),
            foregroundColor: Colors.redAccent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
          icon: const Icon(Icons.delete_outline, size: 16),
          label: const Text('Delete Overlay', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _buildAudioInspector(AudioTimelineClip clip, ThemeData theme) {
    final videoDurationMs = _timeline.videoDurationMs.clamp(1, 1 << 30);
    final maxTimelineStart = (videoDurationMs - clip.durationMs).clamp(0, videoDurationMs);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          color: const Color(0xFF18181A),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: Colors.white10),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Audio Volume', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      clip.muted ? Icons.volume_off : Icons.volume_up,
                      size: 16,
                      color: Colors.white70,
                    ),
                    Expanded(
                      child: Slider(
                        value: clip.muted ? 0.0 : clip.volume,
                        activeColor: theme.colorScheme.primary,
                        inactiveColor: Colors.white10,
                        onChanged: (v) {
                          _timeline.updateAudioClip(clip.copyWith(volume: v, muted: v == 0));
                          setState(() {});
                        },
                      ),
                    ),
                    Text('${(clip.volume * 100).round()}%', style: const TextStyle(color: Colors.white70, fontSize: 11, fontFamily: 'monospace')),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          color: const Color(0xFF18181A),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: Colors.white10),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Source Track Trimming', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(
                  'Playing range: ${TimelineFormat.clock(clip.sourceStartMs)}–${TimelineFormat.clock(clip.sourceEndMs)}',
                  style: const TextStyle(color: Colors.white38, fontSize: 10, fontFamily: 'monospace'),
                ),
                const SizedBox(height: 8),
                if (clip.sourceDurationMs > clip.durationMs) ...[
                  AudioRangeScrubber(
                    sourceDurationMs: clip.sourceDurationMs,
                    windowDurationMs: clip.durationMs,
                    sourceStartMs: clip.sourceStartMs,
                    onSourceStartChanged: (ms) {
                      _timeline.updateAudioClip(clip.copyWith(sourceStartMs: ms));
                      // Seek playhead to clip start so user hears the result
                      _playheadSec = clip.timelineStartMs / 1000.0;
                      _playheadNotifier.value = _playheadSec;
                      _applySeekFromTimelineMs(clip.timelineStartMs);
                      setState(() {});
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (maxTimelineStart > 0) ...[
          Card(
            color: const Color(0xFF18181A),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: Colors.white10),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Timeline Start Position', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Slider(
                    value: clip.timelineStartMs.toDouble(),
                    min: 0,
                    max: maxTimelineStart.toDouble(),
                    activeColor: theme.colorScheme.primary,
                    inactiveColor: Colors.white10,
                    onChanged: (v) {
                      final newStart = v.round();
                      _timeline.updateAudioClip(clip.copyWith(timelineStartMs: newStart));
                      // Seek playhead to new clip start
                      _playheadSec = newStart / 1000.0;
                      _playheadNotifier.value = _playheadSec;
                      _applySeekFromTimelineMs(newStart);
                      setState(() {});
                    },
                  ),
                  Text(
                    'Starts playing at: ${TimelineFormat.clock(clip.timelineStartMs)}',
                    style: const TextStyle(color: Colors.white38, fontSize: 10, fontFamily: 'monospace'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        Card(
          color: const Color(0xFF18181A),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: Colors.white10),
          ),
          child: SwitchListTile(
            title: const Text('Mute Original Video Audio', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
            value: _muteOriginalAudio,
            onChanged: (v) {
              setState(() {
                _muteOriginalAudio = v;
              });
              _syncSession();
              _backend?.setEmbeddedAudioMuted(v);
            },
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () {
            _timeline.removeAudioClip(clip.id);
            _clearSelections();
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            }
            setState(() {});
          },
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF3A1A1A),
            foregroundColor: Colors.redAccent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
          icon: const Icon(Icons.delete_outline, size: 16),
          label: const Text('Delete Audio Track', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _buildVideoClipInspector(VideoTimelineClip clip, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          color: const Color(0xFF18181A),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: Colors.white10),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Video Clip Timing', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text(
                  'Duration: ${_formatDuration(clip.durationMs)}',
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  'Source range: ${_formatDuration(clip.sourceStartMs)} → ${_formatDuration(clip.sourceEndMs)}',
                  style: const TextStyle(color: Colors.white38, fontSize: 11, fontFamily: 'monospace'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          color: const Color(0xFF18181A),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: Colors.white10),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Clip Operations', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: _splitAtPlayhead,
                    icon: const Icon(Icons.content_cut, size: 16),
                    label: const Text('Split at Playhead', style: TextStyle(fontSize: 12)),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          _timeline.mergeWithNext(clip.id);
                          setState(() {});
                        },
                        icon: const Icon(Icons.merge, size: 16),
                        label: const Text('Merge Next', style: TextStyle(fontSize: 11)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _timeline.videoClips.length <= 1
                            ? null
                            : () {
                                _timeline.deleteVideoClip(clip.id);
                                _clearSelections();
                                if (Navigator.canPop(context)) {
                                  Navigator.pop(context);
                                }
                                setState(() {});
                              },
                        icon: const Icon(Icons.delete_outline, size: 16),
                        label: const Text('Delete Clip', style: TextStyle(fontSize: 11)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          color: const Color(0xFF18181A),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: Colors.white10),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: _buildClipEffectsEditor(clip),
          ),
        ),
      ],
    );
  }

  Widget _buildProjectInspector(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Trimmer card
        Card(
          color: const Color(0xFF18181A),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: Colors.white10),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Primary Video Trimming', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                _buildTrimmerRowWithoutCard(),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Settings card
        Card(
          color: const Color(0xFF18181A),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: Colors.white10),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Project Settings', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                const Text(
                  'Select a video clip on the timeline to edit zoom, rotation, and speed '
                  'for that segment only.',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
                const SizedBox(height: 12),
                const Divider(color: Colors.white10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Export Preset', style: TextStyle(color: Colors.white54, fontSize: 12)),
                    DropdownButton<CompressionPreset>(
                      dropdownColor: const Color(0xFF1E1E1F),
                      value: _exportPreset,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      underline: const SizedBox(),
                      onChanged: (v) {
                        if (v != null) {
                          setState(() {
                            _exportPreset = v;
                          });
                        }
                      },
                      items: CompressionPreset.values.map((preset) {
                        return DropdownMenuItem<CompressionPreset>(
                          value: preset,
                          child: Text(preset.label),
                        );
                      }).toList(),
                    ),
                  ],
                ),
                const Divider(color: Colors.white10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Hardware Encode', style: TextStyle(color: Colors.white54, fontSize: 12)),
                    Switch(
                      value: _preferHw,
                      activeColor: theme.colorScheme.primary,
                      onChanged: (v) {
                        setState(() {
                          _preferHw = v;
                        });
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Operations card
        Card(
          color: const Color(0xFF18181A),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: Colors.white10),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Timeline Layers Quick-Add', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickAudioTrack,
                        icon: const Icon(Icons.add_to_photos_outlined, size: 14),
                        label: const Text('Add Audio', style: TextStyle(fontSize: 11)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _addTextOverlay,
                        icon: const Icon(Icons.title, size: 14),
                        label: const Text('Add Text', style: TextStyle(fontSize: 11)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _addEmojiOverlay,
                        icon: const Icon(Icons.emoji_emotions_outlined, size: 14),
                        label: const Text('Add Emoji', style: TextStyle(fontSize: 11)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _timeline.overlays.isEmpty ? null : _clearOverlays,
                        icon: const Icon(Icons.layers_clear_outlined, size: 14),
                        label: const Text('Clear All', style: TextStyle(fontSize: 11)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTrimmerRowWithoutCard() {
    final selectionLabel =
        '${_formatDuration((_startSec * 1000).round())} → '
        '${_formatDuration((_endSec * 1000).round())}';
    final durationSec = _activeDurationMs / 1000.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Trim: $selectionLabel', style: const TextStyle(color: Colors.white54, fontSize: 11)),
            if (_loadingFilmstrip)
              const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
          ],
        ),
        const SizedBox(height: 8),
        FilmstripTrimmer(
          thumbPaths: _filmstripPaths,
          durationSeconds: durationSec,
          startSeconds: _startSec,
          endSeconds: _endSec,
          onRangeChanged: _onRangeChanged,
          onDragStart: () => _backend?.pause(),
          onDragEnd: () => _backend?.play(),
        ),
      ],
    );
  }


  Widget _buildStatusLine() {
    return Container(
      color: const Color(0xFF121212),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Text(
        _statusLine,
        style: const TextStyle(color: Colors.white38, fontSize: 11),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  static String _formatDuration(int ms) {
    final s = ms ~/ 1000;
    final m = s ~/ 60;
    return '${m.toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
  }

  static String? _overlayExportHint(String raw) {
    final lower = raw.toLowerCase();
    if (!lower.contains('burn-in') &&
        !lower.contains('libx264') &&
        !lower.contains('libx265') &&
        !lower.contains('software encoder')) {
      return null;
    }
    return 'Tip: rebuild the app after updating native libs '
        '(./scripts/run-media-studio-android.sh). '
        'If this persists, try export without overlays.';
  }

  /// One-line summary for the export sheet (avoids layout overflow from Rust backtraces).
  static String _shortExportError(String raw) {
    var line = raw.split('\n').first.trim();
    final bt = line.indexOf('Stack backtrace');
    if (bt > 0) {
      line = line.substring(0, bt).trim();
    }
    if (line.startsWith('AnyhowException(') && line.endsWith(')')) {
      line = line.substring('AnyhowException('.length, line.length - 1);
    }
    line = line.replaceAll(RegExp(r'\s+'), ' ');
    if (line.length > 200) {
      return '${line.substring(0, 197)}...';
    }
    return line;
  }
}



class _StatLine extends StatelessWidget {
  const _StatLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: const TextStyle(color: Colors.white38, fontSize: 12)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

class _CommandPaletteDialog extends StatefulWidget {
  const _CommandPaletteDialog({
    required this.onAction,
    required this.showDiagnostics,
  });

  final ValueChanged<String> onAction;
  final bool showDiagnostics;

  @override
  State<_CommandPaletteDialog> createState() => _CommandPaletteDialogState();
}

class _CommandPaletteDialogState extends State<_CommandPaletteDialog> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();
  int _selectedIndex = 0;
  List<_CommandPaletteItem> _filteredItems = [];

  late final List<_CommandPaletteItem> _allItems = [
    const _CommandPaletteItem(
      id: 'add_text',
      title: 'Add Text Overlay',
      subtitle: 'Insert custom text at the current playhead position',
      icon: Icons.text_fields,
    ),
    const _CommandPaletteItem(
      id: 'add_emoji',
      title: 'Add Emoji Overlay',
      subtitle: 'Pick and place an emoji at the current playhead position',
      icon: Icons.emoji_emotions_outlined,
    ),
    const _CommandPaletteItem(
      id: 'add_audio',
      title: 'Add Background Audio Track',
      subtitle: 'Import a background music track to the timeline',
      icon: Icons.music_note,
    ),
    const _CommandPaletteItem(
      id: 'split',
      title: 'Split Video Clip',
      subtitle: 'Cut the selected video clip at the playhead',
      icon: Icons.content_cut,
    ),
    const _CommandPaletteItem(
      id: 'toggle_play',
      title: 'Play / Pause Video',
      subtitle: 'Toggle active video playback',
      icon: Icons.play_arrow,
    ),
    _CommandPaletteItem(
      id: 'toggle_diagnostics',
      title: widget.showDiagnostics ? 'Hide Diagnostics Panel' : 'Show Diagnostics Panel',
      subtitle: 'Show performance metrics and GPU render details',
      icon: Icons.analytics_outlined,
    ),
    const _CommandPaletteItem(
      id: 'clear_overlays',
      title: 'Clear All Overlays',
      subtitle: 'Remove all text and emoji layers from the project',
      icon: Icons.delete_sweep,
    ),
    const _CommandPaletteItem(
      id: 'export',
      title: 'Export Video',
      subtitle: 'Render and save the final video with mixed tracks and overlays',
      icon: Icons.save_alt,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _filteredItems = List.from(_allItems);
    _searchController.addListener(_onSearchChanged);
    _inputFocusNode.requestFocus();
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase().trim();
    setState(() {
      if (query.isEmpty) {
        _filteredItems = List.from(_allItems);
      } else {
        _filteredItems = _allItems
            .where((item) =>
                item.title.toLowerCase().contains(query) ||
                item.subtitle.toLowerCase().contains(query))
            .toList();
      }
      _selectedIndex = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 80),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(
            maxWidth: 500,
            maxHeight: 450,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFF151517).withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white10),
            boxShadow: const [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 24,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Search input
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: TextField(
                  controller: _searchController,
                  focusNode: _inputFocusNode,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search, color: Colors.white54, size: 18),
                    hintText: 'Type a command or search...',
                    hintStyle: const TextStyle(color: Colors.white30, fontSize: 14),
                    border: InputBorder.none,
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.05),
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Colors.white10),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
                    ),
                  ),
                  onSubmitted: (_) {
                    if (_filteredItems.isNotEmpty) {
                      widget.onAction(_filteredItems[_selectedIndex].id);
                    }
                  },
                ),
              ),
              const Divider(color: Colors.white10, height: 1),
              // Keyboard navigation support
              Expanded(
                child: RawKeyboardListener(
                  focusNode: FocusNode(),
                  onKey: (RawKeyEvent event) {
                    if (event is RawKeyDownEvent) {
                      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                        setState(() {
                          _selectedIndex = (_selectedIndex + 1) % _filteredItems.length;
                        });
                      } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                        setState(() {
                          _selectedIndex = (_selectedIndex - 1 + _filteredItems.length) % _filteredItems.length;
                        });
                      }
                    }
                  },
                  child: _filteredItems.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 40),
                          child: Center(
                            child: Text(
                              'No matching commands found',
                              style: TextStyle(color: Colors.white30, fontSize: 12),
                            ),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          itemCount: _filteredItems.length,
                          itemBuilder: (context, index) {
                            final item = _filteredItems[index];
                            final isSelected = index == _selectedIndex;

                            return InkWell(
                              onTap: () => widget.onAction(item.id),
                              onHover: (hovered) {
                                if (hovered) {
                                  setState(() {
                                    _selectedIndex = index;
                                  });
                                }
                              },
                              child: Container(
                                color: isSelected
                                    ? Colors.white.withValues(alpha: 0.06)
                                    : Colors.transparent,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                child: Row(
                                  children: [
                                    Icon(
                                      item.icon,
                                      color: isSelected
                                          ? Theme.of(context).colorScheme.primary
                                          : Colors.white54,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item.title,
                                            style: TextStyle(
                                              color: isSelected ? Colors.white : Colors.white70,
                                              fontSize: 12,
                                              fontWeight: isSelected
                                                  ? FontWeight.bold
                                                  : FontWeight.normal,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            item.subtitle,
                                            style: const TextStyle(
                                              color: Colors.white30,
                                              fontSize: 10,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (isSelected)
                                      const Icon(
                                        Icons.keyboard_return,
                                        color: Colors.white24,
                                        size: 14,
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ),
              const Divider(color: Colors.white10, height: 1),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      'Use ↑↓ to navigate, enter to select',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 9),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommandPaletteItem {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;

  const _CommandPaletteItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
  });
}
