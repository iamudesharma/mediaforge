import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_video_processor/flutter_video_processor.dart'
    show MediaInfo, VideoProcessor;
import 'package:rust_media_runtime/rust_media_runtime.dart'
    hide PlaybackState;

import 'playback_backend.dart';

/// Simple data class for audio clip info needed by overlay sync.
class AudioClipInfo {
  const AudioClipInfo({
    required this.id,
    required this.sourcePath,
    required this.volume,
    required this.timelineStartMs,
    required this.durationMs,
    required this.sourceStartMs,
    this.muted = false,
  });

  final String id;
  final String sourcePath;
  final double volume;
  final int timelineStartMs;
  final int durationMs;
  final int sourceStartMs;
  final bool muted;
}

/// Wraps [MediaPlaybackEngine] (rust_media_runtime) behind [PlaybackBackend].
///
/// Uses FFmpeg demuxing + HW decode + cpal audio output in Rust.
/// Presents video frames via GPU texture (zero-copy on Apple).
class RustBackend extends PlaybackBackend {
  RustBackend({
    required this.textureHandle,
    this.previewMaxEdge = 720,
  });

  final int textureHandle;
  final int previewMaxEdge;

  MediaPlaybackEngine? _engine;
  MediaPlaybackPresenter? _presenter;
  MediaPlaybackDrive? _drive;
  PlaybackDiagnostics? _lastDiagnostics;

  MediaPlaybackEngine? get engine => _engine;
  MediaPlaybackPresenter? get presenter => _presenter;
  MediaPlaybackDrive? get drive => _drive;
  PlaybackDiagnostics? get lastDiagnostics => _lastDiagnostics;

  MediaInfo? _mediaInfo;
  bool _isPlaying = false;
  bool _disposed = false;
  int _trimEndMs = 0;

  /// Map of audio clip ID → Rust overlay ID for real-time mixing.
  final Map<String, int> _overlayIds = {};

  /// Map of audio clip ID → last synced parameters to detect timing changes.
  final Map<String, _OverlaySchedule> _overlaySchedules = {};

  /// Guards against concurrent syncOverlayTracks calls creating duplicate overlays.
  bool _syncInProgress = false;
  List<AudioClipInfo>? _pendingSyncClips;

  Timer? _diagnosticsTimer;
  Timer? _presentationTimer;

  /// Diagnostics timer (500ms) — runs whenever the engine is open.
  /// Keeps position/state info fresh for the UI even when paused.
  void _startDiagnosticsTimer() {
    _diagnosticsTimer?.cancel();
    _diagnosticsTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _pollDiagnostics(),
    );
  }

  /// Presentation timer (16ms) — only runs while actively playing.
  /// Pulls decoded frames from the Rust presenter and uploads to GPU texture.
  void _startPresentationTimer() {
    if (_presentationTimer?.isActive == true) return;
    _presentationTimer = Timer.periodic(
      const Duration(milliseconds: 16),
      (_) => _presentationTick(),
    );
  }

  void _stopPresentationTimer() {
    _presentationTimer?.cancel();
    _presentationTimer = null;
  }

  void _stopAllTimers() {
    _diagnosticsTimer?.cancel();
    _diagnosticsTimer = null;
    _presentationTimer?.cancel();
    _presentationTimer = null;
  }

  /// Immediately present one frame (useful after seek to show target frame).
  Future<void> _presentOneFrame() async {
    if (_disposed) return;
    await _presentationTick();
  }

  Future<void> _pollDiagnostics() async {
    final drive = _drive;
    if (drive == null || _disposed) return;
    try {
      final snap = await drive.diagnosticsTick();
      _lastDiagnostics = snap;
      if (!_disposed) notifyListeners();
    } catch (_) {}
  }

  Future<void> _presentationTick() async {
    final drive = _drive;
    if (drive == null || _disposed) return;
    try {
      await drive.presentationTick();
    } catch (_) {}
  }

  // ── PlaybackBackend ──

  @override
  Future<void> open(String path) async {
    await close();

    // Probe media info for resolution/codec display
    try {
      _mediaInfo = await VideoProcessor.getMediaInfo(path);
    } catch (_) {
      _mediaInfo = null;
    }

    // Create engine (textureId 0 is fine — GpuPresenter is a no-op;
    // actual presentation goes through MediaPlaybackPresenter → GpuTextureRegistry)
    final engine = await MediaPlaybackEngine.newInstance(
      textureId: 0,
      maxQueueSize: BigInt.from(2000),
      previewMaxEdge: previewMaxEdge,
    );
    _engine = engine;

    // Create presenter with the real texture handle for GPU upload
    _presenter = MediaPlaybackPresenter(textureHandle: textureHandle);
    _drive = MediaPlaybackDrive(
      engine: engine,
      presenter: _presenter!,
    );

    // Open file → starts demuxer thread
    await engine.openFile(path: path);

    // Set trim range to full duration
    final dur = await engine.getDurationMs();
    _trimEndMs = dur.toInt();

    _isPlaying = false;
    _startDiagnosticsTimer();
    notifyListeners();
  }

  /// Switch to a different file (e.g. muxed preview) without recreating the engine.
  Future<void> reopenFile(String path) async {
    final engine = _engine;
    if (engine == null) return;

    try {
      await engine.stop();
      _stopPresentationTimer();
      _isPlaying = false;

      // Probe new file info
      try {
        _mediaInfo = await VideoProcessor.getMediaInfo(path);
      } catch (_) {}

      // Open new file → starts demuxer thread
      await engine.openFile(path: path);

      // Update trim range to new duration
      final dur = await engine.getDurationMs();
      _trimEndMs = dur.toInt();

      notifyListeners();
    } catch (e) {
      debugPrint('[RustBackend] reopenFile failed: $e');
    }
  }

  @override
  Future<void> close() async {
    _stopAllTimers();
    final engine = _engine;
    final presenter = _presenter;
    _engine = null;
    _presenter = null;
    _drive = null;
    _mediaInfo = null;
    _isPlaying = false;
    _lastDiagnostics = null;

    if (engine != null) {
      try {
        await engine.stop();
      } catch (_) {}
    }
    try {
      presenter?.dispose();
    } catch (_) {}
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  Future<void> play() async {
    final engine = _engine;
    if (engine == null) return;
    try {
      await engine.start();
      _isPlaying = true;
      _startPresentationTimer();
      notifyListeners();
    } catch (e) {
      debugPrint('[RustBackend] play failed: $e');
    }
  }

  @override
  void pause() {
    final engine = _engine;
    if (engine == null) return;
    try {
      engine.pause();
      _isPlaying = false;
      _stopPresentationTimer();
      notifyListeners();
    } catch (e) {
      debugPrint('[RustBackend] pause failed: $e');
    }
  }

  @override
  Future<void> seekTo(Duration position) async {
    final engine = _engine;
    if (engine == null) return;
    try {
      await engine.seek(timeMs: BigInt.from(position.inMilliseconds));
      _presenter?.onSeek();
      // Present one frame immediately to show the seek target.
      // If paused, stop the presentation timer after (no more frames coming).
      // If playing, the running timer will keep pulling new frames.
      await _presentOneFrame();
      if (!_isPlaying) {
        _stopPresentationTimer();
      }
    } catch (e) {
      debugPrint('[RustBackend] seek failed: $e');
    }
  }

  @override
  void setTrimRange({int? startMs, int? endMs}) {
    final engine = _engine;
    if (engine == null) return;
    final start = startMs ?? 0;
    final end = endMs ?? _trimEndMs;
    _trimEndMs = end;
    engine.setTrimRange(startMs: BigInt.from(start), endMs: BigInt.from(end));
    notifyListeners();
  }

  @override
  Future<void> setEmbeddedAudioMuted(bool muted) async {
    final engine = _engine;
    if (engine == null) return;
    try {
      await engine.setMuted(muted: muted);
    } catch (e) {
      debugPrint('[RustBackend] setEmbeddedAudioMuted failed: $e');
    }
  }

  @override
  Future<void> setPlaybackRate(double rate) async {
    final engine = _engine;
    if (engine == null) return;
    try {
      await engine.setRate(rate: rate);
    } catch (e) {
      debugPrint('[RustBackend] setPlaybackRate failed: $e');
    }
  }

  // ── Overlay audio track management (Rust real-time mixing) ──

  /// Add an overlay audio track for real-time mixing in the Rust engine.
  /// Returns the Rust overlay ID, or -1 on error.
  Future<int> addOverlayAudio({
    required String clipId,
    required String path,
    required double volume,
    required int timelineStartMs,
    required int durationMs,
    required int sourceStartMs,
  }) async {
    final engine = _engine;
    if (engine == null) return -1;
    try {
      final id = await engine.addOverlayAudio(
        path: path,
        volume: volume,
        timelineStartMs: BigInt.from(timelineStartMs),
        durationMs: BigInt.from(durationMs),
        sourceStartMs: BigInt.from(sourceStartMs),
      );
      final overlayId = id.toInt();
      _overlayIds[clipId] = overlayId;
      debugPrint('[RustBackend] addOverlayAudio clipId=$clipId overlayId=$overlayId startMs=$timelineStartMs dur=$durationMs srcStart=$sourceStartMs');
      return overlayId;
    } catch (e) {
      debugPrint('[RustBackend] addOverlayAudio failed: $e');
      return -1;
    }
  }

  /// Remove an overlay audio track by its clip ID.
  Future<void> removeOverlayAudio(String clipId) async {
    final engine = _engine;
    final overlayId = _overlayIds.remove(clipId);
    _overlaySchedules.remove(clipId);
    if (engine == null || overlayId == null) return;
    try {
      await engine.removeOverlayAudio(id: BigInt.from(overlayId));
      debugPrint('[RustBackend] removeOverlayAudio clipId=$clipId overlayId=$overlayId');
    } catch (e) {
      debugPrint('[RustBackend] removeOverlayAudio failed: $e');
    }
  }

  /// Update volume for an overlay audio track.
  Future<void> setOverlayVolume(String clipId, double volume) async {
    final engine = _engine;
    final overlayId = _overlayIds[clipId];
    if (engine == null || overlayId == null) return;
    try {
      await engine.setOverlayVolume(id: BigInt.from(overlayId), volume: volume);
    } catch (e) {
      debugPrint('[RustBackend] setOverlayVolume failed: $e');
    }
  }

  /// Sync all overlay tracks from the timeline. Removes overlays no longer
  /// in the timeline, adds new ones, and updates volumes.
  /// Only works when the Rust backend is active.
  Future<void> syncOverlayTracks(List<AudioClipInfo> clips) async {
    // Guard against concurrent calls: _onTimelineUpdated fires frequently
    // and without await, so multiple syncs can interleave creating duplicate
    // overlays that accumulate and mix simultaneously (garbled audio).
    if (_syncInProgress) {
      _pendingSyncClips = clips;
      return;
    }
    _syncInProgress = true;
    try {
      await _doSyncOverlayTracks(clips);
    } finally {
      _syncInProgress = false;
      // If more updates arrived while we were syncing, run again
      final pending = _pendingSyncClips;
      _pendingSyncClips = null;
      if (pending != null) {
        unawaited(syncOverlayTracks(pending));
      }
    }
  }

  Future<void> _doSyncOverlayTracks(List<AudioClipInfo> clips) async {
    // Build set of current clip IDs
    final currentIds = clips.map((c) => c.id).toSet();

    // Remove overlays that are no longer in the timeline
    final toRemove = _overlayIds.keys
        .where((id) => !currentIds.contains(id))
        .toList();
    for (final id in toRemove) {
      await removeOverlayAudio(id);
    }

    // Add or update overlays
    for (final clip in clips) {
      if (clip.muted) {
        // Muted clips should not be mixed
        if (_overlayIds.containsKey(clip.id)) {
          await removeOverlayAudio(clip.id);
        }
        continue;
      }

      final existingSchedule = _overlaySchedules[clip.id];
      final needsRecreate = existingSchedule != null &&
          (existingSchedule.timelineStartMs != clip.timelineStartMs ||
           existingSchedule.durationMs != clip.durationMs ||
           existingSchedule.sourceStartMs != clip.sourceStartMs ||
           existingSchedule.sourcePath != clip.sourcePath);

      if (needsRecreate) {
        await removeOverlayAudio(clip.id);
      }

      if (_overlayIds.containsKey(clip.id)) {
        // Update volume for existing overlay
        await setOverlayVolume(clip.id, clip.volume);
      } else {
        // Add new overlay
        final overlayId = await addOverlayAudio(
          clipId: clip.id,
          path: clip.sourcePath,
          volume: clip.volume,
          timelineStartMs: clip.timelineStartMs,
          durationMs: clip.durationMs,
          sourceStartMs: clip.sourceStartMs,
        );
        if (overlayId != -1) {
          _overlaySchedules[clip.id] = _OverlaySchedule(
            timelineStartMs: clip.timelineStartMs,
            durationMs: clip.durationMs,
            sourceStartMs: clip.sourceStartMs,
            sourcePath: clip.sourcePath,
          );
        }
      }
    }
  }

  @override
  bool get isOpen => _engine != null;

  @override
  bool get isPlaying => _isPlaying;

  @override
  int get positionMs => _lastDiagnostics?.mediaTimeMs ?? 0;

  @override
  int get durationMs => _mediaInfo?.durationMs.toInt() ?? _trimEndMs;

  @override
  MediaInfo? get mediaInfo => _mediaInfo;

  @override
  double get aspectRatio {
    final info = _mediaInfo;
    if (info == null || info.width <= 0 || info.height <= 0) return 16 / 9;
    return info.width.toDouble() / info.height.toDouble();
  }

  @override
  int get previewWidth => _mediaInfo?.width ?? 0;

  @override
  int get previewHeight => _mediaInfo?.height ?? 0;

  // ── Lifecycle ──

  @override
  void dispose() {
    _disposed = true;
    _stopAllTimers();
    final engine = _engine;
    final presenter = _presenter;
    _engine = null;
    _presenter = null;
    _drive = null;
    if (engine != null) {
      engine.stop();
    }
    presenter?.dispose();
    super.dispose();
  }
}

class _OverlaySchedule {
  const _OverlaySchedule({
    required this.timelineStartMs,
    required this.durationMs,
    required this.sourceStartMs,
    required this.sourcePath,
  });

  final int timelineStartMs;
  final int durationMs;
  final int sourceStartMs;
  final String sourcePath;
}
