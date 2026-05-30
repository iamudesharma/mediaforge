import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_video_processor/flutter_video_processor.dart';
import 'package:path/path.dart' as p;
import 'services/media_ingest.dart';
import 'services/playback_backend.dart';
import 'services/native_backend.dart';
import 'services/rust_backend.dart';
import 'services/preview_playback_mux.dart';
import 'services/output_paths.dart';
import 'widgets/filmstrip_trimmer.dart';
import 'widgets/send_to_chat_sheet.dart';
import 'widgets/video_text_overlay_edit_sheet.dart';
import 'widgets/rust_video_canvas.dart';
import 'widgets/diagnostics_panel.dart';
import 'photo_editor_flow.dart';

class VideoExportResult {
  final String outputPath;
  final String? thumbPath;
  final int originalBytes;
  final int compressedBytes;
  final Duration encodeDuration;

  VideoExportResult({
    required this.outputPath,
    required this.thumbPath,
    required this.originalBytes,
    required this.compressedBytes,
    required this.encodeDuration,
  });
}

class VideoCreatorFlow extends StatefulWidget {
  const VideoCreatorFlow({
    super.key,
    required this.initialPath,
    this.displayName,
  });

  final String initialPath;
  final String? displayName;

  @override
  State<VideoCreatorFlow> createState() => _VideoCreatorFlowState();
}

class _VideoCreatorFlowState extends State<VideoCreatorFlow> {
  static const _filmstripFrames = 10;
  static const _filmstripThumbWidth = 160;
  static final ChangeNotifier _dummyNotifier = ChangeNotifier();
  NativePlaybackController? _player;
  StreamSubscription<ProgressEvent>? _progressSub;

  // ── Backend toggle ──
  bool _useRustBackend = false;
  bool _showDiagnostics = false;
  PlaybackBackend? _backend;

  List<String> _filmstripPaths = [];
  final TimelineController _timeline = TimelineController();
  String? _currentPlaybackPath;
  bool _playbackUsesMux = false;
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
  bool _toolsExpanded = false;
  bool _muteOriginalAudio = false;

  @override
  void initState() {
    super.initState();
    _timeline.addListener(_onTimelineUpdated);
    _loadVideo(widget.initialPath);
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    _timeline.removeListener(_onTimelineUpdated);
    _playheadNotifier.dispose();
    _tearDownPlayer();
    _backend?.dispose();
    super.dispose();
  }

  void _onTimelineUpdated() {
    if (mounted) setState(() {});
  }

  void _invalidatePreviewMux() {
    PreviewPlaybackMux.invalidate();
  }

  /// Switch between Native (video_player) and Rust (rust_media_runtime) backends.
  Future<void> _toggleBackend() async {
    final useRust = !_useRustBackend;
    final wasPlaying = _player?.isPlaying ?? false;
    final currentPath = widget.initialPath;
    final playheadMs = (_playheadSec * 1000).round();

    // Tear down current backend
    await _tearDownPlayer();
    await _tearDownBackend();
    _backend = null;

    setState(() {
      _useRustBackend = useRust;
      _statusLine = useRust ? 'Switching to Rust backend…' : 'Switching to Native backend…';
      _busy = true;
    });

    // Create new backend
    try {
      if (useRust) {
        // Use a unique handle so GPU texture registration works
        final handle = DateTime.now().millisecondsSinceEpoch & 0x7FFFFFFF;
        _backend = RustBackend(textureHandle: handle, previewMaxEdge: 1080);
      } else {
        _backend = NativeBackend();
      }
      _backend!.addListener(_onBackendUpdated);
      await _backend!.open(currentPath);

      // Rust engine must be started to decode any frames at all.
      // Start it, then pause if user wasn't playing before.
      await _backend!.play();
      if (!wasPlaying) {
        _backend!.pause();
      }

      // Restore playhead position
      if (playheadMs > 0) {
        await _backend!.seekTo(Duration(milliseconds: playheadMs));
      }

      if (mounted) {
        setState(() {
          _busy = false;
          _statusLine = useRust
              ? 'Rust backend active · HW decode'
              : 'Native backend active';
          _updateNativeHudFromBackend(_backend!);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _statusLine = 'Backend switch failed: $e';
        });
      }
    }
  }

  /// Unified callback for both backends (handles position updates).
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
          _updateNativeHudFromBackend(backend);
        }
      });
    }
  }

  void _updateNativeHudFromBackend(PlaybackBackend backend) {
    final info = backend.mediaInfo;
    if (info == null) {
      _metricsLine = _useRustBackend ? 'rust playback' : 'native playback';
      return;
    }
    final engineLabel = _useRustBackend ? 'Rust MediaRuntime' : nativePlaybackEngineLabel();
    _metricsLine = '$engineLabel · ${info.width}×${info.height} · ${info.videoCodec}';
  }

  Future<void> _tearDownBackend() async {
    final backend = _backend;
    if (backend == null) return;
    backend.removeListener(_onBackendUpdated);
    backend.pause();
    await backend.close();
  }

  Future<void> _tearDownPlayer() async {
    final player = _player;
    if (player == null) return;
    player.removeListener(_onPlayerUpdated);
    _player = null;
    player.pause();
    await player.close();
    player.dispose();
  }

  void _onPlayerUpdated() {
    final player = _player;
    if (player == null || !mounted) return;
    final sourceMs = player.positionMs;
    final timelineSec = _timelineSecFromSourcePts(sourceMs);
    final clampedSec = _safeClamp(
      timelineSec,
      0,
      _timelineDurationSec > 0 ? _timelineDurationSec : _endSec,
    );

    // Update playhead notifier instantly for the smooth scrubber slider
    _playheadSec = clampedSec;
    _playheadNotifier.value = clampedSec;

    if (player.isPlaying) {
      unawaited(_advancePastClipEndIfNeeded(sourceMs));
    }

    // Throttle heavy full-screen rebuilds (Timeline, overlays, tools panel) during playback
    final now = DateTime.now();
    final lastRebuild = _lastTimelineRebuild;
    final shouldRebuild = !player.isPlaying ||
        lastRebuild == null ||
        now.difference(lastRebuild).inMilliseconds >= 120;

    if (shouldRebuild) {
      _lastTimelineRebuild = now;
      setState(() {
        if (player.isPlaying) {
          _updateNativeHud(player);
        }
      });
    }
  }

  void _updateNativeHud(NativePlaybackController player) {
    final info = player.mediaInfo;
    if (info == null) {
      _metricsLine = 'native playback';
      return;
    }
    _metricsLine =
        'native ${nativePlaybackEngineLabel()} · ${info.width}×${info.height} · ${info.videoCodec}';
  }

  Future<void> _loadVideo(String path) async {
    setState(() {
      _busy = true;
      _statusLine = 'Loading video…';
    });

    try {
      await _tearDownPlayer();
      _player = NativePlaybackController(loopPlayback: false);
      _player!.addListener(_onPlayerUpdated);
      await _player!.open(path);

      final info = _player!.mediaInfo ?? await VideoProcessor.getMediaInfo(path);
      final dur = info.durationMs.toInt() / 1000.0;
      
      final durationMs = info.durationMs.toInt();
      _timeline.loadPrimaryVideo(
        sourcePath: path,
        durationMs: durationMs > 0 ? durationMs : 1000,
      );

      setState(() {
        _startSec = 0;
        _endSec = dur > 0 ? dur : 1;
        _playheadSec = 0;
        _statusLine = 'Ready · ${info.width}×${info.height} · ${info.videoCodec}';
        _busy = false;
      });

      _currentPlaybackPath = path;
      _playbackUsesMux = false;
      _invalidatePreviewMux();
      _updateNativeHud(_player!);
      _player!.setTrimRange(
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
      final duration = _useRustBackend
          ? (_backend?.durationMs ?? 0)
          : (_player?.mediaInfo?.durationMs.toInt() ?? 0);
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
    if (_playbackUsesMux) {
      return _startSec + sourcePtsMs / 1000.0;
    }
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
    // Rust backend path
    if (_useRustBackend) {
      final backend = _backend;
      if (backend == null || !backend.isOpen) return;
      await backend.seekTo(Duration(milliseconds: timelineMs));
      return;
    }

    // Native backend path
    final player = _player;
    if (player == null || !player.isOpen) return;

    if (_playbackUsesMux) {
      final trimStartMs = (_startSec * 1000).round();
      final muxDur = player.durationMs > 0 ? player.durationMs : 1;
      final offsetMs =
          (timelineMs - trimStartMs).clamp(0, muxDur);
      await player.seekTo(Duration(milliseconds: offsetMs));
      return;
    }

    final target = _timeline.seekTargetAt(timelineMs);
    if (target == null) return;

    final clip = _timeline.clipById(target.clipId);
    if (clip != null) {
      player.setTrimRange(
        startMs: clip.sourceStartMs,
        endMs: clip.sourceEndMs,
      );
    }
    await player.seekTo(Duration(milliseconds: target.sourceMs));
  }

  Future<void> _advancePastClipEndIfNeeded(int sourcePtsMs) async {
    if (_useRustBackend) {
      // Rust backend: simplified clip advance (no mux path)
      final backend = _backend;
      if (backend == null || !backend.isPlaying) return;

      final clip = _timeline.clipAtTimelineMs(_playheadTimelineMs);
      if (clip == null) return;
      if (sourcePtsMs < clip.sourceEndMs - 80) return;

      final index = _timeline.videoClips.indexWhere((c) => c.id == clip.id);
      if (index < 0 || index >= _timeline.videoClips.length - 1) {
        backend.pause();
        return;
      }
      final next = _timeline.videoClips[index + 1];
      setState(() => _playheadSec = next.timelineStartMs / 1000.0);
      await _applySeekFromTimelineMs(next.timelineStartMs);
      if (backend.isOpen && !backend.isPlaying) {
        await backend.play();
      }
      return;
    }

    // Native backend path
    final player = _player;
    if (player == null || !player.isPlaying) return;

    final clip = _timeline.clipAtTimelineMs(_playheadTimelineMs);
    if (clip == null) return;
    if (sourcePtsMs < clip.sourceEndMs - 80) return;

    final index = _timeline.videoClips.indexWhere((c) => c.id == clip.id);
    if (index < 0 || index >= _timeline.videoClips.length - 1) {
      player.pause();
      await player.setEmbeddedAudioMuted(_muteOriginalAudio);
      return;
    }
    final next = _timeline.videoClips[index + 1];
    setState(() => _playheadSec = next.timelineStartMs / 1000.0);
    await _applySeekFromTimelineMs(next.timelineStartMs);
    if (player.isOpen && !player.isPlaying) {
      await player.play();
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

  Future<void> _pickAudioTrack() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'm4a', 'aac', 'wav', 'ogg', 'flac'],
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) {
      if (mounted) {
        setState(() => _statusLine = 'Audio import failed: no file path');
      }
      return;
    }

    setState(() => _statusLine = 'Importing audio…');
    final ingested = await MediaIngest.ingestLocalAudio(
      path,
      onStatus: (s) {
        if (mounted) setState(() => _statusLine = s);
      },
    );
    if (ingested.phase != MediaIngestPhase.ready ||
        ingested.stablePath == null ||
        ingested.info == null) {
      if (mounted) {
        setState(() => _statusLine = ingested.error ?? 'Audio import failed');
      }
      return;
    }

    final stablePath = ingested.stablePath!;
    final sourceDurationMs = ingested.info!.durationMs.toInt();
    // Always start audio at timeline 0 — background music should cover the
    // whole video (like CapCut / Instagram / TikTok).  Using _playheadTimelineMs
    // would cause clamping to ~1 ms when the playhead is near the end of a
    // short video.
    _timeline.addAudioClip(
      sourcePath: stablePath,
      sourceDurationMs: sourceDurationMs > 0 ? sourceDurationMs : 1000,
      timelineStartMs: 0,
      videoDurationMs: _timeline.videoDurationMs,
    );
    _invalidatePreviewMux();
    if (mounted) {
      setState(() {
        _statusLine =
            'Audio track added · ${p.basename(stablePath)} '
            '(${_formatDuration(sourceDurationMs)})';
      });
    }
  }

  /// Re-open the native player on [path] (original video or FFmpeg preview mux).
  Future<void> _reopenPlayerAtPath(
    String path, {
    required bool muxed,
    bool playAfterOpen = false,
  }) async {
    final wasPlaying = _player?.isPlaying ?? false;
    final playhead = _playheadSec;
    await _tearDownPlayer();
    _player = NativePlaybackController(loopPlayback: false);
    _player!.addListener(_onPlayerUpdated);
    _currentPlaybackPath = path;
    _playbackUsesMux = muxed;
    await _player!.open(path);
    if (!_player!.isOpen) {
      throw StateError('Failed to open playback: $path');
    }
    if (muxed) {
      final dur = _player!.durationMs;
      _player!.setTrimRange(startMs: 0, endMs: dur > 0 ? dur : 1);
    } else {
      _player!.setTrimRange(
        startMs: (_startSec * 1000).round(),
        endMs: (_endSec * 1000).round(),
      );
    }
    await _player!.setEmbeddedAudioMuted(
      muxed ? false : _muteOriginalAudio,
    );
    _playheadSec = playhead;
    await _applySeekFromTimelineMs(_playheadTimelineMs);
    debugPrint(
      '[PreviewMux] opened muxed=$muxed path=$path '
      'isOpen=${_player!.isOpen} duration=${_player!.durationMs}ms '
      'playAfterOpen=$playAfterOpen',
    );
    if ((playAfterOpen || wasPlaying) && _player!.isOpen) {
      await _player!.play();
    }
    if (mounted) setState(() {});
  }

  /// Builds a single mixed preview file when overlay audio exists (CapCut-style).
  Future<bool> _ensurePreviewPlaybackReady({bool playAfterOpen = false}) async {
    final tracks = _exportAudioTracks();
    if (tracks.isEmpty) {
      if (_playbackUsesMux) {
        await _reopenPlayerAtPath(
          widget.initialPath,
          muxed: false,
          playAfterOpen: playAfterOpen,
        );
      }
      return true;
    }

    final (startMs, endMs) = _exportTrimMs();
    try {
      final path = await PreviewPlaybackMux.ensure(
        videoPath: widget.initialPath,
        startMs: startMs,
        endMs: endMs,
        audioTracks: tracks,
        muteOriginalAudio: _muteOriginalAudio,
        onStatus: (s) {
          if (mounted) setState(() => _statusLine = s);
        },
      );
      final needsReopen =
          !_playbackUsesMux || path != _currentPlaybackPath;
      debugPrint(
        '[PreviewMux] ensure ready path=$path current=$_currentPlaybackPath '
        'usesMux=$_playbackUsesMux needsReopen=$needsReopen',
      );
      if (needsReopen) {
        await _reopenPlayerAtPath(
          path,
          muxed: true,
          playAfterOpen: playAfterOpen,
        );
      } else if (playAfterOpen) {
        await _applySeekFromTimelineMs(_playheadTimelineMs);
        await _player?.play();
      }
      return true;
    } catch (e, st) {
      debugPrint('[PreviewMux] failed: $e\n$st');
      if (mounted) {
        setState(() => _statusLine = 'Preview mix failed: $e');
      }
      return false;
    }
  }

  void _splitAtPlayhead() {
    final ok = _timeline.splitVideoAt(_playheadTimelineMs);
    setState(() {
      _statusLine = ok
          ? 'Split clip at ${_formatDuration(_playheadTimelineMs)}'
          : 'Cannot split here (move playhead inside a clip)';
    });
  }

  void _onRangeChanged(double start, double end) {
    final dur = (_player?.mediaInfo?.durationMs.toInt() ?? 0) / 1000.0;
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
    _invalidatePreviewMux();
    if (!_playbackUsesMux) {
      _player?.setTrimRange(
        startMs: (_startSec * 1000).round(),
        endMs: (_endSec * 1000).round(),
      );
    }
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
    if (_useRustBackend) {
      // Rust backend doesn't have a separate mux path; just seek
      unawaited(_applySeekFromTimelineMs((timelineSeconds * 1000).round()));
      return;
    }
    if (_player?.isPlaying ?? false) return;
    unawaited(_applySeekFromTimelineMs((timelineSeconds * 1000).round()));
  }

  Future<void> _togglePlayback() async {
    if (_useRustBackend) {
      return _togglePlaybackRust();
    }
    final player = _player;
    if (player == null || !player.isOpen || _busy) return;
    if (player.isPlaying) {
      player.pause();
      if (mounted) setState(() {});
      return;
    }

    setState(() => _busy = true);
    try {
      final ready = await _ensurePreviewPlaybackReady(playAfterOpen: true);
      if (!mounted || !ready) return;
      final active = _player;
      if (active == null || !active.isOpen) {
        if (mounted) {
          setState(() => _statusLine = 'Preview player failed to open');
        }
        return;
      }
      if (!active.isPlaying) {
        await _applySeekFromTimelineMs(_playheadTimelineMs);
        await active.play();
      }
      if (mounted) {
        setState(() => _statusLine = _exportAudioTracks().isEmpty
            ? 'Playing'
            : 'Playing preview mix');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Rust backend playback toggle.
  Future<void> _togglePlaybackRust() async {
    final backend = _backend;
    if (backend == null || !backend.isOpen || _busy) return;

    if (backend.isPlaying) {
      backend.pause();
      if (mounted) setState(() {});
      return;
    }

    setState(() => _busy = true);
    try {
      // Check if audio tracks need mixing
      final tracks = _exportAudioTracks();
      if (tracks.isNotEmpty) {
        // Build muxed preview with mixed audio
        final (startMs, endMs) = _exportTrimMs();
        final muxPath = await PreviewPlaybackMux.ensure(
          videoPath: widget.initialPath,
          startMs: startMs,
          endMs: endMs,
          audioTracks: tracks,
          muteOriginalAudio: _muteOriginalAudio,
          onStatus: (s) {
            if (mounted) setState(() => _statusLine = s);
          },
        );
        // Reopen Rust backend on muxed file
        final needsReopen = muxPath != _currentPlaybackPath;
        if (needsReopen) {
          _currentPlaybackPath = muxPath;
          _playbackUsesMux = true;
          await (backend as RustBackend).reopenFile(muxPath);
        }
      } else if (_playbackUsesMux) {
        // No audio tracks but currently on mux — switch back to original
        _currentPlaybackPath = widget.initialPath;
        _playbackUsesMux = false;
        await (backend as RustBackend).reopenFile(widget.initialPath);
      }

      await _applySeekFromTimelineMs(_playheadTimelineMs);
      await backend.play();
      if (mounted) {
        setState(() => _statusLine = tracks.isEmpty
            ? 'Playing (Rust)'
            : 'Playing preview mix (Rust)');
      }
    } catch (e) {
      debugPrint('[RustBackend] playback start failed: $e');
      if (mounted) {
        setState(() => _statusLine = 'Playback failed: $e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addTextOverlay() async {
    final spec = await VideoTextOverlayEditSheet.show(
      context,
      initialSpec: const VideoTextOverlaySpec(label: ''),
      title: 'Add text overlay',
    );
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
    );
    _timeline.addOverlay(overlay);
    setState(() {});
  }

  void _updateTextOverlay(String id, VideoTextOverlaySpec spec) {
    final i = _timeline.overlays.indexWhere((o) => o.id == id);
    if (i < 0) return;
    _timeline.updateOverlay(_timeline.overlays[i].withTextSpec(spec));
  }

  Future<void> _editTextOverlay(VideoOverlayItem overlay) async {
    final initial = overlay.resolvedTextSpec;
    if (initial == null) return;
    final spec = await VideoTextOverlayEditSheet.show(
      context,
      initialSpec: initial,
      title: 'Edit text',
    );
    if (spec == null || !mounted) return;
    _updateTextOverlay(overlay.id, spec);
    setState(() {});
  }

  VideoOverlayItem? _selectedOverlay() {
    final id = _timeline.selectedOverlayId;
    if (id == null) return null;
    for (final o in _timeline.overlays) {
      if (o.id == id) return o;
    }
    return null;
  }

  void _addEmojiOverlay() {
    final emojis = ['✨', '🔥', '😂', '❤️', '👍', '🍕', '🎉', '✈️'];
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Choose Emoji Overlay',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              GridView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                ),
                itemCount: emojis.length,
                itemBuilder: (context, i) {
                  return InkWell(
                    onTap: () {
                      final duration = _timeline.durationMs;
                      final startMs = _playheadTimelineMs;
                      final endMs = (startMs + 5000).clamp(0, duration);
                      
                      final overlay = VideoOverlayItem.emoji(
                        id: 'emoji:${emojis[i]}:${DateTime.now().millisecondsSinceEpoch}',
                        startMs: startMs,
                        endMs: endMs,
                        anchor: const Offset(0.7, 0.2),
                        emoji: emojis[i],
                      );
                      
                      _timeline.addOverlay(overlay);
                      setState(() {});
                      Navigator.pop(ctx);
                    },
                    child: Center(
                      child: Text(emojis[i], style: const TextStyle(fontSize: 40)),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  /// JPEG/PNG bytes at [seekMs] with seek retries and Apple RGBA preview fallback.
  Future<Uint8List> _extractPosterFrameBytes(int seekMs) async {
    final attempts = <int>{
      seekMs,
      math.max(0, seekMs - 2000),
      0,
    };
    Object? lastError;
    for (final ms in attempts) {
      try {
        return await VideoProcessor.thumbnailBytes(
          input: widget.initialPath,
          position: Duration(milliseconds: ms),
          width: 1080,
        );
      } catch (e) {
        lastError = e;
      }
    }

    if (Platform.isMacOS || Platform.isIOS) {
      try {
        final frame = await VideoProcessor.decodePreviewFrameRgba(
          inputPath: widget.initialPath,
          positionMs: seekMs,
          maxEdge: 1080,
        );
        try {
          return await _rgba8888ToPngBytes(
            frame.rgba,
            frame.width,
            frame.height,
          );
        } finally {
          VideoProcessor.releaseBuffer(frame.rgba);
        }
      } catch (e) {
        lastError = e;
      }
    }

    throw lastError ?? StateError('poster frame extraction failed');
  }

  static Future<Uint8List> _rgba8888ToPngBytes(
    Uint8List rgba,
    int width,
    int height,
  ) async {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      width,
      height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    final image = await completer.future;
    try {
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw StateError('RGBA preview encode to PNG failed');
      }
      return byteData.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  Future<void> _runPosterFrameBridge() async {
    if (_busy) return;

    setState(() {
      _busy = true;
      _statusLine = 'Extracting frame at playhead…';
    });

    try {
      final duration = _player?.mediaInfo?.durationMs.toInt() ?? 0;
      final requestedMs = (_playheadSec * 1000).round();
      final seekMs = duration > 100
          ? requestedMs.clamp(0, duration - 100)
          : requestedMs;

      final bytes = await _extractPosterFrameBytes(seekMs);

      if (!mounted) return;
      setState(() {
        _busy = false;
        _statusLine = 'Opening Photo Editor…';
      });

      final editedPath = await Navigator.push<String?>(
        context,
        MaterialPageRoute(
          builder: (context) => PhotoEditorFlow(
            initialBytes: bytes,
            title: 'Edit Frame',
          ),
        ),
      );

      if (!mounted) return;

      if (editedPath != null && File(editedPath).existsSync()) {
        final clipDuration = _player?.mediaInfo?.durationMs.toInt() ?? 1000;
        final startMs = (_playheadSec * 1000).round();
        final endMs = (startMs + 6000).clamp(0, clipDuration);

        final overlay = VideoOverlayItem(
          id: 'poster:Edited Frame:${DateTime.now().millisecondsSinceEpoch}',
          startMs: startMs,
          endMs: endMs,
          anchor: const Offset(0.5, 0.5),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 2),
              borderRadius: BorderRadius.circular(8),
              color: Colors.black38,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.file(
                File(editedPath),
                width: 150,
                height: 150,
                fit: BoxFit.contain,
              ),
            ),
          ),
        );

        _timeline.addOverlay(overlay);
        setState(() {
          _statusLine = 'Poster frame overlay added!';
        });
      } else {
        setState(() {
          _statusLine = 'Frame editing cancelled.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusLine = 'Poster frame failed: $e';
        });
      }
    } finally {
      if (mounted && _busy) {
        setState(() => _busy = false);
      }
    }
  }

  void _clearOverlays() {
    _timeline.clearOverlays();
    setState(() => _statusLine = 'Cleared all overlays');
  }

  Future<void> _exportVideo() async {
    final player = _player;
    if (player == null || _busy) return;

    if (player.isPlaying) {
      player.pause();
    }

    setState(() {
      _busy = true;
      _statusLine = _timeline.overlays.isEmpty
          ? 'Preparing export…'
          : 'Baking overlays for export…';
    });

    List<BurnInOverlay> burnInOverlays = const [];
    try {
      if (_timeline.overlays.isNotEmpty) {
        final info = player.mediaInfo ??
            await VideoProcessor.getMediaInfo(widget.initialPath);
        burnInOverlays = await OverlayRasterExporter.rasterizeForExport(
          overlays: _timeline.overlays,
          sourceWidth: info.width,
          sourceHeight: info.height,
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

    final outputs = await OutputPaths.resolve();
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
              // Initiate compressJob
              final sw = Stopwatch()..start();
              VideoProcessor.compressJob(
                input: widget.initialPath,
                output: outPath,
                quality: _exportPreset.quality,
                // Burn-in uses CPU YUV420P compositing; software encode is required.
                preferHardwareEncoder:
                    burnInOverlays.isEmpty && _preferHw,
                startMs: startMs,
                endMs: endMs > startMs ? endMs : null,
                burnInOverlays: burnInOverlays,
                audioTracks: exportAudioTracks,
                muteOriginalAudio: muteOriginalAudio,
              ).then((job) {
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
                              _invalidatePreviewMux();
                              if (_exportAudioTracks().isEmpty &&
                                  !_playbackUsesMux) {
                                if (_useRustBackend) {
                                  _backend?.setEmbeddedAudioMuted(v);
                                } else {
                                  _player?.setEmbeddedAudioMuted(v);
                                }
                              }
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
              onPressed: () {
                Navigator.pop(ctx);
                showSendToChatSheet(
                  context,
                  displayName: widget.displayName ?? 'Video',
                  path: result.outputPath,
                  originalBytes: result.originalBytes,
                  compressedBytes: result.compressedBytes,
                  encodeDuration: result.encodeDuration,
                );
              },
              child: const Text('Share to Chat'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx); // Pop success dialog
                Navigator.pop(context, result); // Pop creator flow back to HomeHub with result
              },
              child: const Text('Post to Updates'),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLoaded = _useRustBackend
        ? (_backend != null && _backend!.isOpen)
        : (_player != null && _player!.isOpen);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(widget.displayName ?? 'Video Creator', style: const TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (isLoaded) ...[
            // Backend toggle button
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: _useRustBackend
                    ? Colors.greenAccent.withValues(alpha: 0.2)
                    : Colors.white12,
                borderRadius: BorderRadius.circular(16),
              ),
              child: InkWell(
                onTap: _busy ? null : _toggleBackend,
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _useRustBackend ? Icons.memory : Icons.phone_android,
                        size: 14,
                        color: _useRustBackend
                            ? Colors.greenAccent
                            : Colors.white70,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _useRustBackend ? 'Rust' : 'Native',
                        style: TextStyle(
                          color: _useRustBackend
                              ? Colors.greenAccent
                              : Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Diagnostics toggle (Rust only)
            if (_useRustBackend)
              IconButton(
                icon: Icon(
                  Icons.analytics_outlined,
                  color: _showDiagnostics ? Colors.greenAccent : Colors.white54,
                  size: 20,
                ),
                onPressed: () {
                  setState(() => _showDiagnostics = !_showDiagnostics);
                },
                tooltip: 'Diagnostics',
              ),
            TextButton.icon(
              onPressed: _runPosterFrameBridge,
              icon: const Icon(Icons.portrait, color: Colors.white),
              label: const Text('Edit Frame', style: TextStyle(color: Colors.white)),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: _exportVideo,
              icon: const Icon(Icons.save_alt, color: Colors.white),
              label: const Text('Export', style: TextStyle(color: Colors.white)),
            ),
          ],
        ],
      ),
      body: DefaultTabController(
        length: 3,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Upper half: Video player canvas (fills all remaining room)
              Expanded(
                child: Container(
                  color: Colors.black,
                  alignment: Alignment.center,
                  child: isLoaded
                      ? Stack(
                          children: [
                            ListenableBuilder(
                              listenable: _timeline,
                              builder: (context, _) {
                                return ValueListenableBuilder<double>(
                                  valueListenable: _playheadNotifier,
                                  builder: (context, playheadSec, _) {
                                    if (_useRustBackend) {
                                      final rustBackend = _backend as RustBackend?;
                                      if (rustBackend == null) {
                                        return const Center(
                                          child: CircularProgressIndicator(color: Colors.white),
                                        );
                                      }
                                      return RustVideoCanvas(
                                        key: ValueKey(_currentPlaybackPath),
                                        backend: rustBackend,
                                        overlays: _timeline.overlays,
                                        timelinePlayheadMs:
                                            (playheadSec * 1000).round(),
                                        selectedOverlayId:
                                            _timeline.selectedOverlayId,
                                        onSelectOverlay: (id) {
                                          _timeline.selectOverlay(id);
                                          setState(() {});
                                        },
                                        onOverlayChanged: (item) {
                                          _timeline.updateOverlay(item);
                                          setState(() {});
                                        },
                                        showDiagnostics: _showDiagnostics,
                                      );
                                    }
                                    return NativeVideoCanvas(
                                      key: ValueKey(_currentPlaybackPath),
                                      controller: _player!,
                                      overlays: _timeline.overlays,
                                      timelinePlayheadMs:
                                          (playheadSec * 1000).round(),
                                      selectedOverlayId:
                                          _timeline.selectedOverlayId,
                                      onSelectOverlay: (id) {
                                        _timeline.selectOverlay(id);
                                        setState(() {});
                                      },
                                      onOverlayChanged: (item) {
                                        _timeline.updateOverlay(item);
                                        setState(() {});
                                      },
                                    );
                                  },
                                );
                              },
                            ),
                            // Play Button Overlay
                            Positioned.fill(
                              child: ListenableBuilder(
                                listenable: _useRustBackend
                                    ? (_backend ?? _dummyNotifier)
                                    : (_player ?? _dummyNotifier),
                                builder: (context, _) {
                                  final playing = _useRustBackend
                                      ? (_backend?.isPlaying ?? false)
                                      : (_player?.isPlaying ?? false);
                                  if (playing) return const SizedBox.shrink();
                                  return Center(
                                    child: GestureDetector(
                                      onTap: _togglePlayback,
                                      child: Container(
                                        padding: const EdgeInsets.all(16),
                                        decoration: const BoxDecoration(
                                          color: Colors.black54,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(Icons.play_arrow, size: 64, color: Colors.white),
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
                                    style: const TextStyle(color: Colors.white70, fontSize: 10, fontFamily: 'monospace'),
                                  ),
                                ),
                              ),
                          ],
                        )
                      : const Center(
                          child: CircularProgressIndicator(),
                        ),
                ),
              ),

              // Diagnostics panel (Rust backend only)
              if (isLoaded && _useRustBackend && _showDiagnostics)
                SizedBox(
                  height: 180,
                  child: DiagnosticsPanel(
                    backend: _backend as RustBackend,
                  ),
                ),

              if (isLoaded) ...[
                _buildScrubberRow(theme),
                
                if (_toolsExpanded) ...[
                  Row(
                    children: [
                      Expanded(
                        child: TabBar(
                          dividerColor: Colors.transparent,
                          indicatorColor: theme.colorScheme.primary,
                          labelColor: Colors.white,
                          unselectedLabelColor: Colors.white38,
                          labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                          tabs: const [
                            Tab(icon: Icon(Icons.cut, size: 16), text: 'Trim & Export'),
                            Tab(icon: Icon(Icons.linear_scale, size: 16), text: 'Tracks'),
                            Tab(icon: Icon(Icons.title, size: 16), text: 'Add Overlays'),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white),
                        onPressed: () => setState(() => _toolsExpanded = false),
                        tooltip: 'Collapse Tools',
                      ),
                    ],
                  ),
                  
                  SizedBox(
                    height: 180,
                    child: TabBarView(
                      children: [
                        // Tab 1: Trim & Settings
                        SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildTrimmerRow(),
                              _buildPlaybackControls(),
                              _buildSettingsRow(theme),
                            ],
                          ),
                        ),
                        // Tab 2: Tracks
                        SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Card(
                                color: const Color(0xFF141414),
                                margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                                child: SwitchListTile(
                                  title: const Text(
                                    'Mute Original Video Audio',
                                    style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                  ),
                                  subtitle: const Text(
                                    'Toggle original audio playback during preview',
                                    style: TextStyle(color: Colors.white38, fontSize: 11),
                                  ),
                                  value: _muteOriginalAudio,
                                   onChanged: (v) {
                                     setState(() {
                                       _muteOriginalAudio = v;
                                     });
                                     _invalidatePreviewMux();
                                     if (_exportAudioTracks().isEmpty) {
                                       if (_useRustBackend) {
                                         _backend?.setEmbeddedAudioMuted(v);
                                       } else {
                                         _player?.setEmbeddedAudioMuted(v);
                                       }
                                     }
                                   },
                                ),
                              ),
                              TimelineEditorPanel(
                                controller: _timeline,
                                playheadMs: _playheadTimelineMs,
                                onAddAudio: _pickAudioTrack,
                                onAddText: _addTextOverlay,
                                onAddEmoji: _addEmojiOverlay,
                                onSplitAtPlayhead: _splitAtPlayhead,
                              ),
                            ],
                          ),
                        ),
                        // Tab 3: Add Overlays (Inline widgets, no blocking dialogs)
                        SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: _buildOverlaysTab(theme),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () => setState(() => _toolsExpanded = true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1E1E1E),
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(Icons.keyboard_arrow_up, size: 18),
                          label: const Text('Show Editing Tools', style: TextStyle(fontSize: 12)),
                        ),
                        const SizedBox(width: 8),
                        if (_timeline.overlays.isNotEmpty)
                          TextButton.icon(
                            onPressed: _clearOverlays,
                            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                            icon: const Icon(Icons.layers_clear, size: 14),
                            label: Text('Clear (${_timeline.overlays.length})', style: const TextStyle(fontSize: 11)),
                          )
                        else
                          const SizedBox(width: 80),
                      ],
                    ),
                  ),
                ],
              ],
              _buildStatusLine(),
            ],
          ),
        ),
      ),
    );
  }



  Widget _buildPlaybackControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ListenableBuilder(
        listenable: _useRustBackend
            ? (_backend ?? _dummyNotifier)
            : (_player ?? _dummyNotifier),
        builder: (context, _) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white),
                onPressed: _buildFilmstrip,
                tooltip: 'Regenerate Filmstrip',
              ),
              const SizedBox(width: 32),
              IconButton(
                icon: const Icon(Icons.layers_clear_outlined, color: Colors.white),
                onPressed: _timeline.overlays.isEmpty ? null : _clearOverlays,
                tooltip: 'Clear Overlays',
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildScrubberRow(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          ValueListenableBuilder<double>(
            valueListenable: _playheadNotifier,
            builder: (context, val, _) {
              final ms = (val * 1000).round();
              return Text(_formatDuration(ms), style: const TextStyle(color: Colors.white70, fontSize: 11));
            },
          ),
          Expanded(
            child: ValueListenableBuilder<double>(
              valueListenable: _playheadNotifier,
              builder: (context, val, _) {
                return Slider(
                  value: _safeClamp(val, 0, _timelineDurationSec),
                  min: 0,
                  max: _timelineDurationSec > 0 ? _timelineDurationSec : 0.01,
                  activeColor: theme.colorScheme.primary,
                  inactiveColor: Colors.white24,
                  onChanged: (v) {
                    if (_useRustBackend) {
                      _backend?.pause();
                    } else {
                      _player?.pause();
                    }
                    _playheadSec = v;
                    _playheadNotifier.value = v;
                    _schedulePreviewSync(v);
                  },
                );
              },
            ),
          ),
          Text(_formatDuration(_timeline.durationMs), style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildSettingsRow(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          const Text('Export Preset:', style: TextStyle(color: Colors.white70, fontSize: 11)),
          const SizedBox(width: 8),
          DropdownButton<CompressionPreset>(
            dropdownColor: const Color(0xFF1E1E1E),
            value: _exportPreset,
            style: const TextStyle(color: Colors.white, fontSize: 11),
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
          const Spacer(),
          const Text('HW Encode', style: TextStyle(color: Colors.white70, fontSize: 11)),
          const SizedBox(width: 4),
          Transform.scale(
            scale: 0.8,
            child: Switch(
              value: _preferHw,
              onChanged: (v) {
                setState(() {
                  _preferHw = v;
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverlaysTab(ThemeData theme) {
    final selected = _selectedOverlay();
    final selectedTextSpec = selected?.resolvedTextSpec;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 36,
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _addTextOverlay,
              icon: const Icon(Icons.title, size: 16, color: Colors.white),
              label: const Text(
                'Add styled text…',
                style: TextStyle(color: Colors.white, fontSize: 12),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.white24),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Emoji quick grid
          const Text('Tap Emoji to Insert:', style: TextStyle(color: Colors.white70, fontSize: 11)),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: ['✨', '🔥', '😂', '❤️', '👍', '🎉', '💡', '🍕'].map((emoji) {
              return InkWell(
                onTap: () {
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
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(emoji, style: const TextStyle(fontSize: 16)),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          const Text(
            'Drag overlay on preview to reposition.',
            style: TextStyle(color: Colors.white38, fontSize: 10),
          ),
          const SizedBox(height: 8),
          // Active overlays list with delete buttons
          if (_timeline.overlays.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Active Overlays:', style: TextStyle(color: Colors.white70, fontSize: 11)),
                TextButton(
                  onPressed: _clearOverlays,
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
                  child: const Text('Clear All', style: TextStyle(color: Colors.redAccent, fontSize: 11)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            ..._timeline.overlays.map((o) {
              final parts = o.id.split(':');
              final type = parts.isNotEmpty ? parts[0] : '';
              final content = parts.length > 1 ? parts[1] : '';

              final isText = type == 'text';
              final isEmoji = type == 'emoji';

              IconData icon;
              if (isText) {
                icon = Icons.title;
              } else if (isEmoji) {
                icon = Icons.emoji_emotions;
              } else {
                icon = Icons.portrait;
              }

              final selected = o.id == _timeline.selectedOverlayId;
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    _timeline.selectOverlay(o.id);
                    setState(() {});
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                margin: const EdgeInsets.symmetric(vertical: 2),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: selected
                      ? const Color(0xFF2A3A35)
                      : const Color(0xFF161616),
                  borderRadius: BorderRadius.circular(4),
                  border: selected
                      ? Border.all(color: const Color(0xFF00D4AA), width: 1)
                      : null,
                ),
                child: Row(
                  children: [
                    Icon(icon, size: 14, color: Colors.white54),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        content,
                        style: const TextStyle(color: Colors.white, fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${_formatDuration(o.startMs)} - ${_formatDuration(o.endMs)}',
                      style: const TextStyle(color: Colors.white38, fontSize: 10),
                    ),
                    if (isText) ...[
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 14, color: Colors.white54),
                        onPressed: () => _editTextOverlay(o),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: 'Edit style',
                      ),
                    ],
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 14, color: Colors.redAccent),
                      onPressed: () {
                        _timeline.removeOverlay(o.id);
                        setState(() {});
                      },
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
                ),
              );
            }),
          ],
          if (selected != null &&
              selectedTextSpec != null &&
              _timeline.selectedOverlayId != null) ...[
            const SizedBox(height: 8),
            VideoTextOverlayEditPanel(
              key: ValueKey(_timeline.selectedOverlayId),
              spec: selectedTextSpec,
              onChanged: (spec) {
                _updateTextOverlay(_timeline.selectedOverlayId!, spec);
                setState(() {});
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTrimmerRow() {
    final selectionLabel =
        '${_formatDuration((_startSec * 1000).round())} → '
        '${_formatDuration((_endSec * 1000).round())}';
    final durationSec = (_player?.mediaInfo?.durationMs.toInt() ?? 0) / 1000.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Trim Duration: $selectionLabel', style: const TextStyle(color: Colors.white70, fontSize: 12)),
              if (_loadingFilmstrip)
                const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
            ],
          ),
          const SizedBox(height: 8),
          FilmstripTrimmer(
            thumbPaths: _filmstripPaths,
            durationSeconds: durationSec,
            startSeconds: _startSec,
            endSeconds: _endSec,
            onRangeChanged: _onRangeChanged,
          ),
        ],
      ),
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
