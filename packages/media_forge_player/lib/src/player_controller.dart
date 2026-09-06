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
      final network = media is MediaForgeNetwork ? media : null;
      if (network != null) {
        await _engine!.openUrl(
          url: target,
          options: mf.NetworkOptions(
            headers: network.headers,
            userAgent: network.userAgent,
            timeoutMs: BigInt.from(network.timeout.inMilliseconds),
            reconnect: network.reconnect,
          ),
        );
      } else {
        await _engine!.openFile(path: target);
      }
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
        audioTracks: const [],
        subtitleTracks: const [],
        videoTracks: const [],
        clearAudioSelection: true,
        clearSubtitleSelection: true,
        clearVideoSelection: true,
      );
      await _refreshTracks();
      // Push retained audio state into the fresh engine session.
      if (_engineReady) {
        await _engine!.setVolume(volume: value.volume);
        await _engine!.setMuted(muted: value.isMuted);
        await _engine!.setSubtitlesEnabled(enabled: value.subtitlesEnabled);
        await _engine!.setSubtitleDelayMs(
          delayMs: value.subtitleDelay.inMilliseconds,
        );
      }
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
          debugPrint(
            '[MediaForgePlayer] network open headers=${headers.keys.join(',')} '
            'url=$url',
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

  /// Master volume 0..1 — engine-side gain (source + overlays).
  Future<void> setVolume(double volume) async {
    if (_disposed) return;
    final clamped = volume.clamp(0.0, 1.0);
    value = value.copyWith(volume: clamped);
    if (_engineReady) {
      await _engine!.setVolume(volume: clamped);
    }
    debugPrint('[MediaForgePlayer] volume=$clamped');
  }

  Future<void> setMuted(bool muted) async {
    if (_disposed) return;
    value = value.copyWith(isMuted: muted);
    if (_engineReady) {
      await _engine!.setMuted(muted: muted);
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

  static String? _nonEmpty(String s) => s.isEmpty ? null : s;

  /// Rebuild track lists from `listStreams()` (called after every open).
  /// External (sidecar) tracks already in [value] are preserved.
  Future<void> _refreshTracks() async {
    final engine = _engine;
    if (engine == null) return;
    late final List<mf.MediaStreamInfo> streams;
    try {
      streams = await engine.listStreams();
    } catch (e) {
      debugPrint('[MediaForgePlayer] listStreams failed: $e');
      return;
    }
    final audio = <MediaForgeAudioTrack>[];
    final subs = <MediaForgeSubtitleTrack>[];
    final videos = <MediaForgeVideoTrack>[];
    for (final s in streams) {
      switch (s.kind) {
        case mf.StreamKind.audio:
          audio.add(MediaForgeAudioTrack(
            id: s.index,
            language: _nonEmpty(s.language),
            label: _nonEmpty(s.title) ??
                _nonEmpty(s.language) ??
                'Audio ${s.index}',
            codec: s.codecName,
            bitrate: s.bitrate.toInt(),
            isDefault: s.isDefault,
            isForced: s.isForced,
            channels: s.channels == 0 ? null : s.channels,
            sampleRate: s.sampleRate == 0 ? null : s.sampleRate,
          ));
        case mf.StreamKind.subtitle:
          subs.add(MediaForgeSubtitleTrack(
            id: s.index,
            language: _nonEmpty(s.language),
            label: _nonEmpty(s.title) ??
                _nonEmpty(s.language) ??
                'Subtitle ${s.index}',
            codec: s.codecName,
            bitrate: s.bitrate.toInt(),
            isDefault: s.isDefault,
            isForced: s.isForced,
          ));
        case mf.StreamKind.video:
          videos.add(MediaForgeVideoTrack(
            id: s.index,
            language: _nonEmpty(s.language),
            label: _nonEmpty(s.title) ?? 'Video ${s.index}',
            codec: s.codecName,
            bitrate: s.bitrate.toInt(),
            isDefault: s.isDefault,
            isForced: s.isForced,
            width: s.width == 0 ? null : s.width,
            height: s.height == 0 ? null : s.height,
          ));
      }
    }
    final external =
        value.subtitleTracks.where((t) => !t.isEmbedded).toList();
    value = value.copyWith(
      audioTracks: audio,
      subtitleTracks: [...subs, ...external],
      videoTracks: videos,
      clearVideoSelection: value.selectedVideoTrackId != null &&
          videos.every((t) => t.id != value.selectedVideoTrackId),
    );
    debugPrint('[MediaForgePlayer] tracks audio=${audio.length} '
        'subtitle=${subs.length} video=${videos.length} '
        'external=${external.length}');
  }

  /// Select a video track by stream index. Switches the live pipeline.
  Future<void> selectVideoTrack(int? id) async {
    if (id != null &&
        value.videoTracks.isNotEmpty &&
        value.videoTracks.every((t) => t.id != id)) {
      throw RangeError('Unknown video track id=$id');
    }
    if (id != null && _engineReady) {
      try {
        await _engine!.selectVideoStream(index: id);
      } catch (e, st) {
        debugPrint('[MediaForgePlayer] selectVideoStream failed: $e\n$st');
        rethrow;
      }
    }
    value = value.copyWith(selectedVideoTrackId: id);
    debugPrint('[MediaForgePlayer] video track selected id=$id');
  }

  /// Select an audio track by stream index. Switches the live decoder.
  Future<void> selectAudioTrack(int? id) async {
    if (id != null &&
        value.audioTracks.isNotEmpty &&
        value.audioTracks.every((t) => t.id != id)) {
      throw RangeError('Unknown audio track id=$id');
    }
    if (id != null && _engineReady) {
      try {
        await _engine!.selectAudioStream(index: id);
      } catch (e, st) {
        debugPrint('[MediaForgePlayer] selectAudioStream failed: $e\n$st');
        rethrow;
      }
    }
    value = value.copyWith(selectedAudioTrackId: id);
    debugPrint('[MediaForgePlayer] audio track selected id=$id');
  }

  /// Select an embedded subtitle track (`null` = off). Switches live.
  Future<void> selectSubtitleTrack(int? id) async {
    if (id != null &&
        value.subtitleTracks.isNotEmpty &&
        value.subtitleTracks.every((t) => t.id != id)) {
      throw RangeError('Unknown subtitle track id=$id');
    }
    if (_engineReady) {
      final embedded = id == null ||
          value.subtitleTracks.any((t) => t.id == id && t.isEmbedded);
      try {
        if (id != null && embedded) {
          await _engine!.selectSubtitleStream(index: id);
        } else if (id == null) {
          // Off (or external-only): stop embedded forwarding.
          await _engine!.selectSubtitleStream(index: -1);
        }
      } catch (e, st) {
        debugPrint('[MediaForgePlayer] selectSubtitleStream failed: $e\n$st');
        rethrow;
      }
    }
    value = value.copyWith(selectedSubtitleTrackId: id);
    debugPrint('[MediaForgePlayer] subtitle track selected id=$id');
  }

  /// Register an external (sidecar) subtitle file/URL and decode it into
  /// the shared cue queue. Returns the synthetic track id.
  Future<int> addExternalSubtitle(Uri uri, {String? language}) async {
    final id = 1000 + value.subtitleTracks.length;
    if (_engineReady) {
      try {
        await _engine!.openExternalSubtitle(pathOrUrl: '$uri');
      } catch (e, st) {
        debugPrint('[MediaForgePlayer] openExternalSubtitle failed: $e\n$st');
        rethrow;
      }
    }
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

  /// Stop the sidecar session and drop external tracks from state.
  Future<void> closeExternalSubtitles() async {
    if (_engineReady) {
      try {
        await _engine!.closeExternalSubtitle();
      } catch (e) {
        debugPrint('[MediaForgePlayer] closeExternalSubtitle failed: $e');
      }
    }
    final selectedGone = value.selectedSubtitleTrackId != null &&
        value.subtitleTracks.any((t) =>
            t.id == value.selectedSubtitleTrackId && !t.isEmbedded);
    value = value.copyWith(
      subtitleTracks:
          value.subtitleTracks.where((t) => t.isEmbedded).toList(),
      clearSubtitleSelection: selectedGone,
    );
  }

  /// Active cue text at [position] (`null` when none).
  Future<String?> subtitleTextAt(Duration position) async {
    if (!_engineReady) return null;
    try {
      return await _engine!
          .pollSubtitleText(timeMs: BigInt.from(position.inMilliseconds));
    } catch (e) {
      debugPrint('[MediaForgePlayer] pollSubtitleText failed: $e');
      return null;
    }
  }

  /// User subtitle delay (signed; applied by the engine at cue ingest).
  Future<void> setSubtitleDelay(Duration delay) async {
    value = value.copyWith(subtitleDelay: delay);
    if (_engineReady) {
      await _engine!.setSubtitleDelayMs(delayMs: delay.inMilliseconds);
    }
    debugPrint(
        '[MediaForgePlayer] subtitle delay=${delay.inMilliseconds}ms');
  }

  /// Enable/disable cue delivery (decoding continues while disabled).
  Future<void> setSubtitlesEnabled(bool enabled) async {
    value = value.copyWith(subtitlesEnabled: enabled);
    if (_engineReady) {
      await _engine!.setSubtitlesEnabled(enabled: enabled);
    }
    debugPrint('[MediaForgePlayer] subtitles enabled=$enabled');
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
      // Forward buffer estimate prefers the engine's decoded-ahead figure;
      // fall back to queue-depth heuristic when it is zero.
      final engineBufferedMs = snap.bufferedDurationMs.toInt();
      final bufferedMs = engineBufferedMs > 0
          ? mediaMs + engineBufferedMs
          : mediaMs + (vq + vpq) * 40;
      final durationMs = value.duration.inMilliseconds;
      value = value.copyWith(
        position: Duration(milliseconds: mediaMs),
        buffered: Duration(
            milliseconds: durationMs == 0
                ? bufferedMs
                : bufferedMs.clamp(0, durationMs)),
        isBuffering: buffering,
      );
      MediaForgeCapabilities? caps;
      try {
        caps = await MediaForgeCapabilities.probe();
      } catch (e) {
        debugPrint('[MediaForgePlayer] capabilities probe failed: $e');
      }
      final engineDecoder = snap.activeVideoDecoder;
      final fallbackDecoder = caps?.decoderLabelFor() ?? 'unknown';
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
        bufferedDurationMs: engineBufferedMs,
        activeDecoder: engineDecoder.isEmpty || engineDecoder == 'none'
            ? fallbackDecoder
            : engineDecoder,
        hwDecode: snap.hwDecodeActive,
        networkBytesRead: snap.bytesRead.toInt(),
        bytesRead: snap.bytesRead.toInt(),
        readBitrateBps: snap.readBitrateBps.toInt(),
        decoderDroppedFrames: snap.droppedVideoFrames.toInt(),
        subtitleCuesPending: snap.subtitleCuesPending.toInt(),
        selectedVideoIndex: snap.selectedVideoIndex,
        selectedAudioIndex: snap.selectedAudioIndex,
        selectedSubtitleIndex: snap.selectedSubtitleIndex,
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

  /// Test hook: run one diagnostics tick on demand.
  @visibleForTesting
  Future<void> diagnosticsTickForTest() => _diagnosticsTick();

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
