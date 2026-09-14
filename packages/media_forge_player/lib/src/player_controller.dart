import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:media_forge/media_forge.dart' as mf;
import 'package:pixel_surface/pixel_surface.dart';
import 'package:path/path.dart' as p;

import 'buffered_range.dart';
import 'capabilities.dart';
import 'diagnostics.dart';
import 'media_source.dart';
import 'network_profile.dart';
import 'player_configuration.dart';
import 'player_value.dart';
import 'texture_presenter.dart';
import 'track_info.dart';
import 'video_enhancement.dart';

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

  /// First frame presented since open (§7).
  firstFramePresented,

  /// Seek started (carries monotonic generation) (§7).
  seekStarted,

  /// Latest seek generation reached a valid presented frame near target (§7).
  seekSettled,

  /// A lifecycle transition. This is deliberately source-agnostic: hosts can
  /// correlate it with their own cache/transport diagnostics without making
  /// MediaForge depend on a torrent implementation.
  stateChanged,
}

/// Controller lifecycle. Rebuffering never performs transport work: it holds
/// the last presented frame while the existing source continues to refill.
enum MediaForgePlayerRuntimeState {
  idle,
  opening,
  playing,
  paused,
  preloading,
  rebuffering,
  seeking,
  ended,
  failed,
  disposed,
}

/// Player event broadcast on [MediaForgePlayerController.events].
@immutable
class MediaForgeEvent {
  const MediaForgeEvent(
    this.type, {
    this.message,
    this.generation = -1,
    this.positionMs,
    this.latencyMs,
  });
  final MediaForgeEventType type;
  final String? message;

  /// Monotonic seek/open generation for seekStarted/seekSettled (-1 = n/a).
  final int generation;

  /// Associated media position in ms (seek target / presented PTS).
  final int? positionMs;

  /// Measured latency in ms (first-frame / seek-settled).
  final int? latencyMs;
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
///
/// New configured construction is additive:
/// ```dart
/// MediaForgePlayerController(
///   configuration: MediaForgePlayerConfiguration(
///     decodeResolution: MediaForgeDecodeResolution.native,
///   ),
/// )
/// ```
class MediaForgePlayerController extends ValueNotifier<MediaForgePlayerValue>
    with WidgetsBindingObserver {
  MediaForgePlayerController({
    int? textureHandle,
    this.maxQueueSize = 2000,
    this.previewMaxEdge = 1080,
    this.autoPlay = false,
    this.looping = false,
    MediaForgeEngineFactory engineFactory = _defaultEngineFactory,
    this.configuration,
  })  : textureHandle = textureHandle ?? (0x4D465000 + Random().nextInt(0xFFFF)),
        _engineFactory = engineFactory,
        super(MediaForgePlayerValue.uninitialized) {
    _presenter = MediaForgeTexturePresenter(textureHandle: this.textureHandle);
  }

  /// Configured construction (additive/non-breaking).
  factory MediaForgePlayerController.withConfiguration({
    int? textureHandle,
    required MediaForgePlayerConfiguration configuration,
    bool autoPlay = false,
    bool looping = false,
    MediaForgeEngineFactory engineFactory = _defaultEngineFactory,
  }) {
    return MediaForgePlayerController(
      textureHandle: textureHandle,
      maxQueueSize: configuration.resolveMaxQueueSize(),
      previewMaxEdge: configuration.resolvePreviewMaxEdge(),
      autoPlay: autoPlay,
      looping: looping,
      engineFactory: engineFactory,
      configuration: configuration,
    );
  }

  /// Stable GPU texture handle for the controller lifetime.
  final int textureHandle;

  /// Engine packet-queue cap forwarded to `MediaPlaybackEngine.newInstance`.
  ///
  /// When [configuration] is present, the effective value comes from
  /// [MediaForgePlayerConfiguration.resolveMaxQueueSize] (byte-budget
  /// derived, bounded). The raw field is preserved for backward compat.
  final int maxQueueSize;

  /// Decode-side max edge (1080 keeps the 64-frame queue cap in Rust).
  ///
  /// Legacy `previewMaxEdge == 0 → 1080` behaviour is preserved. When
  /// [configuration] is present, [effectivePreviewMaxEdge] is used instead.
  final int previewMaxEdge;

  final bool autoPlay;
  bool looping;

  /// Explicit configuration (null = legacy constructor behaviour).
  final MediaForgePlayerConfiguration? configuration;

  /// Effective longest edge forwarded to the engine.
  ///
  /// Preserves `previewMaxEdge == 0 → 1080` for legacy consumers. Native
  /// configuration resolves to the preservation ceiling (never a public
  /// magic sentinel — the enum is the API).
  int get effectivePreviewMaxEdge {
    final cfg = configuration;
    if (cfg != null) return cfg.resolvePreviewMaxEdge();
    if (previewMaxEdge == 0) return kLegacyDefaultPreviewEdge;
    return previewMaxEdge;
  }

  /// Effective packet-count cap forwarded to the engine (legacy bridge).
  int get effectiveMaxQueueSize {
    final cfg = configuration;
    if (cfg != null) return cfg.resolveMaxQueueSize();
    return maxQueueSize;
  }

  /// Effective diagnostics cadence.
  Duration get effectiveDiagnosticsCadence =>
      configuration?.diagnosticsCadence ?? const Duration(milliseconds: 500);

  final MediaForgeEngineFactory _engineFactory;
  late final MediaForgeTexturePresenter _presenter;

  mf.MediaPlaybackEngine? _engine;
  MediaForgeMedia? _media;
  MediaForgeMedia? get media => _media;

  MediaForgeTexturePresenter get presenter => _presenter;

  // ---- experimental GPU video enhancement ---------------------------------
  //
  // The requested mode is player state, so it survives source changes and is
  // re-applied whenever a new engine is created. The native side owns the
  // target plan, the quality ladder and all GPU work — Dart only routes the
  // frame pointer.
  VideoEnhancementMode _videoEnhancementMode = VideoEnhancementMode.defaultMode;

  /// Probed GPU enhancement capabilities (`null` until the first probe).
  ///
  /// Separate from `value` because the probe is a one-off device query, not
  /// per-frame state. Not disposed on release: settings UI may still be
  /// mounted during a route transition.
  final ValueNotifier<VideoEnhancementCapabilities?> enhancementCapabilities =
      ValueNotifier<VideoEnhancementCapabilities?>(null);

  VideoEnhancementStatus? _videoEnhancementStatus;
  int _videoEnhancementMaxOutputEdge = 0;
  int? _videoEnhancementViewportWidth;
  int? _videoEnhancementViewportHeight;
  bool _videoEnhancementProbed = false;
  int _enhancedFrames = 0;
  int _enhancementBypassedFrames = 0;

  /// Requested enhancement mode (default [VideoEnhancementMode.off]).
  VideoEnhancementMode get videoEnhancementMode => _videoEnhancementMode;

  /// Latest probe result, or `null` before [probeVideoEnhancement] runs.
  ///
  /// Listen to [enhancementCapabilities] to react to the probe completing.
  VideoEnhancementCapabilities? get videoEnhancementCapabilities =>
      enhancementCapabilities.value;

  /// Latest enhancement diagnostics, or `null` before the first frame.
  VideoEnhancementStatus? get videoEnhancementStatus => _videoEnhancementStatus;

  /// True when this device can run GPU enhancement.
  ///
  /// Before the first [probeVideoEnhancement] this reports the compiled-in
  /// capability, which is optimistic on Apple and false everywhere else.
  bool get supportsVideoEnhancement =>
      enhancementCapabilities.value?.supported ??
      _videoEnhancementStatus?.supported ??
      false;

  /// Modes this device will actually run (always includes
  /// [VideoEnhancementMode.off]).
  List<VideoEnhancementMode> get supportedVideoEnhancementModes =>
      enhancementCapabilities.value?.supportedModes ??
      const [VideoEnhancementMode.off];

  /// Frames presented through the GPU enhancement stage since [open].
  int get enhancedFrameCount => _enhancedFrames;

  /// Frames where enhancement was skipped (unsupported plan, deadline
  /// pressure, backend failure) since [open].
  int get enhancementBypassedFrameCount => _enhancementBypassedFrames;

  final StreamController<MediaForgeEvent> _events =
      StreamController<MediaForgeEvent>.broadcast();
  Stream<MediaForgeEvent> get events => _events.stream;

  final StreamController<MediaForgeDiagnostics> _diagnostics =
      StreamController<MediaForgeDiagnostics>.broadcast();
  Stream<MediaForgeDiagnostics> get diagnostics => _diagnostics.stream;

  MediaForgeDiagnostics? _lastDiagnostics;
  MediaForgeDiagnostics? get lastDiagnostics => _lastDiagnostics;

  /// Explicit lifecycle state for embedding applications. This intentionally
  /// does not use external cached ranges as a readiness signal.
  final ValueNotifier<MediaForgePlayerRuntimeState> runtimeState =
      ValueNotifier(MediaForgePlayerRuntimeState.idle);

  void _setRuntimeState(MediaForgePlayerRuntimeState next,
      {String? reason}) {
    if (runtimeState.value == next) return;
    runtimeState.value = next;
    _emit(MediaForgeEvent(MediaForgeEventType.stateChanged,
        message: reason ?? next.name));
    debugPrint('[MediaForgePlayer] state=${next.name}'
        '${reason == null ? '' : ' reason=$reason'}');
  }

  // ---- buffered / preloaded ranges -------------------------------------
  //
  // Layering (do not confuse):
  // * compressed packet read-ahead (network/demux, bounded by byte/duration
  //   budgets) — the only thing that may grow while paused;
  // * decoded frame queue (tiny: ~2–3 frames, never preloaded en masse);
  // * host-provided cached/downloaded ranges (generic, e.g. torrent cache).
  //
  // [bufferState] is the dedicated lightweight notifier for timeline
  // availability: listening to it never rebuilds the video texture (the
  // surface listens to the presenter, not to this).
  final ValueNotifier<MediaForgeBufferState> bufferState =
      ValueNotifier(MediaForgeBufferState.empty);

  List<MediaForgeBufferedRange> _externalBufferedRanges = const [];
  List<MediaForgeBufferedRange> _lastInternalRanges = const [];

  /// Host-provided cached/downloaded ranges (generic — never torrent or
  /// libtorrent types; this package must not import PeerStream).
  ///
  /// Set by the embedding app when it knows more than the engine (e.g. a
  /// localhost torrent stream whose pieces are already on disk). Merged
  /// (union, never double-counted) with engine read-ahead for display.
  List<MediaForgeBufferedRange> get externalBufferedRanges =>
      _externalBufferedRanges;

  /// Replace the host-provided cache ranges and refresh the merged view.
  ///
  /// Generic: pass any sparse/dense download cache as time ranges. Empty
  /// clears the external contribution.
  void setExternalBufferedRanges(List<MediaForgeBufferedRange> ranges) {
    _externalBufferedRanges = normalizeBufferedRanges(ranges);
    debugPrint(
        '[MediaForgePlayer] external buffered ranges=${_externalBufferedRanges.length}');
    _refreshMergedBufferState(
      position: value.position,
      duration: value.duration,
    );
  }

  /// Clear host-provided ranges (same as setting empty).
  void clearExternalBufferedRanges() =>
      setExternalBufferedRanges(const []);

  Timer? _diagTimer;
  bool _vsyncScheduled = false;
  bool _tickInFlight = false;
  bool _disposed = false;
  int _seekGeneration = 0;

  // Rebuffer hysteresis avoids toggling the UI during a single diagnostic
  // interval. It never invokes seek/open/stop and therefore cannot restart a
  // localhost Range request or flush source queues during starvation.
  DateTime? _starvationStartedAt;
  DateTime? _recoveryReadyStartedAt;
  bool _rebufferingLatched = false;
  static const _starvationEnterDelay = Duration(milliseconds: 750);
  static const _rebufferExitDelay = Duration(milliseconds: 350);
  static const _recoveryPacketFloor = Duration(milliseconds: 250);

  /// Monotonic seek counter (useful for tests/debugging).
  int get seekGeneration => _seekGeneration;

  // ---- frame-ready pump state (§5) ----
  bool _suspended = false;
  bool get isSuspended => _suspended;

  // ---- §6 drop accounting (true drops only; empty polls never count) ----
  int _presentedSinceTick = 0;
  int _decodedPtsChanges = 0;
  int _lastDecodedPts = -1;

  /// Actual presented frames since open (never bridge-call count).
  int _presentedFrames = 0;
  int get presentedFrameCount => _presentedFrames;

  /// Bridge presentation calls since open.
  int get bridgeCallCount => _presenter.bridgeCallCount;

  /// Queue-overflow drops (engine-reported, split when available).
  int _queueOverflowDrops = 0;
  int get queueOverflowDrops => _queueOverflowDrops;

  /// Catch-up drops (engine-reported, split when available).
  int _catchupDrops = 0;
  int get catchupDrops => _catchupDrops;

  /// Legacy total (kept for backward compat; equals overflow+catchup+decoder).
  int get droppedFrames =>
      _queueOverflowDrops + _catchupDrops + _decoderDrops;
  int _decoderDrops = 0;
  int get decoderDrops => _decoderDrops;

  DateTime _fpsWindowStart = DateTime.now();
  double _presentedFps = 0;
  double _decodedFps = 0;

  // ---- §7 first-frame / seek latency ----
  DateTime? _openStartedAt;
  DateTime? _firstDecodedAt;
  DateTime? _firstPresentedAt;

  int? _pendingSeekGeneration;
  int? _pendingSeekTargetMs;
  DateTime? _pendingSeekStartedAt;
  int _lastSeekSettledGeneration = -1;
  int? _lastSeekLatencyMs;
  DateTime? _lastSeekStartedAt;
  DateTime? _lastSeekSettledAt;

  int? get firstFrameLatencyMs => _openStartedAt != null && _firstPresentedAt != null
      ? _firstPresentedAt!.difference(_openStartedAt!).inMilliseconds
      : null;
  int? get lastSeekLatencyMs => _lastSeekLatencyMs;
  int get lastSeekSettledGeneration => _lastSeekSettledGeneration;

  // ---- §11 probe ----
  int? _lastProbeDurationMs;
  int? get lastProbeDurationMs => _lastProbeDurationMs;

  // ---- §12 interrupt / generation ----
  int _sourceGeneration = 0;
  int get sourceGeneration => _sourceGeneration;

  // ---- §14 subtitle efficiency ----
  DateTime? _lastSubtitlePollAt;
  String? _lastSubtitleText;
  Duration? _lastSubtitlePosition;
  int _subtitlePollCount = 0;
  @visibleForTesting
  int get subtitlePollCountForTest => _subtitlePollCount;

  // ---- §15 deterministic release ----
  Future<void>? _releaseFuture;
  bool get isReleased => _releaseFuture != null;
  Future<void>? get releaseFutureForTest => _releaseFuture;

  bool get _engineReady => _engine != null && value.isInitialized;

  // ---------------------------------------------------------------- open ---

  /// Open [media], replacing any current source.
  Future<void> open(MediaForgeMedia media, {bool play = false}) async {
    if (_releaseFuture != null) throw StateError('Controller is released');
    if (_disposed) throw StateError('Controller is disposed');
    _setRuntimeState(MediaForgePlayerRuntimeState.opening);
    _emit(const MediaForgeEvent(MediaForgeEventType.buffering));
    debugPrint('[MediaForgePlayer] open kind=${media.runtimeType}');
    final openStart = DateTime.now();
    _openStartedAt = openStart;
    _firstDecodedAt = null;
    _firstPresentedAt = null;
    _presentedFrames = 0;
    _queueOverflowDrops = 0;
    _catchupDrops = 0;
    _decoderDrops = 0;
    _pendingSeekGeneration = null;
    _enhancedFrames = 0;
    _enhancementBypassedFrames = 0;
    _videoEnhancementStatus = null;
    _starvationStartedAt = null;
    _recoveryReadyStartedAt = null;
    _rebufferingLatched = false;
    final openGen = ++_sourceGeneration;
    try {
      await _ensureEngine();
      if (openGen != _sourceGeneration || _releaseFuture != null) {
        // Stale open superseded by a newer source/dispose (§12).
        return;
      }
      await _engine!.stop();
      await _presenter.reset();

      final target = await _resolveTarget(media);
      if (openGen != _sourceGeneration || _releaseFuture != null) return;
      debugPrint('[MediaForgePlayer] opening target=$target');
      final network = media is MediaForgeNetwork ? media : null;
      final profile = MediaForgeNetworkProfile.inferFor(
        media,
        configured: configuration?.networkProfile,
        callerTimeout: network != null && network.timeout != Duration.zero
            ? network.timeout
            : null,
        callerReconnect: network != null && network.reconnect ? true : null,
      );
      // Torrent-localhost forces reconnect; direct HTTP honours caller/config.
      final bool resolvedReconnect;
      if (network == null) {
        resolvedReconnect = false;
      } else if (profile.name == 'torrent_localhost') {
        resolvedReconnect = true;
      } else {
        resolvedReconnect = network.reconnect || profile.reconnect;
      }
      final resolvedTimeout = network != null &&
              network.timeout != Duration.zero
          ? network.timeout
          : profile.timeout;
      if (network != null) {
        await _engine!.openUrl(
          url: target,
          options: mf.NetworkOptions(
            headers: network.headers,
            userAgent: network.userAgent,
            timeoutMs: BigInt.from(resolvedTimeout.inMilliseconds),
            reconnect: resolvedReconnect,
          ),
        );
      } else {
        await _engine!.openFile(path: target);
      }
      if (openGen != _sourceGeneration || _releaseFuture != null) return;
      _lastProbeDurationMs =
          DateTime.now().difference(openStart).inMilliseconds;
      var durationMs = (await _engine!.getDurationMs()).toInt();
      debugPrint(
          '[MediaForgePlayer] opened duration=${durationMs}ms target=$target '
          'profile=${profile.name} probe=${_lastProbeDurationMs}ms');
      // §11 fast-probe fallback: if metadata is incomplete (no duration and
      // no streams), the engine is asked once more — the native layer
      // retries with the larger probe budget. Fake engines in tests always
      // report a duration so this is a no-op there.
      if (durationMs <= 0) {
        try {
          final streams = await _engine!.listStreams();
          if (streams.isEmpty) {
            debugPrint('[MediaForgePlayer] metadata incomplete → '
                'single fallback probe with larger budget');
            if (network != null) {
              await _engine!.openUrl(
                url: target,
                options: mf.NetworkOptions(
                  headers: network.headers,
                  userAgent: network.userAgent,
                  timeoutMs: BigInt.from(resolvedTimeout.inMilliseconds),
                  reconnect: resolvedReconnect,
                ),
              );
            } else {
              await _engine!.openFile(path: target);
            }
            durationMs = (await _engine!.getDurationMs()).toInt();
          }
        } catch (_) {
          // Keep the original open result; diagnostics will show duration 0.
        }
      }

      _media = media;
      _seekGeneration++;
      _presenter.onSeek();
      _lastInternalRanges = const [];
      bufferState.value = MediaForgeBufferState.empty;
      // A new source replaces sidecar subtitles: the engine closes the
      // external session during open, so the Dart track list and the cue
      // cache are cleared here to stay in step (a stale external id must
      // never survive into the new session). Re-add with
      // [addExternalSubtitle] after the open completes.
      _clearSubtitleTextCache();
      value = value.copyWith(
        isInitialized: true,
        clearError: true,
        duration: Duration(milliseconds: durationMs),
        position: Duration.zero,
        buffered: Duration.zero,
        bufferedPosition: Duration.zero,
        bufferedRanges: const [],
        bufferedAhead: Duration.zero,
        isRebuffering: false,
        isPreloading: false,
        packetBufferedDuration: Duration.zero,
        packetBufferedBytes: 0,
        decodedVideoFrames: 0,
        decodedFrameMemoryBytes: 0,
        isCompleted: false,
        audioTracks: const [],
        subtitleTracks: const [],
        videoTracks: const [],
        clearAudioSelection: true,
        clearSubtitleSelection: true,
        clearVideoSelection: true,
        firstFramePresented: false,
        activeSeekGeneration: _seekGeneration,
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
      _setRuntimeState(
        play || autoPlay
            ? MediaForgePlayerRuntimeState.playing
            : MediaForgePlayerRuntimeState.paused,
        reason: 'opened',
      );
      _startLoops();
      if (play || autoPlay) {
        await this.play();
      }
    } catch (e, st) {
      if (openGen != _sourceGeneration) return;
      debugPrint('[MediaForgePlayer] open failed: $e\n$st');
      value = value.copyWith(
        errorDescription: e.toString(),
        isInitialized: false,
      );
      _emit(MediaForgeEvent(MediaForgeEventType.error, message: '$e'));
      _setRuntimeState(MediaForgePlayerRuntimeState.failed, reason: 'open');
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
      maxQueueSize: BigInt.from(effectiveMaxQueueSize),
      previewMaxEdge: effectivePreviewMaxEdge,
    );
    debugPrint('[MediaForgePlayer] engine ready handle=$textureHandle '
        'maxQueue=${effectiveMaxQueueSize} edge=${effectivePreviewMaxEdge} '
        'native=${configuration?.isNative ?? false}');
    // Enhancement state lives on the controller, so it survives source
    // changes and is re-applied to every new engine (still no media reopen:
    // this runs before the first open).
    await _applyEnhancementSettings();
  }

  // ------------------------------------------------------------- transport ---

  Future<void> play() async {
    if (_releaseFuture != null || _disposed || !_engineReady) return;
    if (_suspended) {
      // Resume the pump on explicit play while suspended is cleared elsewhere.
      _suspended = false;
    }
    try {
      await _engine!.start();
      value = value.copyWith(
          isPlaying: true, isCompleted: false, clearError: true);
      _startLoops();
      _emit(const MediaForgeEvent(MediaForgeEventType.playing));
      _setRuntimeState(MediaForgePlayerRuntimeState.playing);
      debugPrint('[MediaForgePlayer] play');
    } catch (e, st) {
      debugPrint('[MediaForgePlayer] play failed: $e\n$st');
      value = value.copyWith(errorDescription: e.toString());
      _emit(MediaForgeEvent(MediaForgeEventType.error, message: '$e'));
      _setRuntimeState(MediaForgePlayerRuntimeState.failed, reason: 'play');
      rethrow;
    }
  }

  Future<void> pause() async {
    if (_releaseFuture != null || _disposed || !_engineReady) return;
    await _engine!.pause();
    value = value.copyWith(isPlaying: false);
    _emit(const MediaForgeEvent(MediaForgeEventType.paused));
    _setRuntimeState(MediaForgePlayerRuntimeState.paused);
    debugPrint('[MediaForgePlayer] pause pos=${value.position.inMilliseconds}ms');
  }

  /// Pause + reset position to zero (engine `stop`).
  Future<void> stop() async {
    if (_releaseFuture != null || _disposed || _engine == null) return;
    await _engine!.stop();
    value = value.copyWith(isPlaying: false, position: Duration.zero);
    _emit(const MediaForgeEvent(MediaForgeEventType.paused));
    _setRuntimeState(MediaForgePlayerRuntimeState.idle, reason: 'stopped');
    debugPrint('[MediaForgePlayer] stop');
  }

  /// Accurate seek. Keeps the GPU texture, clears PTS dedupe.
  ///
  /// Emits [MediaForgeEventType.seekStarted] immediately with a monotonic
  /// generation; [MediaForgeEventType.seekSettled] fires when the latest
  /// generation reaches a valid presented frame near the target — never
  /// purely on demux seek success. Stale generations are rejected.
  Future<void> seek(Duration position) async {
    if (_releaseFuture != null || _disposed || !_engineReady) return;
    final clamped = position.inMilliseconds.clamp(
        0,
        value.duration.inMilliseconds == 0
            ? position.inMilliseconds
            : value.duration.inMilliseconds);
    final target = Duration(milliseconds: clamped);
    final wasPlaying = value.isPlaying;
    debugPrint('[MediaForgePlayer] seek target=${target.inMilliseconds}ms');
    _seekGeneration++;
    _sourceGeneration++;
    final gen = _seekGeneration;
    _pendingSeekGeneration = gen;
    _pendingSeekTargetMs = target.inMilliseconds;
    _pendingSeekStartedAt = DateTime.now();
    _lastSeekStartedAt = _pendingSeekStartedAt;
    value = value.copyWith(
      position: target,
      isBuffering: true,
      activeSeekGeneration: gen,
    );
    _emit(MediaForgeEvent(
      MediaForgeEventType.seekStarted,
      generation: gen,
      positionMs: target.inMilliseconds,
    ));
    _setRuntimeState(MediaForgePlayerRuntimeState.seeking);
    try {
      await _engine!.seek(timeMs: BigInt.from(target.inMilliseconds));
      if (gen != _seekGeneration || _releaseFuture != null) {
        // Superseded by a newer seek — stale completion rejected (§20).
        debugPrint('[MediaForgePlayer] seek gen=$gen superseded, ignoring');
        return;
      }
      _presenter.onSeek();
      _lastDecodedPts = -1;
      if (wasPlaying) await _engine!.start();
      value = value.copyWith(isBuffering: false, isCompleted: false);
      // seekSettled is emitted from the presentation pump once a frame near
      // the target is actually presented (see _maybeSettleSeek). If no frame
      // arrives promptly (e.g. fake engines in tests), settle
      // optimistically on the next diagnostics tick — still gated on the
      // latest generation.
    } catch (e, st) {
      debugPrint('[MediaForgePlayer] seek failed: $e\n$st');
      value = value.copyWith(
          isBuffering: false, errorDescription: e.toString());
      _setRuntimeState(MediaForgePlayerRuntimeState.failed, reason: 'seek');
      rethrow;
    }
  }

  void _maybeSettleSeek(int presentedPtsMs) {
    final gen = _pendingSeekGeneration;
    if (gen == null) return;
    if (gen != _seekGeneration) {
      // Stale seek — reject completion.
      _pendingSeekGeneration = null;
      return;
    }
    final target = _pendingSeekTargetMs ?? presentedPtsMs;
    // Near-target tolerance: 500 ms (local) — presentation must be close to
    // the requested target, not merely demux success.
    if ((presentedPtsMs - target).abs() <= 500) {
      final started = _pendingSeekStartedAt;
      final now = DateTime.now();
      final latency =
          started != null ? now.difference(started).inMilliseconds : 0;
      _pendingSeekGeneration = null;
      _lastSeekSettledGeneration = gen;
      _lastSeekLatencyMs = latency;
      _lastSeekSettledAt = now;
      value = value.copyWith(lastSeekSettledGeneration: gen);
      _emit(MediaForgeEvent(
        MediaForgeEventType.seekSettled,
        generation: gen,
        positionMs: presentedPtsMs,
        latencyMs: latency,
      ));
      debugPrint(
          '[MediaForgePlayer] seek settled gen=$gen pts=${presentedPtsMs}ms latency=${latency}ms');
    }
  }

  Future<void> setPlaybackRate(double rate) async {
    if (_releaseFuture != null || _disposed || !_engineReady) return;
    final clamped = rate.clamp(0.25, 4.0);
    await _engine!.setRate(rate: clamped);
    value = value.copyWith(playbackRate: clamped);
    debugPrint('[MediaForgePlayer] rate=$clamped');
  }

  /// Master volume 0..1 — engine-side gain (source + overlays).
  Future<void> setVolume(double volume) async {
    if (_releaseFuture != null || _disposed) return;
    final clamped = volume.clamp(0.0, 1.0);
    value = value.copyWith(volume: clamped);
    if (_engineReady) {
      await _engine!.setVolume(volume: clamped);
    }
    debugPrint('[MediaForgePlayer] volume=$clamped');
  }

  Future<void> setMuted(bool muted) async {
    if (_releaseFuture != null || _disposed) return;
    value = value.copyWith(isMuted: muted);
    if (_engineReady) {
      await _engine!.setMuted(muted: muted);
    }
    debugPrint('[MediaForgePlayer] muted=$muted');
  }

  /// Mute only the embedded (source) audio, keeping overlays audible.
  Future<void> setEmbeddedAudioMuted(bool muted) async {
    if (_releaseFuture != null || _disposed || !_engineReady) return;
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
    // A fresh source auto-selects the embedded track the container flags as
    // forced (foreign-dialogue track) or default, so flagged subtitles show
    // without a manual pick. An existing selection — including the user's
    // explicit Off — is never overridden.
    final autoSelected = value.selectedSubtitleTrackId != null
        ? null
        : _flaggedSubtitleTrackId(subs, enabled: value.subtitlesEnabled);
    value = value.copyWith(
      audioTracks: audio,
      subtitleTracks: [...subs, ...external],
      videoTracks: videos,
      selectedSubtitleTrackId: autoSelected,
      clearVideoSelection: value.selectedVideoTrackId != null &&
          videos.every((t) => t.id != value.selectedVideoTrackId),
    );
    if (autoSelected != null) {
      try {
        await engine.selectSubtitleStream(index: autoSelected);
      } catch (e) {
        debugPrint('[MediaForgePlayer] auto subtitle select failed: $e');
      }
    }
    debugPrint('[MediaForgePlayer] tracks audio=${audio.length} '
        'subtitle=${subs.length} video=${videos.length} '
        'external=${external.length} autoSubtitle=$autoSelected');
  }

  /// The embedded track the container asks to be shown: forced first, then
  /// default. `null` when subtitles are switched off or nothing is flagged.
  static int? _flaggedSubtitleTrackId(
    List<MediaForgeSubtitleTrack> subs, {
    required bool enabled,
  }) {
    if (!enabled) return null;
    for (final t in subs) {
      if (t.isForced) return t.id;
    }
    for (final t in subs) {
      if (t.isDefault) return t.id;
    }
    return null;
  }

  /// Select a video track by stream index. Switches the live pipeline.
  Future<void> selectVideoTrack(int? id) async {
    if (_releaseFuture != null || _disposed) return;
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
    if (_releaseFuture != null || _disposed) return;
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

  /// Select a subtitle track by id (`null` = off). Switches live.
  ///
  /// Embedded ids switch the engine decoder; external (sidecar) ids are
  /// state-only because [addExternalSubtitle] already opened their session.
  /// Off stops embedded forwarding and hides *every* cue source
  /// deterministically: a sidecar session may keep decoding, but nothing is
  /// delivered until a track is selected again. Tear the session down with
  /// [closeExternalSubtitles] instead.
  Future<void> selectSubtitleTrack(int? id) async {
    if (_releaseFuture != null || _disposed) return;
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
    if (id != value.selectedSubtitleTrackId) _clearSubtitleTextCache();
    // `copyWith(selectedSubtitleTrackId: null)` means "keep", so Off needs
    // the explicit clear flag — otherwise the old track stays selected and
    // keeps being polled/rendered.
    value = value.copyWith(
      selectedSubtitleTrackId: id,
      clearSubtitleSelection: id == null,
    );
    debugPrint('[MediaForgePlayer] subtitle track selected id=$id');
  }

  /// Register an external (sidecar) subtitle file/URL and decode it into
  /// the shared cue queue. Returns the synthetic track id.
  ///
  /// `file:` and bare URIs are sent to the engine as local paths — FFmpeg's
  /// file protocol wants `/tmp/a.srt`, never `file:///tmp/a.srt`. http(s)
  /// URLs pass through verbatim so Range reads keep working.
  Future<int> addExternalSubtitle(Uri uri, {String? language}) async {
    if (_releaseFuture != null || _disposed) {
      throw StateError('Controller is released');
    }
    final target = _engineTargetForSubtitle(uri);
    final id = 1000 + value.subtitleTracks.length;
    if (_engineReady) {
      try {
        await _engine!.openExternalSubtitle(pathOrUrl: target);
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
    debugPrint('[MediaForgePlayer] external subtitle added id=$id '
        'target=$target');
    return id;
  }

  /// Engine target for a sidecar [uri]: `file:` and bare local paths are
  /// decoded to filesystem paths, everything else (http/https/… ) stays a
  /// string.
  static String _engineTargetForSubtitle(Uri uri) {
    if (uri.scheme == 'file' || (uri.scheme.isEmpty && uri.host.isEmpty)) {
      return uri.toFilePath();
    }
    return uri.toString();
  }

  /// Stop the sidecar session and drop external tracks from state.
  Future<void> closeExternalSubtitles() async {
    if (_releaseFuture != null || _disposed) return;
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
    if (selectedGone) _clearSubtitleTextCache();
    value = value.copyWith(
      subtitleTracks:
          value.subtitleTracks.where((t) => t.isEmbedded).toList(),
      clearSubtitleSelection: selectedGone,
    );
    debugPrint('[MediaForgePlayer] external subtitles closed '
        'tracks=${value.subtitleTracks.length}');
  }

  /// Drop cached cue text so a previous track/position can never leak into
  /// the next poll (the cache is served verbatim while suspended).
  void _clearSubtitleTextCache() {
    _lastSubtitleText = null;
    _lastSubtitlePosition = null;
    _lastSubtitlePollAt = null;
  }

  /// Active cue text at [position] (`null` when none).
  ///
  /// Gated by [MediaForgePlayerValue.hasActiveSubtitles] — the same rule the
  /// caption overlays use: subtitles enabled and a track selected. No bridge
  /// call when no track is active, when the engine is not ready, or when the
  /// same position is re-polled within the configured minimum interval
  /// (cue-boundary behaviour).
  Future<String?> subtitleTextAt(Duration position) async {
    if (_releaseFuture != null || _disposed) return null;
    // §14: never poll when disabled / no track selected. Checked before the
    // suspend shortcut so switching Off hides cues deterministically.
    if (!value.hasActiveSubtitles) return null;
    if (_suspended) return _lastSubtitleText;
    if (!_engineReady) return null;
    final now = DateTime.now();
    final minInterval = configuration?.subtitlePollMinimumInterval ??
        const Duration(milliseconds: 200);
    if (_lastSubtitlePollAt != null &&
        _lastSubtitlePosition == position &&
        now.difference(_lastSubtitlePollAt!) < minInterval) {
      // Same position re-polled within the minimum interval — serve the
      // cached text without a bridge call (cue-boundary behaviour).
      return _lastSubtitleText;
    }
    try {
      _subtitlePollCount++;
      final text = await _engine!
          .pollSubtitleText(timeMs: BigInt.from(position.inMilliseconds));
      _lastSubtitlePollAt = now;
      _lastSubtitleText = text;
      _lastSubtitlePosition = position;
      return text;
    } catch (e) {
      debugPrint('[MediaForgePlayer] pollSubtitleText failed: $e');
      return null;
    }
  }

  /// User subtitle delay (signed; applied by the engine at cue ingest).
  Future<void> setSubtitleDelay(Duration delay) async {
    if (_releaseFuture != null || _disposed) return;
    value = value.copyWith(subtitleDelay: delay);
    if (_engineReady) {
      await _engine!.setSubtitleDelayMs(delayMs: delay.inMilliseconds);
    }
    debugPrint(
        '[MediaForgePlayer] subtitle delay=${delay.inMilliseconds}ms');
  }

  /// Enable/disable cue delivery (decoding continues while disabled).
  Future<void> setSubtitlesEnabled(bool enabled) async {
    if (_releaseFuture != null || _disposed) return;
    if (!enabled) _clearSubtitleTextCache();
    value = value.copyWith(subtitlesEnabled: enabled);
    if (_engineReady) {
      await _engine!.setSubtitlesEnabled(enabled: enabled);
    }
    debugPrint('[MediaForgePlayer] subtitles enabled=$enabled');
  }

  // --------------------------------------------------- video enhancement -----

  /// Best answer available before the native GPU probe runs.
  ///
  /// Apple is the only platform with a backend today, so other platforms can
  /// answer honestly without touching the GPU at all.
  static VideoEnhancementCapabilities _platformDefaultCapabilities() {
    if (kIsWeb) return VideoEnhancementCapabilities.unsupported;
    final apple = defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.iOS;
    if (!apple) {
      return const VideoEnhancementCapabilities(
        supported: false,
        supportedModes: [VideoEnhancementMode.off],
        backend: 'none',
        maxOutputEdge: 0,
        reason: 'video enhancement backend is Apple-only in this release',
      );
    }
    return const VideoEnhancementCapabilities(
      supported: true,
      supportedModes: VideoEnhancementMode.values,
      backend: 'metal_wgpu',
      maxOutputEdge: 3840,
      reason: 'probe_pending',
    );
  }

  /// Probe GPU enhancement support for this device.
  ///
  /// Creates the native GPU pipeline on first call, so call it once during
  /// app/settings initialisation rather than per frame. Never throws: an
  /// unsupported device reports [VideoEnhancementCapabilities.unsupported].
  Future<VideoEnhancementCapabilities> probeVideoEnhancement() async {
    final engine = _engine;
    if (engine == null) {
      // Without an engine the compiled-in answer is all we can honestly give,
      // but it must still be published so UI can gate on it.
      final cached = enhancementCapabilities.value;
      if (cached != null) return cached;
      final provisional = _platformDefaultCapabilities();
      enhancementCapabilities.value = provisional;
      return provisional;
    }
    try {
      final caps = await engine.videoEnhancementCapabilities();
      final mapped = VideoEnhancementCapabilities(
        supported: caps.supported,
        supportedModes: caps.modes.map(VideoEnhancementMode.fromEngine).toList(),
        backend: caps.backend,
        maxOutputEdge: caps.maxOutputEdge,
        reason: caps.reason,
      );
      _videoEnhancementProbed = true;
      enhancementCapabilities.value = mapped;
      debugPrint('[MediaForgePlayer] videoEnhancement probe: $mapped');
      return mapped;
    } catch (e) {
      debugPrint('[MediaForgePlayer] videoEnhancement probe failed: $e');
      _videoEnhancementProbed = true;
      enhancementCapabilities.value = VideoEnhancementCapabilities.unsupported;
      return VideoEnhancementCapabilities.unsupported;
    }
  }

  /// Change the GPU enhancement mode.
  ///
  /// Applies to the next presented frame: no media reopen, no decoder
  /// restart, no queue flush, no seek. Selecting an unsupported mode leaves
  /// playback on the normal render path and reports the reason through
  /// [videoEnhancementStatus].
  ///
  /// Returns true when the device accepted the mode.
  Future<bool> setVideoEnhancementMode(VideoEnhancementMode mode) async {
    if (_releaseFuture != null || _disposed) return false;
    _videoEnhancementMode = mode;
    value = value.copyWith(videoEnhancementMode: mode);
    // The hook is installed only while a mode is active, so `off` costs
    // nothing on the presentation path — not even a bridge call.
    _presenter.enhancer = mode.isActive ? _enhanceFrame : null;
    final engine = _engine;
    if (engine == null) {
      debugPrint('[MediaForgePlayer] videoEnhancement=$mode (applied on open)');
      return true;
    }
    try {
      final accepted = await engine.setVideoEnhancementMode(
        mode: mode.toEngine,
      );
      debugPrint('[MediaForgePlayer] videoEnhancement=$mode accepted=$accepted');
      return accepted;
    } catch (e) {
      debugPrint('[MediaForgePlayer] videoEnhancement set failed: $e');
      return false;
    }
  }

  /// Display box in device pixels (logical size × devicePixelRatio).
  ///
  /// Drives the resolution-aware target: enhancement only upscales toward the
  /// display, never past it. Passing `(0, 0)` clears the hint. Safe to call
  /// during layout — it forwards asynchronously and never notifies listeners.
  void setVideoEnhancementViewport(double width, double height) {
    if (_releaseFuture != null || _disposed) return;
    final w = width.isFinite && width > 0 ? width.round() : 0;
    final h = height.isFinite && height > 0 ? height.round() : 0;
    if (_videoEnhancementViewportWidth == w &&
        _videoEnhancementViewportHeight == h) {
      return;
    }
    _videoEnhancementViewportWidth = w;
    _videoEnhancementViewportHeight = h;
    final engine = _engine;
    if (engine == null) return;
    unawaited(
      engine.setVideoEnhancementViewport(width: w, height: h).catchError((_) {}),
    );
  }

  /// Hard ceiling for the enhanced output longest edge (`0` = mode default).
  Future<void> setVideoEnhancementMaxOutputEdge(int edge) async {
    if (_releaseFuture != null || _disposed) return;
    _videoEnhancementMaxOutputEdge = edge < 0 ? 0 : edge;
    final engine = _engine;
    if (engine == null) return;
    await engine.setVideoEnhancementMaxOutputEdge(
      edge: _videoEnhancementMaxOutputEdge,
    );
  }

  /// Push the current requested mode / viewport / cap to a freshly created
  /// engine (called from [_ensureEngine]).
  Future<void> _applyEnhancementSettings() async {
    final engine = _engine;
    if (engine == null) return;
    _presenter.enhancer =
        _videoEnhancementMode.isActive ? _enhanceFrame : null;
    if (_videoEnhancementMaxOutputEdge > 0) {
      await engine.setVideoEnhancementMaxOutputEdge(
        edge: _videoEnhancementMaxOutputEdge,
      );
    }
    if (_videoEnhancementViewportWidth != null) {
      await engine.setVideoEnhancementViewport(
        width: _videoEnhancementViewportWidth!,
        height: _videoEnhancementViewportHeight ?? 0,
      );
    }
    if (!_videoEnhancementProbed) {
      await probeVideoEnhancement();
    }
    // Nothing to send while the mode is off and staying off.
    await engine.setVideoEnhancementMode(mode: _videoEnhancementMode.toEngine);
  }

  /// Enhancement hook installed on the presenter.
  ///
  /// Runs the native GPU stage for one decoded frame. Returns `null` to
  /// present the decoded frame unchanged — which is also what happens on any
  /// error, so a GPU problem can never break playback.
  Future<mf.PixelBufferHandoff?> _enhanceFrame(
    mf.MediaVideoFrame frame,
    mf.PixelBufferHandoff handoff,
  ) async {
    final engine = _engine;
    if (engine == null) return null;
    try {
      // The engine takes ownership of the decoded frame's retain on success
      // and returns the enhanced surface; `null` means "present the decoded
      // frame as-is" and leaves that retain with us.
      final enhanced = await engine.enhancePixelBuffer(
        pixelBufferPtr: handoff.pixelBufferPtr,
        width: handoff.width,
        height: handoff.height,
        ptsMs: handoff.ptsMs,
      );
      if (enhanced == null) {
        _enhancementBypassedFrames++;
        return null;
      }
      _enhancedFrames++;
      return enhanced;
    } catch (e) {
      debugPrint('[MediaForgePlayer] enhancement failed: $e');
      _enhancementBypassedFrames++;
      return null;
    }
  }

  /// Refresh the enhancement counters folded into diagnostics.
  Future<void> _refreshEnhancementDiagnostics() async {
    final engine = _engine;
    if (engine == null) return;
    if (!_videoEnhancementMode.isActive &&
        (_videoEnhancementStatus?.supported ?? true) == false) {
      return;
    }
    try {
      final s = await engine.videoEnhancementStatus();
      _videoEnhancementStatus = VideoEnhancementStatus(
        supported: s.supported,
        requestedMode: VideoEnhancementMode.fromEngine(s.requestedMode),
        activeMode: VideoEnhancementMode.fromEngine(s.activeMode),
        backend: s.backend,
        path: s.path,
        scaler: s.scaler,
        inputWidth: s.inputWidth,
        inputHeight: s.inputHeight,
        outputWidth: s.outputWidth,
        outputHeight: s.outputHeight,
        lastFrameMs: s.lastFrameMs,
        averageFrameMs: s.averageFrameMs,
        deadlineMs: s.deadlineMs,
        deadlineMisses: s.deadlineMisses.toInt(),
        hardDeadlineMisses: s.hardDeadlineMisses.toInt(),
        enhancedFrames: s.enhancedFrames.toInt(),
        bypassedFrames: s.bypassedFrames.toInt(),
        failedFrames: s.failedFrames.toInt(),
        passes: s.passes,
        fallbackReason: s.fallbackReason,
        bypassReason: s.bypassReason,
      );
      if (value.videoEnhancementActive != _presenter.enhancementActive ||
          value.videoEnhancementFallbackReason != s.fallbackReason) {
        value = value.copyWith(
          videoEnhancementActive: _presenter.enhancementActive,
          videoEnhancementFallbackReason: s.fallbackReason,
        );
      }
    } catch (e) {
      debugPrint('[MediaForgePlayer] enhancement status failed: $e');
    }
  }

  // ------------------------------------------------------- presentation ------

  void _startLoops() {
    if (_releaseFuture != null || _disposed) return;
    if (_suspended) return;
    _diagTimer ??= Timer.periodic(
      effectiveDiagnosticsCadence,
      (_) => _diagnosticsTick(),
    );
    if (!_vsyncScheduled) {
      _vsyncScheduled = true;
      SchedulerBinding.instance.scheduleFrameCallback(_onVsync);
      SchedulerBinding.instance.scheduleFrame();
    }
  }

  /// Frame-ready presentation pump (§5).
  ///
  /// Schedules exactly one Flutter frame callback per presented frame.
  /// No bridge calls while paused / completed / backgrounded / disposed.
  void _onVsync(Duration timestamp) {
    if (_releaseFuture != null || _disposed) {
      _vsyncScheduled = false;
      return;
    }
    if (_suspended || !value.isPlaying || value.isCompleted) {
      // Stop the pump — play()/resume() re-registers a single callback.
      _vsyncScheduled = false;
      return;
    }
    _presentationTick();
    if (_releaseFuture != null || _disposed) {
      _vsyncScheduled = false;
      return;
    }
    if (_suspended || !value.isPlaying || value.isCompleted) {
      _vsyncScheduled = false;
      return;
    }
    SchedulerBinding.instance.scheduleFrameCallback(_onVsync);
    SchedulerBinding.instance.scheduleFrame();
  }

  /// Test hook: run one presentation tick on demand (frame-ready path).
  @visibleForTesting
  Future<void> presentationTickForTest() => _presentationTick();

  /// Vsync-driven presentation: follows decoder PTS, never a Dart Timer.
  Future<void> _presentationTick() async {
    final engine = _engine;
    if (engine == null ||
        _tickInFlight ||
        _disposed ||
        _releaseFuture != null ||
        _suspended) {
      return;
    }
    if (!value.isPlaying || value.isCompleted) return;
    _tickInFlight = true;
    try {
      final pts = await _presenter.presentNext(engine);
      if (pts >= 0) {
        _presentedSinceTick++;
        _presentedFrames++;
        if (_firstDecodedAt == null) {
          _firstDecodedAt = DateTime.now();
        }
        if (_firstPresentedAt == null) {
          _firstPresentedAt = DateTime.now();
          value = value.copyWith(firstFramePresented: true);
          final latency = firstFrameLatencyMs;
          _emit(MediaForgeEvent(
            MediaForgeEventType.firstFramePresented,
            positionMs: pts,
            latencyMs: latency,
          ));
          debugPrint(
              '[MediaForgePlayer] first frame presented pts=${pts}ms latency=${latency}ms');
        } else if (!value.firstFramePresented) {
          value = value.copyWith(firstFramePresented: true);
        }
        _maybeSettleSeek(pts);
        final size = _presenter.frameSize.value;
        if (size.width > 0 &&
            (size.width.toInt() != value.videoWidth ||
                size.height.toInt() != value.videoHeight)) {
          value = value.copyWith(
            videoWidth: size.width.toInt(),
            videoHeight: size.height.toInt(),
          );
        }
      } else {
        // §6: an empty poll is NOT a dropped frame. Drops are tracked
        // from engine counters in _diagnosticsTick only.
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
    if (engine == null ||
        _disposed ||
        _releaseFuture != null ||
        !value.isInitialized) {
      return;
    }
    if (_suspended) return;
    try {
      final snap = await engine.getDiagnostics();
      final mediaMs = snap.mediaTimeMs.toInt();
      final audioMs = snap.audioClockMs.toInt();
      final presentedMs = snap.presentedPtsMs.toInt();
      final decodedMs = snap.latestDecodedPtsMs.toInt();
      if (decodedMs != _lastDecodedPts) {
        if (_firstDecodedAt == null && decodedMs > 0) {
          _firstDecodedAt = DateTime.now();
        }
        _decodedPtsChanges++;
        _lastDecodedPts = decodedMs;
      }
      final vq = snap.videoFramesInQueue.toInt();
      final vpq = snap.videoPacketsInQueue.toInt();
      final apq = snap.audioPacketsInQueue.toInt();
      final afq = snap.audioFramesInQueue.toInt();
      final engineBufferedMs = snap.bufferedDurationMs.toInt();
      final buffering = _updateRebufferingHysteresis(
        videoFrames: vq,
        packetBufferedMs: engineBufferedMs,
      );
      if (buffering && !value.isBuffering) {
        _emit(const MediaForgeEvent(MediaForgeEventType.buffering));
      }
      final durationMs = value.duration.inMilliseconds;
      final position = Duration(milliseconds: mediaMs);
      final duration = Duration(milliseconds: durationMs);
      final frameMem = _estimateFrameMemoryBytes(vq);
      final videoBytes = _estimateQueueBytes(vpq, isVideo: true);
      final audioBytes = _estimateQueueBytes(apq, isVideo: false);
      final packetBytes = videoBytes + audioBytes;
      // Honest read-ahead from real engine state (never faked from
      // position alone): decoded-ahead + compressed packet window.
      // Packet durations are capped by the configured budgets so paused
      // read-ahead stops at backpressure instead of growing unbounded.
      final videoPacketMs = _cappedQueueDurationMs(vpq, isVideo: true);
      final audioPacketMs = _cappedQueueDurationMs(apq, isVideo: false);
      final packetMs = videoPacketMs > audioPacketMs
          ? videoPacketMs
          : audioPacketMs;
      final bufferSnapshot = _computeBufferSnapshot(
        position: position,
        duration: duration,
        engineBufferedMs: engineBufferedMs,
        packetBufferedMs: packetMs,
        packetBufferedBytes: packetBytes,
        decodedVideoFrames: vq,
        decodedFrameMemoryBytes: frameMem,
        isPlaying: value.isPlaying,
      );
      value = value.copyWith(
        position: position,
        buffered: bufferSnapshot.bufferedPosition,
        bufferedPosition: bufferSnapshot.bufferedPosition,
        bufferedRanges: bufferSnapshot.ranges,
        bufferedAhead: bufferSnapshot.bufferedAhead,
        isRebuffering: bufferSnapshot.isRebuffering,
        isPreloading: bufferSnapshot.isPreloading,
        packetBufferedDuration: bufferSnapshot.packetBufferedDuration,
        packetBufferedBytes: bufferSnapshot.packetBufferedBytes,
        decodedVideoFrames: bufferSnapshot.decodedVideoFrames,
        decodedFrameMemoryBytes: bufferSnapshot.decodedFrameMemoryBytes,
        isBuffering: buffering,
      );
      // §6 true drop accounting: engine counter deltas only. The native
      // engine reports stale+catchup as one number today; split it
      // heuristically until the native split lands (both stay observable).
      final engineDrops = snap.droppedVideoFrames.toInt();
      final prevTotal = _queueOverflowDrops + _catchupDrops + _decoderDrops;
      if (engineDrops > prevTotal) {
        final delta = engineDrops - prevTotal;
        // Attribute to catch-up (the dominant pre-decode discard) while
        // keeping the total exact; the native split will refine this.
        _catchupDrops += delta;
        _decoderDrops = snap.droppedVideoFrames.toInt() -
            _queueOverflowDrops -
            _catchupDrops;
        if (_decoderDrops < 0) _decoderDrops = 0;
      }
      MediaForgeCapabilities? caps;
      try {
        caps = await MediaForgeCapabilities.probe();
      } catch (e) {
        debugPrint('[MediaForgePlayer] capabilities probe failed: $e');
      }
      final engineDecoder = snap.activeVideoDecoder;
      final fallbackDecoder = caps?.decoderLabelFor() ?? 'unknown';
      final activeDecoder =
          engineDecoder.isEmpty || engineDecoder == 'none'
              ? fallbackDecoder
              : engineDecoder;
      await _refreshEnhancementDiagnostics();
      final enhancement = _videoEnhancementStatus;
      final diag = MediaForgeDiagnostics(
        state: snap.state,
        mediaTimeMs: mediaMs,
        audioClockMs: audioMs,
        wallClockMs: snap.wallClockMs.toInt(),
        latestDecodedPtsMs: decodedMs,
        presentedPtsMs: presentedMs,
        avDriftMs: snap.avDriftMs.toInt(),
        videoPacketsInQueue: vpq,
        audioPacketsInQueue: apq,
        videoFramesInQueue: vq,
        audioFramesInQueue: afq,
        decodedFps: _decodedFps,
        presentedFps: _presentedFps,
        droppedFrames: _queueOverflowDrops + _catchupDrops + _decoderDrops,
        bufferedDurationMs: engineBufferedMs,
        activeDecoder: activeDecoder,
        hwDecode: snap.hwDecodeActive,
        networkBytesRead: snap.bytesRead.toInt(),
        bytesRead: snap.bytesRead.toInt(),
        readBitrateBps: snap.readBitrateBps.toInt(),
        decoderDroppedFrames: snap.droppedVideoFrames.toInt(),
        subtitleCuesPending: snap.subtitleCuesPending.toInt(),
        selectedVideoIndex: snap.selectedVideoIndex,
        selectedAudioIndex: snap.selectedAudioIndex,
        selectedSubtitleIndex: snap.selectedSubtitleIndex,
        firstDecodedAtMs: _firstDecodedAt?.millisecondsSinceEpoch,
        firstPresentedAtMs: _firstPresentedAt?.millisecondsSinceEpoch,
        firstFrameLatencyMs: firstFrameLatencyMs,
        lastSeekStartedAtMs: _lastSeekStartedAt?.millisecondsSinceEpoch,
        lastSeekSettledAtMs: _lastSeekSettledAt?.millisecondsSinceEpoch,
        lastSeekLatencyMs: _lastSeekLatencyMs,
        lastSeekGeneration: _lastSeekSettledGeneration,
        presentedFrameCount: _presentedFrames,
        bridgeCallCount: _presenter.bridgeCallCount,
        queueOverflowDrops: _queueOverflowDrops,
        catchupDrops: _catchupDrops,
        decodedQueueDepth: vq + afq,
        videoQueueBytes: videoBytes,
        audioQueueBytes: audioBytes,
        videoQueueDurationMs: _estimateQueueDurationMs(vpq, isVideo: true),
        audioQueueDurationMs: _estimateQueueDurationMs(apq, isVideo: false),
        packetBufferDurationMs: packetMs,
        frameMemoryBytes: frameMem,
        probeDurationMs: _lastProbeDurationMs,
        presentationTimeMs: _presenter.lastPresentationMs,
        renderingPath: _presenter.activeRenderingPath,
        nativeWidth: _presenter.nativeWidth > 0
            ? _presenter.nativeWidth
            : value.videoWidth,
        nativeHeight: _presenter.nativeHeight > 0
            ? _presenter.nativeHeight
            : value.videoHeight,
        presentedWidth: value.videoWidth,
        presentedHeight: value.videoHeight,
        retainedPixelBufferCount: vq,
        retainedTextureCount: _presenter.textureId.value != null ? 1 : 0,
        isSuspended: _suspended,
        videoEnhancementSupported: enhancement?.supported ?? false,
        videoEnhancementRequested: _videoEnhancementMode.wireName,
        videoEnhancementActive:
            (enhancement?.activeMode ?? VideoEnhancementMode.off).wireName,
        videoEnhancementBackend: enhancement?.backend ?? 'none',
        videoEnhancementPath: enhancement?.path ?? '',
        videoEnhancementInputWidth: enhancement?.inputWidth ?? 0,
        videoEnhancementInputHeight: enhancement?.inputHeight ?? 0,
        videoEnhancementOutputWidth: enhancement?.outputWidth ?? 0,
        videoEnhancementOutputHeight: enhancement?.outputHeight ?? 0,
        videoEnhancementFrameMs: enhancement?.lastFrameMs,
        videoEnhancementAverageMs: enhancement?.averageFrameMs,
        videoEnhancementDeadlineMs: enhancement?.deadlineMs,
        videoEnhancementDeadlineMisses: enhancement?.deadlineMisses ?? 0,
        videoEnhancementFallbackReason: enhancement?.fallbackReason ?? '',
      );
      _lastDiagnostics = diag;
      if (!_diagnostics.isClosed) _diagnostics.add(diag);

      // Optimistic seek-settle for engines that present without a fresh
      // takeVideoFrame (e.g. fakes in tests): if a seek is pending and the
      // clock already sits near the target, settle on the latest gen.
      if (_pendingSeekGeneration != null &&
          _pendingSeekGeneration == _seekGeneration) {
        final target = _pendingSeekTargetMs ?? mediaMs;
        if ((mediaMs - target).abs() <= 500) {
          _maybeSettleSeek(mediaMs);
        }
      }

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
            _setRuntimeState(MediaForgePlayerRuntimeState.ended);
            debugPrint('[MediaForgePlayer] completed');
          }
        }
      }
    } catch (e) {
      debugPrint('[MediaForgePlayer] diagnostics tick failed: $e');
    }
  }

  bool _updateRebufferingHysteresis({
    required int videoFrames,
    required int packetBufferedMs,
  }) {
    // Pausing must not turn a healthy source into a spinner. The native
    // demuxer can keep its bounded compressed-packet queue filling; its
    // timestamp coverage remains visible through _computeBufferSnapshot.
    if (!value.isPlaying) {
      _starvationStartedAt = null;
      _recoveryReadyStartedAt = null;
      _rebufferingLatched = false;
      if (packetBufferedMs > 0 && !value.isCompleted) {
        _setRuntimeState(MediaForgePlayerRuntimeState.preloading,
            reason: 'paused-read-ahead');
      }
      return false;
    }

    final now = DateTime.now();
    final starved = videoFrames == 0;
    if (!starved) {
      _starvationStartedAt = null;
      if (_rebufferingLatched) {
        final ready = packetBufferedMs >= _recoveryPacketFloor.inMilliseconds ||
            videoFrames >= 2;
        if (!ready) {
          _recoveryReadyStartedAt = null;
        } else {
          _recoveryReadyStartedAt ??= now;
        }
        if (ready && now.difference(_recoveryReadyStartedAt!) >= _rebufferExitDelay) {
          _rebufferingLatched = false;
          _recoveryReadyStartedAt = null;
          _setRuntimeState(MediaForgePlayerRuntimeState.playing,
              reason: 'rebuffer-recovered');
        }
      } else {
        _setRuntimeState(MediaForgePlayerRuntimeState.playing);
      }
      return _rebufferingLatched;
    }

    _recoveryReadyStartedAt = null;
    _starvationStartedAt ??= now;
    if (!_rebufferingLatched &&
        now.difference(_starvationStartedAt!) >= _starvationEnterDelay) {
      _rebufferingLatched = true;
      _setRuntimeState(MediaForgePlayerRuntimeState.rebuffering,
          reason: 'video-starvation');
    }
    return _rebufferingLatched;
  }

  int _estimateFrameMemoryBytes(int videoFrames) {
    final w = _presenter.nativeWidth > 0
        ? _presenter.nativeWidth
        : value.videoWidth;
    final h = _presenter.nativeHeight > 0
        ? _presenter.nativeHeight
        : value.videoHeight;
    if (w <= 0 || h <= 0 || videoFrames <= 0) return 0;
    // BGRA/RGBA 4 bytes per pixel; VT buffers counted at BGRA size.
    return videoFrames * w * h * 4;
  }

  int _estimateQueueBytes(int packets, {required bool isVideo}) {
    if (packets <= 0) return 0;
    // Conservative average compressed packet sizes for observability until
    // the native byte-accurate counters land via FRB.
    final avg = isVideo ? 64 * 1024 : 8 * 1024;
    return packets * avg;
  }

  int _estimateQueueDurationMs(int packets, {required bool isVideo}) {
    if (packets <= 0) return 0;
    // ~40 ms per video packet (25 fps), ~20 ms per audio packet heuristic.
    return packets * (isVideo ? 40 : 20);
  }

  /// Packet-window duration capped by the configured byte/duration budgets.
  ///
  /// The Rust queues enforce 16 MiB/5 s (video) and 4 MiB/5 s (audio) as
  /// backpressure: paused read-ahead must stop there instead of growing
  /// unbounded. Capping the Dart estimate at the same budget keeps the
  /// timeline honest about the backpressure limit.
  int _cappedQueueDurationMs(int packets, {required bool isVideo}) {
    final raw = _estimateQueueDurationMs(packets, isVideo: isVideo);
    final budget = isVideo
        ? configuration?.videoPacketBudget.maxDuration ??
            const Duration(seconds: 5)
        : configuration?.audioPacketBudget.maxDuration ??
            const Duration(seconds: 5);
    final cap = budget.inMilliseconds;
    if (cap <= 0) return raw;
    return raw > cap ? cap : raw;
  }

  bool get _isFileSource =>
      _media is MediaForgeFile || _media is MediaForgeAsset;

  /// Honest buffer snapshot from real engine state.
  ///
  /// * Files/assets: the source is effectively available — report the full
  ///   duration as buffered (no misleading "network buffering").
  /// * HTTP(S): only the genuinely demuxed window
  ///   (decoded-ahead + compressed packet window) counts. Never the full
  ///   Content-Length.
  MediaForgeBufferState _computeBufferSnapshot({
    required Duration position,
    required Duration duration,
    required int engineBufferedMs,
    required int packetBufferedMs,
    required int packetBufferedBytes,
    required int decodedVideoFrames,
    required int decodedFrameMemoryBytes,
    required bool isPlaying,
  }) {
    final durationMs = duration.inMilliseconds;
    if (durationMs <= 0) {
      final empty = MediaForgeBufferState(
        packetBufferedDuration: Duration(milliseconds: packetBufferedMs),
        packetBufferedBytes: packetBufferedBytes,
        decodedVideoFrames: decodedVideoFrames,
        decodedFrameMemoryBytes: decodedFrameMemoryBytes,
      );
      _lastInternalRanges = const [];
      bufferState.value = empty;
      debugPrint(
          '[MediaForgePlayer] buffer pos=${position.inMilliseconds}ms ranges=0 (no duration)');
      return empty;
    }
    List<MediaForgeBufferedRange> internal;
    if (_isFileSource) {
      // Local source: any position is immediately seekable, no network wait.
      internal = [MediaForgeBufferedRange(start: Duration.zero, end: duration)];
    } else {
      final safeEngine = engineBufferedMs < 0 ? 0 : engineBufferedMs;
      final safePacket = packetBufferedMs < 0 ? 0 : packetBufferedMs;
      // Packets sit ahead of the decoded head, so windows add (not max).
      final aheadMs = safeEngine + safePacket;
      final endMs =
          (position.inMilliseconds + aheadMs).clamp(0, durationMs);
      final end = Duration(milliseconds: endMs);
      if (end <= position) {
        internal = const [];
      } else {
        internal =
            [MediaForgeBufferedRange(start: position, end: end)];
      }
    }
    _lastInternalRanges = internal;
    return _mergeBufferSnapshot(
      internal: internal,
      position: position,
      duration: duration,
      packetBufferedMs: packetBufferedMs,
      packetBufferedBytes: packetBufferedBytes,
      decodedVideoFrames: decodedVideoFrames,
      decodedFrameMemoryBytes: decodedFrameMemoryBytes,
      isPlaying: isPlaying,
    );
  }

  MediaForgeBufferState _mergeBufferSnapshot({
    required List<MediaForgeBufferedRange> internal,
    required Duration position,
    required Duration duration,
    required int packetBufferedMs,
    required int packetBufferedBytes,
    required int decodedVideoFrames,
    required int decodedFrameMemoryBytes,
    required bool isPlaying,
  }) {
    final internalNormalized = normalizeBufferedRanges(internal);
    // External ranges belong to the host cache layer. They are useful to draw
    // on the timeline, but must never make MediaForge believe compressed data
    // is immediately readable or suppress a real rebuffer.
    final merged = mergeBufferedRanges(internalNormalized, _externalBufferedRanges);
    // Clamp display ranges to [0, duration].
    final clamped = <MediaForgeBufferedRange>[];
    for (final r in merged) {
      final s = r.start < Duration.zero ? Duration.zero : r.start;
      var e = r.end;
      if (s >= duration) continue;
      if (e > duration) e = duration;
      if (e <= s) continue;
      clamped.add(MediaForgeBufferedRange(start: s, end: e));
    }
    final normalized = normalizeBufferedRanges(clamped);
    final bufferedPosition =
        contiguousBufferedPosition(internalNormalized, position);
    var ahead = bufferedPosition - position;
    if (ahead.isNegative) ahead = Duration.zero;
    // Stall (needs spinner) vs background read-ahead (never a big spinner).
    // Use the latched hysteresis state rather than a single empty queue
    // sample. A transient decoder handoff must not flash buffering UI or
    // trigger recovery work before the enter threshold has elapsed.
    final isRebuffering = isPlaying && _rebufferingLatched;
    final isPreloading = !_isFileSource &&
        !isRebuffering &&
        ahead > Duration.zero;
    final snapshot = MediaForgeBufferState(
      ranges: normalized,
      bufferedPosition: bufferedPosition,
      bufferedAhead: ahead,
      isRebuffering: isRebuffering,
      isPreloading: isPreloading,
      packetBufferedDuration: Duration(milliseconds: packetBufferedMs),
      packetBufferedBytes: packetBufferedBytes,
      decodedVideoFrames: decodedVideoFrames,
      decodedFrameMemoryBytes: decodedFrameMemoryBytes,
    );
    bufferState.value = snapshot;
    debugPrint(
        '[MediaForgePlayer] buffer pos=${position.inMilliseconds}ms '
        'buffered=${bufferedPosition.inMilliseconds}ms ahead=${ahead.inMilliseconds}ms '
        'ranges=${normalized.length} packet=${packetBufferedMs}ms/${packetBufferedBytes}B '
        'decodedFrames=$decodedVideoFrames rebuffering=$isRebuffering preloading=$isPreloading');
    return snapshot;
  }

  void _refreshMergedBufferState({
    required Duration position,
    required Duration duration,
  }) {
    if (!value.isInitialized) return;
    final current = bufferState.value;
    _mergeBufferSnapshot(
      internal: _lastInternalRanges,
      position: position,
      duration: duration,
      packetBufferedMs: current.packetBufferedDuration.inMilliseconds,
      packetBufferedBytes: current.packetBufferedBytes,
      decodedVideoFrames: current.decodedVideoFrames,
      decodedFrameMemoryBytes: current.decodedFrameMemoryBytes,
      isPlaying: value.isPlaying,
    );
    final updated = bufferState.value;
    value = value.copyWith(
      buffered: updated.bufferedPosition,
      bufferedPosition: updated.bufferedPosition,
      bufferedRanges: updated.ranges,
      bufferedAhead: updated.bufferedAhead,
      isRebuffering: updated.isRebuffering,
      isPreloading: updated.isPreloading,
    );
  }

  /// Test hook: run one diagnostics tick on demand.
  @visibleForTesting
  Future<void> diagnosticsTickForTest() => _diagnosticsTick();

  // ------------------------------------------------------------- lifecycle ---

  /// Suspend presentation pump, diagnostics timer and subtitle wakeups (§13).
  ///
  /// No bridge frame calls are emitted while suspended. The session (engine,
  /// texture, position) is retained for [resume].
  Future<void> suspend() async {
    if (_suspended || _releaseFuture != null || _disposed) return;
    _suspended = true;
    _vsyncScheduled = false;
    _diagTimer?.cancel();
    _diagTimer = null;
    debugPrint('[MediaForgePlayer] suspended (pump+diag+subs paused)');
  }

  /// Resume a suspended session (§13).
  Future<void> resume() async {
    if (!_suspended || _releaseFuture != null || _disposed) return;
    _suspended = false;
    _fpsWindowStart = DateTime.now();
    if (value.isPlaying && !value.isCompleted) {
      _startLoops();
    } else {
      // Restart diagnostics so position stays fresh even while paused.
      _diagTimer ??= Timer.periodic(
        effectiveDiagnosticsCadence,
        (_) => _diagnosticsTick(),
      );
    }
    debugPrint('[MediaForgePlayer] resumed');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (configuration?.suspendInBackground == false) return;
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        unawaited(suspend());
        break;
      case AppLifecycleState.resumed:
        unawaited(resume());
        break;
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

  /// Resource counters for release verification (all must be 0 after
  /// [release] except the stable handle itself).
  Map<String, int> resourceCountersForTest() => {
        'engine': _engine == null ? 0 : 1,
        'textures': _presenter.textureId.value != null ? 1 : 0,
        'videoFrames': _lastDiagnostics?.videoFramesInQueue ?? 0,
        'pixelBuffers': _lastDiagnostics?.retainedPixelBufferCount ?? 0,
        'diagTimer': _diagTimer == null ? 0 : 1,
        'vsyncScheduled': _vsyncScheduled ? 1 : 0,
      };

  /// Async release. Named `release` because [ValueNotifier.dispose] is sync.
  ///
  /// Deterministic, idempotent, ordered (§15):
  /// 1. stop new commands/frame requests
  /// 2. cancel blocked FFmpeg operations (generation bump)
  /// 3. stop workers (diag timer + vsync pump)
  /// 4. stop audio/engine
  /// 5. release frame/pixel-buffer references
  /// 6. release texture/presentation resources
  /// 7. finish controller disposal
  ///
  /// Repeated calls return the same future and are safe.
  Future<void> release() {
    final existing = _releaseFuture;
    if (existing != null) return existing;
    final future = _releaseImpl();
    _releaseFuture = future;
    return future;
  }

  Future<void> _releaseImpl() async {
    _setRuntimeState(MediaForgePlayerRuntimeState.disposed);
    // 1. Stop new commands/frame requests.
    _disposed = true;
    _suspended = true;
    _vsyncScheduled = false;
    _sourceGeneration++;
    try {
      WidgetsBinding.instance.removeObserver(this);
    } catch (_) {}
    // 2-3. Cancel blocked ops + stop workers.
    _diagTimer?.cancel();
    _diagTimer = null;
    // 4. Stop audio/engine.
    try {
      await _engine?.stop();
    } catch (e) {
      debugPrint('[MediaForgePlayer] dispose stop failed: $e');
    }
    _engine = null;
    _presenter.enhancer = null;
    // 5-6. Release frames + texture/presentation resources.
    try {
      _presenter.dispose();
    } catch (e) {
      debugPrint('[MediaForgePlayer] presenter dispose failed: $e');
    }
    try {
      await MediaForgeTexturePresenter.handleMemoryPressure();
    } catch (e) {
      debugPrint('[MediaForgePlayer] flush pools failed: $e');
    }
    // 7. Finish disposal.
    _emit(const MediaForgeEvent(MediaForgeEventType.disposed));
    try {
      await _events.close();
    } catch (_) {}
    try {
      await _diagnostics.close();
    } catch (_) {}
    try {
      bufferState.dispose();
    } catch (_) {}
    runtimeState.dispose();
    debugPrint('[MediaForgePlayer] disposed handle=$textureHandle');
  }

  @override
  void dispose() {
    unawaited(release());
    super.dispose();
  }
}
