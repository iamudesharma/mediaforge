import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:media_forge/media_forge.dart' as mf;

/// Scripted in-memory engine for controller stress tests (no native lib).
///
/// Mimics engine semantics: position advances while playing, track
/// selection validates against [streams], subtitle polling honours
/// enabled/selection state, and every mutating call is logged.
class FakeMediaPlaybackEngine implements mf.MediaPlaybackEngine {
  FakeMediaPlaybackEngine({
    this.durationMs = 120000,
    List<mf.MediaStreamInfo>? streams,
  }) : streams = streams ?? _defaultStreams();

  static List<mf.MediaStreamInfo> _defaultStreams() => [
        mf.MediaStreamInfo(
          index: 0,
          kind: mf.StreamKind.video,
          codecName: 'h264',
          language: '',
          title: '',
          bitrate: BigInt.zero,
          width: 1920,
          height: 1080,
          channels: 0,
          sampleRate: 0,
          isDefault: true,
          isForced: false,
        ),
        mf.MediaStreamInfo(
          index: 1,
          kind: mf.StreamKind.audio,
          codecName: 'aac',
          language: 'en',
          title: 'English',
          bitrate: BigInt.zero,
          width: 0,
          height: 0,
          channels: 2,
          sampleRate: 48000,
          isDefault: true,
          isForced: false,
        ),
        mf.MediaStreamInfo(
          index: 2,
          kind: mf.StreamKind.audio,
          codecName: 'ac3',
          language: 'es',
          title: 'Español',
          bitrate: BigInt.zero,
          width: 0,
          height: 0,
          channels: 6,
          sampleRate: 48000,
          isDefault: false,
          isForced: false,
        ),
        mf.MediaStreamInfo(
          index: 3,
          kind: mf.StreamKind.subtitle,
          codecName: 'mov_text',
          language: 'en',
          title: 'English',
          bitrate: BigInt.zero,
          width: 0,
          height: 0,
          channels: 0,
          sampleRate: 0,
          isDefault: true,
          isForced: false,
        ),
        mf.MediaStreamInfo(
          index: 4,
          kind: mf.StreamKind.subtitle,
          codecName: 'subrip',
          language: 'fr',
          title: 'Français',
          bitrate: BigInt.zero,
          width: 0,
          height: 0,
          channels: 0,
          sampleRate: 0,
          isDefault: false,
          isForced: false,
        ),
      ];

  final int durationMs;
  final List<mf.MediaStreamInfo> streams;

  int positionMs = 0;
  bool playing = false;
  double volume = 1.0;
  bool muted = false;
  double rate = 1.0;
  int selectedAudio = 1;
  int selectedSubtitle = -1;
  bool subtitlesEnabled = true;
  int subtitleDelayMs = 0;
  bool externalOpen = false;
  int openCount = 0;

  final List<String> openedUrls = [];
  final List<String> openedFiles = [];
  mf.NetworkOptions? lastOptions;
  final List<int> seekLog = [];
  final List<int> audioSelectLog = [];
  final List<int> subtitleSelectLog = [];
  final List<int> videoSelectLog = [];
  final List<String> externalOpened = [];

  DateTime _lastTick = DateTime.now();
  bool _disposed = false;

  @override
  void dispose() => _disposed = true;

  @override
  bool get isDisposed => _disposed;

  int _pos() {
    if (playing) {
      final now = DateTime.now();
      positionMs += (now.difference(_lastTick).inMilliseconds * rate).round();
      _lastTick = now;
      if (positionMs >= durationMs) positionMs = durationMs;
    } else {
      _lastTick = DateTime.now();
    }
    return positionMs;
  }

  // -- open ------------------------------------------------------------

  @override
  Future<void> openUrl(
      {required String url, required mf.NetworkOptions options}) async {
    openedUrls.add(url);
    lastOptions = options;
    openCount++;
    positionMs = 0;
    playing = false;
    _lastTick = DateTime.now();
  }

  @override
  Future<void> openFile({required String path}) async {
    openedFiles.add(path);
    openCount++;
    positionMs = 0;
    playing = false;
    _lastTick = DateTime.now();
  }

  @override
  Future<List<mf.MediaStreamInfo>> listStreams() async => streams;

  // -- transport --------------------------------------------------------

  @override
  Future<void> start() async {
    playing = true;
    _lastTick = DateTime.now();
  }

  @override
  Future<void> pause() async {
    _pos();
    playing = false;
  }

  @override
  Future<void> stop() async {
    playing = false;
    positionMs = 0;
  }

  @override
  Future<void> seek({required BigInt timeMs}) async {
    positionMs = timeMs.toInt().clamp(0, durationMs);
    seekLog.add(positionMs);
    _lastTick = DateTime.now();
  }

  @override
  Future<void> setRate({required double rate}) async => this.rate = rate;

  @override
  Future<void> setVolume({required double volume}) async {
    this.volume = volume;
  }

  @override
  Future<double> getVolume() async => volume;

  @override
  Future<void> setMuted({required bool muted}) async => this.muted = muted;

  @override
  Future<void> setSourceMuted({required bool muted}) async {}

  @override
  Future<void> setTrimRange(
          {required BigInt startMs, required BigInt endMs}) async {}

  @override
  Future<BigInt> getTrimStartMs() async => BigInt.zero;

  @override
  Future<BigInt> getTrimEndMs() async => BigInt.from(durationMs);

  // -- tracks ------------------------------------------------------------

  void _requireKind(int index, mf.StreamKind kind) {
    final match =
        streams.any((s) => s.index == index && s.kind == kind);
    if (!match) throw Exception('Unknown stream index $index');
  }

  @override
  Future<void> selectAudioStream({required int index}) async {
    _requireKind(index, mf.StreamKind.audio);
    selectedAudio = index;
    audioSelectLog.add(index);
  }

  @override
  Future<void> selectVideoStream({required int index}) async {
    _requireKind(index, mf.StreamKind.video);
    videoSelectLog.add(index);
  }

  @override
  Future<void> selectSubtitleStream({required int index}) async {
    if (index != -1) _requireKind(index, mf.StreamKind.subtitle);
    selectedSubtitle = index;
    subtitleSelectLog.add(index);
  }

  // -- subtitles ----------------------------------------------------------

  @override
  Future<String?> pollSubtitleText({required BigInt timeMs}) async {
    if (!subtitlesEnabled) return null;
    if (selectedSubtitle < 0 && !externalOpen) return null;
    final t = timeMs.toInt() - subtitleDelayMs;
    if (5000 <= t && t < 9000) return 'Hello';
    if (10000 <= t && t < 14000) return 'World';
    return null;
  }

  @override
  Future<void> setSubtitleDelayMs({required PlatformInt64 delayMs}) async {
    subtitleDelayMs = delayMs;
  }

  @override
  Future<PlatformInt64> getSubtitleDelayMs() async => subtitleDelayMs;

  @override
  Future<void> setSubtitlesEnabled({required bool enabled}) async {
    subtitlesEnabled = enabled;
  }

  @override
  Future<void> openExternalSubtitle({required String pathOrUrl}) async {
    externalOpened.add(pathOrUrl);
    externalOpen = true;
  }

  @override
  Future<void> closeExternalSubtitle() async {
    externalOpen = false;
  }

  // -- reads ---------------------------------------------------------------

  @override
  Future<BigInt> getDurationMs() async => BigInt.from(durationMs);

  @override
  Future<BigInt> getMediaTimeMs() async => BigInt.from(_pos());

  @override
  Future<BigInt> getAudioClockMs() async => BigInt.from(_pos());

  @override
  Future<BigInt> getWallClockMs() async => BigInt.from(_pos());

  @override
  Future<BigInt> getLatestDecodedVideoPtsMs() async => BigInt.from(_pos());

  @override
  Future<BigInt> getLastPresentedPtsMs() async => BigInt.from(_pos());

  @override
  Future<BigInt> getAvDriftMs() async => BigInt.zero;

  @override
  Future<mf.PlaybackState> getPlaybackState() async =>
      playing ? mf.PlaybackState.playing : mf.PlaybackState.paused;

  @override
  Future<BigInt> getVideoPacketQueueLen() async => BigInt.from(10);

  @override
  Future<BigInt> getAudioPacketQueueLen() async => BigInt.from(5);

  @override
  Future<BigInt> getVideoFrameQueueLen() async =>
      BigInt.from(playing ? 4 : 0);

  @override
  Future<BigInt> getAudioFrameQueueLen() async => BigInt.from(8);

  @override
  Future<mf.DiagnosticsSnapshot> getDiagnostics() async {
    final p = _pos();
    return mf.DiagnosticsSnapshot(
      state: playing ? mf.PlaybackState.playing : mf.PlaybackState.paused,
      mediaTimeMs: BigInt.from(p),
      audioClockMs: BigInt.from(p),
      wallClockMs: BigInt.from(p),
      latestDecodedPtsMs: BigInt.from(p),
      presentedPtsMs: BigInt.from(p),
      avDriftMs: BigInt.zero,
      videoPacketsInQueue: BigInt.from(10),
      audioPacketsInQueue: BigInt.from(5),
      videoFramesInQueue: BigInt.from(playing ? 4 : 0),
      audioFramesInQueue: BigInt.from(8),
      bytesRead: BigInt.from(1024 * 1024),
      readBitrateBps: BigInt.from(800000),
      bufferedDurationMs: BigInt.from(2000),
      droppedVideoFrames: BigInt.zero,
      activeVideoDecoder: 'h264-videotoolbox',
      hwDecodeActive: true,
      subtitleCuesPending: BigInt.two,
      selectedVideoIndex: 0,
      selectedAudioIndex: selectedAudio,
      selectedSubtitleIndex: selectedSubtitle,
    );
  }

  @override
  Future<mf.DecodeCapabilities> getDecodeCapabilities() async =>
      const mf.DecodeCapabilities(
        hevcVideotoolbox: true,
        h264Videotoolbox: true,
        hwDecodeDisabledEnv: false,
        ffmpegVersion: 'fake',
        readyForHevcHw: true,
        hint: 'fake',
      );

  @override
  Future<BigInt> presenterIntervalMs() async => BigInt.from(16);

  @override
  Future<BigInt> hardResyncDriftThresholdMs() async => BigInt.from(2000);

  @override
  Future<mf.MediaVideoFrame?> takeVideoFrame() async => null;

  @override
  Future<mf.AudioFrame?> takeAudioFrame() async => null;

  @override
  Future<Float32List> getAudioWaveform() async => Float32List(20);

  @override
  Future<bool> pushVideoPacket({required mf.MediaPacket packet}) async => true;

  @override
  Future<bool> pushAudioPacket({required mf.MediaPacket packet}) async => true;

  @override
  Future<BigInt> addOverlayAudio({
    required String path,
    required double volume,
    required BigInt timelineStartMs,
    required BigInt durationMs,
    required BigInt sourceStartMs,
  }) async =>
      BigInt.one;

  @override
  Future<void> removeOverlayAudio({required BigInt id}) async {}

  @override
  Future<void> setOverlayVolume(
          {required BigInt id, required double volume}) async {}
}
