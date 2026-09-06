import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:media_forge/media_forge.dart' as mf;
import 'package:pixel_surface/pixel_surface.dart';
import 'package:path/path.dart' as p;

import 'capabilities.dart';
import 'diagnostics.dart';
import 'media_source.dart';
import 'player_value.dart';
import 'texture_presenter.dart';
import 'track_info.dart';

/// Creates engine instances. Overridable in tests with fakes.
typedef MediaForgeEngineFactory = Future<mf.MediaPlaybackEngine> Function({
  required int textureHandle,
  required BigInt maxQueueSize,
  required int previewMaxEdge,
});

Future<mf.MediaPlaybackEngine> _defaultEngineFactory({
  required int textureHandle,
  required BigInt maxQueueSize,
  required int previewMaxEdge,
}) =>
    mf.MediaPlaybackEngine.newInstance(
      textureId: textureHandle,
      maxQueueSize: maxQueueSize,
      previewMaxEdge: previewMaxEdge,
    );

/// Player states beyond [MediaForgePlayerValue] for event streams.
enum MediaForgeEventType {
  opened,
  playing,
  paused,
  completed,
  buffering,
  error,
  disposed,
}

/// Player event broadcast on [MediaForgePlayerController.events].
@immutable
class MediaForgeEvent {
  const MediaForgeEvent(this.type, {this.message});
  final MediaForgeEventType type;
  final String? message;
}

/// Production-ready player controller.
///
/// ```dart
/// final controller = MediaForgePlayerController();
/// await controller.open(MediaForgeMedia.network('http://127.0.0.1:8080/stream'));
/// await controller.play();
/// ```
///
/// Layering: this controller drives `media_forge` (engine) and presents via
/// `pixel_surface` (through [MediaForgeTexturePresenter]). It never decodes
/// or fetches bytes itself.
class MediaForgePlayerController extends ValueNotifier<MediaForgePlayerValue>
    with WidgetsBindingObserver {
  MediaForgePlayerController({
    int? textureHandle,
    this.maxQueueSize = 2000,
    this.previewMaxEdge = 1080,
    this.autoPlay = false,
    this.looping = false,
    MediaForgeEngineFactory engineFactory = _defaultEngineFactory,
  })  : textureHandle = textureHandle ?? (0x4D465000 + Random().nextInt(0xFFFF)),
        _engineFactory = engineFactory,
        super(MediaForgePlayerValue.uninitialized) {
    _presenter = MediaForgeTexturePresenter(textureHandle: this.textureHandle);
  }

  /// Stable GPU texture handle for the controller lifetime.
  final int textureHandle;

  /// Engine packet-queue cap forwarded to `MediaPlaybackEngine.newInstance`.
  final int maxQueueSize;

  /// Decode-side max edge (1080 keeps the 64-frame queue cap in Rust).
  final int previewMaxEdge;

  final bool autoPlay;
  bool looping;

  final MediaForgeEngineFactory _engineFactory;
  late final MediaForgeTexturePresenter _presenter;

  mf.MediaPlaybackEngine? _engine;
  MediaForgeMedia? _media;
  MediaForgeMedia? get media => _media;

  MediaForgeTexturePresenter get presenter => _presenter;

  final StreamController<MediaForgeEvent> _events =
      StreamController<MediaForgeEvent>.broadcast();
  Stream<MediaForgeEvent> get events => _events.stream;

  final StreamController<MediaForgeDiagnostics> _diagnostics =
      StreamController<MediaForgeDiagnostics>.broadcast();
  Stream<MediaForgeDiagnostics> get diagnostics => _diagnostics.stream;

  MediaForgeDiagnostics? _lastDiagnostics;
  MediaForgeDiagnostics? get lastDiagnostics => _lastDiagnostics;

  Timer? _diagTimer;
  bool _vsyncScheduled = false;
  bool _tickInFlight = false;
  bool _disposed = false;
  int _seekGeneration = 0;

  /// Monotonic seek counter (useful for tests/debugging).
  int get seekGeneration => _seekGeneration;

  // FPS counters on the vsync loop.
  int _presentedSinceTick = 0;
  int _decodedPtsChanges = 0;
  int _lastDecodedPts = -1;
  int _droppedFrames = 0;
  DateTime _fpsWindowStart = DateTime.now();
  double _presentedFps = 0;
  double _decodedFps = 0;

  bool get _engineReady => _engine != null && value.isInitialized;

  // ---------------------------------------------------------------- open ---

  /// Open [media], replacing any current source.
  Future<void> open(MediaForgeMedia media, {bool play = false}) async {
    if (_disposed) throw StateError('Controller is disposed');
    _emit(const MediaForgeEvent(MediaForgeEventType.buffering));
    debugPrint('[MediaForgePlayer] open kind=${media.runtimeType}');
    try {
      await _ensureEngine();
      await _engine!.stop();
      await _presenter.reset();

      final target = await _resolveTarget(media);
      debugPrint('[MediaForgePlayer] opening target=$target');
      await _engine!.openFile(path: target);
      final durationMs = (await _engine!.getDurationMs()).toInt();
      debugPrint(
          '[MediaForgePlayer] opened duration=${durationMs}ms target=$target');

      _media = media;
      _seekGeneration++;
      _presenter.onSeek();
      value = value.copyWith(
        isInitialized: true,
        clearError: true,
        duration: Duration(milliseconds: durationMs),
        position: Duration.zero,
        buffered: Duration.zero,
        isCompleted: false,
        // v1 engine exposes a single best audio/video stream; track
        // discovery APIs exist but report empty until the engine adds
        // stream listing (see README gap table).
        audioTracks: const [],
        subtitleTracks: const [],
        selectedAudioTrackId: null,
        selectedSubtitleTrackId: null,
      );
      _emit(const MediaForgeEvent(MediaForgeEventType.opened));
      _startLoops();
      if (play || autoPlay) {
        await this.play();
      }
    } catch (e, st) {
      debugPrint('[MediaForgePlayer] open failed: $e\n$st');
      value = value.copyWith(
        errorDescription: e.toString(),
        isInitialized: false,
      );
      _emit(MediaForgeEvent(MediaForgeEventType.error, message: '$e'));
      rethrow;
    }
  }

  /// Resolve a [MediaForgeMedia] to an engine path/URL.
  ///
  /// Files pass through; network URLs are handed to FFmpeg directly so
  /// seeks become HTTP Range requests; assets are staged to temp.
  @visibleForTesting
  Future<String> resolveTargetForTest(MediaForgeMedia media) =>
      _resolveTarget(media);

  Future<String> _resolveTarget(MediaForgeMedia media) async {
    switch (media) {
      case MediaForgeFile(:final path):
        final f = File(path);
        if (!await f.exists()) {
          throw ArgumentError('Local file not found: $path');
        }
        return path;
      case MediaForgeNetwork(:final url, :final headers):
        final uri = Uri.tryParse(url);
        if (uri == null ||
            !(uri.scheme == 'http' || uri.scheme == 'https')) {
          throw ArgumentError('Network source must be http(s): $url');
        }
        if (headers.isNotEmpty) {
          // v1 engine has no header plumbing; log loudly so PeerStream
          // auth headers are not silently dropped from debugging.
          debugPrint(
            '[MediaForgePlayer] network headers pending engine open_url '
            'count=${headers.length} url=$url',
          );
        }
        return url;
      case MediaForgeAsset(:final assetKey):
        return _stageAsset(assetKey);
    }
  }

  Future<String> _stageAsset(String assetKey) async {
    final data = await rootBundle.load(assetKey);
    final dir = Directory.systemTemp;
    final out =
        File(p.join(dir.path, 'media_forge_player_${assetKey.hashCode}'));
    await out.writeAsBytes(data.buffer.asUint8List(), flush: true);
    debugPrint('[MediaForgePlayer] asset staged $assetKey → ${out.path}');
    return out.path;
  }

  Future<void> _ensureEngine() async {
    if (_engine != null) return;
    WidgetsBinding.instance.addObserver(this);
    _engine = await _engineFactory(
      textureHandle: textureHandle,
      maxQueueSize: BigInt.from(maxQueueSize),
      previewMaxEdge: previewMaxEdge,
    );
    debugPrint('[MediaForgePlayer] engine ready handle=$textureHandle');
  }

  // ------------------------------------------------------------- transport ---

  Future<void> play() async {
    if (_disposed || !_engineReady) return;
    try {
      await _engine!.start();
      value = value.copyWith(
          isPlaying: true, isCompleted: false, clearError: true);
      _startLoops();
      _emit(const MediaForgeEvent(MediaForgeEventType.playing));
      debugPrint('[MediaForgePlayer] play');
    } catch (e, st) {
      debugPrint('[MediaForgePlayer] play failed: $e\n$st');
      value = value.copyWith(errorDescription: e.toString());
      _emit(MediaForgeEvent(MediaForgeEventType.error, message: '$e'));
      rethrow;
    }
  }

  Future<void> pause() async {
    if (_disposed || !_engineReady) return;
    await _engine!.pause();
    value = value.copyWith(isPlaying: false);
    _emit(const MediaForgeEvent(MediaForgeEventType.paused));
    debugPrint('[MediaForgePlayer] pause pos=${value.position.inMilliseconds}ms');
  }

  /// Pause + reset position to zero (engine `stop`).
  Future<void> stop() async {
    if (_disposed || _engine == null) return;
    await _engine!.stop();
    value = value.copyWith(isPlaying: false, position: Duration.zero);
    _emit(const MediaForgeEvent(MediaForgeEventType.paused));
    debugPrint('[MediaForgePlayer] stop');
  }

  /// Accurate seek. Keeps the GPU texture, clears PTS dedupe.
  Future<void> seek(Duration position) async {
    if (_disposed || !_engineReady) return;
    final clamped = position.inMilliseconds.clamp(
        0,
        value.duration.inMilliseconds == 0
            ? position.inMilliseconds
            : value.duration.inMilliseconds);
    final target = Duration(milliseconds: clamped);
    final wasPlaying = value.isPlaying;
    debugPrint('[MediaForgePlayer] seek target=${target.inMilliseconds}ms');
    _seekGeneration++;
    value = value.copyWith(position: target, isBuffering: true);
    try {
      await _engine!.seek(timeMs: BigInt.from(target.inMilliseconds));
      _presenter.onSeek();
      _lastDecodedPts = -1;
      if (wasPlaying) await _engine!.start();
      value = value.copyWith(isBuffering: false, isCompleted: false);
    } catch (e, st) {
      debugPrint('[MediaForgePlayer] seek failed: $e\n$st');
      value = value.copyWith(
          isBuffering: false, errorDescription: e.toString());
      rethrow;
    }
  }

  Future<void> setPlaybackRate(double rate) async {
    if (_disposed || !_engineReady) return;
    final clamped = rate.clamp(0.25, 4.0);
    await _engine!.setRate(rate: clamped);
    value = value.copyWith(playbackRate: clamped);
    debugPrint('[MediaForgePlayer] rate=$clamped');
  }

  /// Master volume 0..1.
  ///
  /// v1 engine exposes mute switches only, so volume maps to
  /// `setMuted(volume == 0 || muted)`; the value is retained and applied
  /// to a future `setVolume` engine API without breaking changes.
  Future<void> setVolume(double volume) async {
    if (_disposed) return;
    final clamped = volume.clamp(0.0, 1.0);
    value = value.copyWith(volume: clamped);
    if (_engineReady) {
      final mute = clamped == 0 || value.isMuted;
      await _engine!.setMuted(muted: mute);
    }
    debugPrint('[MediaForgePlayer] volume=$clamped');
  }

  Future<void> setMuted(bool muted) async {
    if (_disposed) return;
    value = value.copyWith(isMuted: muted);
    if (_engineReady) {
      final effective = muted || value.volume == 0;
      await _engine!.setMuted(muted: effective);
    }
    debugPrint('[MediaForgePlayer] muted=$muted');
  }

  /// Mute only the embedded (source) audio, keeping overlays audible.
  Future<void> setEmbeddedAudioMuted(bool muted) async {
    if (_disposed || !_engineReady) return;
    await _engine!.setSourceMuted(muted: muted);
    debugPrint('[MediaForgePlayer] embeddedMuted=$muted');
  }

  // ---------------------------------------------------------------- tracks ---

  /// Select an audio track by id. Stored locally in v1; the engine plays
  /// its single best stream until stream switching lands (logged).
  Future<void> selectAudioTrack(int? id) async {
    if (id != null &&
        value.audioTracks.isNotEmpty &&
        value.audioTracks.every((t) => t.id != id)) {
      throw RangeError('Unknown audio track id=$id');
    }
    value = value.copyWith(selectedAudioTrackId: id);
    debugPrint('[MediaForgePlayer] audio track selected id=$id '
        '(engine switch pending stream-listing support)');
  }

  /// Select a subtitle track by id (`null` = off). Rendering is a v1 gap:
  /// the selection is retained for UI state; no overlay is drawn yet.
  Future<void> selectSubtitleTrack(int? id) async {
    if (id != null &&
        value.subtitleTracks.isNotEmpty &&
        value.subtitleTracks.every((t) => t.id != id)) {
      throw RangeError('Unknown subtitle track id=$id');
    }
    value = value.copyWith(selectedSubtitleTrackId: id);
    debugPrint('[MediaForgePlayer] subtitle track selected id=$id '
        '(rendering pending; embedded/external demux not in engine yet)');
  }

  /// Register an external (sidecar) subtitle file for UI state.
  /// Returns the synthetic track id. Rendering follows in a later release.
  Future<int> addExternalSubtitle(Uri uri, {String? language}) async {
    final id = 1000 + value.subtitleTracks.length;
    final track = MediaForgeSubtitleTrack(
      id: id,
      language: language,
      label: uri.pathSegments.isEmpty ? '$uri' : uri.pathSegments.last,
      isEmbedded: false,
      externalUri: uri,
    );
    value = value.copyWith(
        subtitleTracks: [...value.subtitleTracks, track]);
    debugPrint('[MediaForgePlayer] external subtitle added id=$id uri=$uri');
    return id;
  }

  // ------------------------------------------------------- presentation ------

  void _startLoops() {
    _diagTimer ??= Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _diagnosticsTick(),
    );
    if (!_vsyncScheduled) {
      _vsyncScheduled = true;
      SchedulerBinding.instance.scheduleFrameCallback(_onVsync);
      SchedulerBinding.instance.scheduleFrame();
    }
  }

  void _onVsync(Duration timestamp) {
    if (_disposed) {
      _vsyncScheduled = false;
      return;
    }
    if (!value.isPlaying) {
      // Idle: keep one scheduled callback so play() resumes instantly
      // without re-registering observers.
      SchedulerBinding.instance.scheduleFrameCallback(_onVsync);
      return;
    }
    _presentationTick();
    SchedulerBinding.instance.scheduleFrameCallback(_onVsync);
    SchedulerBinding.instance.scheduleFrame();
  }

  /// Vsync-driven presentation: follows decoder PTS, never a Dart Timer.
  Future<void> _presentationTick() async {
    final engine = _engine;
    if (engine == null || _tickInFlight || _disposed) return;
    if (!value.isPlaying) return;
    _tickInFlight = true;
    try {
      final pts = await _presenter.presentNext(engine);
      if (pts >= 0) {
        _presentedSinceTick++;
        final size = _presenter.frameSize.value;
        if (size.width > 0 &&
            (size.width.toInt() != value.videoWidth ||
                size.height.toInt() != value.videoHeight)) {
          value = value.copyWith(
            videoWidth: size.width.toInt(),
            videoHeight: size.height.toInt(),
          );
        }
      } else if (value.isPlaying) {
        _droppedFrames++;
      }
      _updateFpsWindow();
    } catch (e) {
      debugPrint('[MediaForgePlayer] presentation tick failed: $e');
    } finally {
      _tickInFlight = false;
    }
  }

  void _updateFpsWindow() {
    final now = DateTime.now();
    final elapsed = now.difference(_fpsWindowStart).inMilliseconds / 1000.0;
    if (elapsed >= 1.0) {
      _presentedFps = _presentedSinceTick / elapsed;
      _decodedFps = _decodedPtsChanges / elapsed;
      _presentedSinceTick = 0;
      _decodedPtsChanges = 0;
      _fpsWindowStart = now;
    }
  }

  Future<void> _diagnosticsTick() async {
    final engine = _engine;
    if (engine == null || _disposed || !value.isInitialized) return;
    try {
      final snap = await engine.getDiagnostics();
      final mediaMs = snap.mediaTimeMs.toInt();
      final audioMs = snap.audioClockMs.toInt();
      final presentedMs = snap.presentedPtsMs.toInt();
      final decodedMs = snap.latestDecodedPtsMs.toInt();
      if (decodedMs != _lastDecodedPts) {
        _decodedPtsChanges++;
        _lastDecodedPts = decodedMs;
      }
      final vq = snap.videoFramesInQueue.toInt();
      final vpq = snap.videoPacketsInQueue.toInt();
      final buffering = value.isPlaying && vq == 0;
      if (buffering && !value.isBuffering) {
        _emit(const MediaForgeEvent(MediaForgeEventType.buffering));
      }
      // Forward buffer estimate: ~40ms per queued video frame+packet.
      final bufferedMs = mediaMs + (vq + vpq) * 40;
      final durationMs = value.duration.inMilliseconds;
      value = value.copyWith(
        position: Duration(milliseconds: mediaMs),
        buffered: Duration(
            milliseconds: durationMs == 0
                ? bufferedMs
                : bufferedMs.clamp(0, durationMs)),
        isBuffering: buffering,
      );
      final caps = await MediaForgeCapabilities.probe();
      final diag = MediaForgeDiagnostics(
        state: snap.state,
        mediaTimeMs: mediaMs,
        audioClockMs: audioMs,
        wallClockMs: snap.wallClockMs.toInt(),
        latestDecodedPtsMs: decodedMs,
        presentedPtsMs: presentedMs,
        avDriftMs: snap.avDriftMs.toInt(),
        videoPacketsInQueue: vpq,
        audioPacketsInQueue: snap.audioPacketsInQueue.toInt(),
        videoFramesInQueue: vq,
        audioFramesInQueue: snap.audioFramesInQueue.toInt(),
        decodedFps: _decodedFps,
        presentedFps: _presentedFps,
        droppedFrames: _droppedFrames,
        bufferedDurationMs: (bufferedMs - mediaMs).clamp(0, 1 << 31),
        activeDecoder: caps.decoderLabelFor(),
        hwDecode: caps.hwDecodeAvailable,
        networkBytesRead: null, // pending engine socket stats
      );
      _lastDiagnostics = diag;
      if (!_diagnostics.isClosed) _diagnostics.add(diag);

      // Completion: engine reports Ended via trim, or clock hit duration.
      if (snap.state == mf.PlaybackState.ended ||
          (durationMs > 0 && mediaMs >= durationMs - 200)) {
        if (!value.isCompleted) {
          if (looping) {
            debugPrint('[MediaForgePlayer] loop → seek 0');
            await seek(Duration.zero);
            await play();
          } else {
            value = value.copyWith(isPlaying: false, isCompleted: true);
            _emit(const MediaForgeEvent(MediaForgeEventType.completed));
            debugPrint('[MediaForgePlayer] completed');
          }
        }
      }
    } catch (e) {
      debugPrint('[MediaForgePlayer] diagnostics tick failed: $e');
    }
  }

  // ------------------------------------------------------------------ misc ---

  void _emit(MediaForgeEvent e) {
    if (!_events.isClosed) _events.add(e);
  }

  @override
  void didHaveMemoryPressure() {
    debugPrint('[MediaForgePlayer] memory pressure → flushPools');
    unawaited(MediaForgeTexturePresenter.handleMemoryPressure());
  }

  /// Native pool stats for diagnostics overlays / tests.
  Future<String?> debugStats() async {
    final stats = await GpuTextureRegistry.debugStats();
    return stats?.toString();
  }

  /// Async release. Named `release` because [ValueNotifier.dispose] is sync;
  /// this closes streams, stops the engine and flushes GPU pools.
  Future<void> release() async {
    if (_disposed) return;
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _diagTimer?.cancel();
    _diagTimer = null;
    try {
      await _engine?.stop();
    } catch (e) {
      debugPrint('[MediaForgePlayer] dispose stop failed: $e');
    }
    _engine = null;
    _presenter.dispose();
    await MediaForgeTexturePresenter.handleMemoryPressure();
    _emit(const MediaForgeEvent(MediaForgeEventType.disposed));
    await _events.close();
    await _diagnostics.close();
    debugPrint('[MediaForgePlayer] disposed handle=$textureHandle');
  }

  @override
  void dispose() {
    unawaited(release());
    super.dispose();
  }
}
