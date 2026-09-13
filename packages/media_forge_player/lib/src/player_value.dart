import 'package:flutter/foundation.dart';

import 'buffered_range.dart';
import 'track_info.dart';

/// Immutable snapshot of player state, in the spirit of `video_player`'s
/// `VideoPlayerValue` but covering buffering, tracks and errors.
@immutable
class MediaForgePlayerValue {
  const MediaForgePlayerValue({
    this.isInitialized = false,
    this.isPlaying = false,
    this.isBuffering = false,
    this.isCompleted = false,
    this.duration = Duration.zero,
    this.position = Duration.zero,
    this.buffered = Duration.zero,
    this.bufferedPosition = Duration.zero,
    this.bufferedRanges = const [],
    this.bufferedAhead = Duration.zero,
    this.isRebuffering = false,
    this.isPreloading = false,
    this.packetBufferedDuration = Duration.zero,
    this.packetBufferedBytes = 0,
    this.decodedVideoFrames = 0,
    this.decodedFrameMemoryBytes = 0,
    this.volume = 1.0,
    this.isMuted = false,
    this.playbackRate = 1.0,
    this.videoWidth = 0,
    this.videoHeight = 0,
    this.rotationDegrees = 0,
    this.errorDescription,
    this.audioTracks = const [],
    this.subtitleTracks = const [],
    this.videoTracks = const [],
    this.selectedAudioTrackId,
    this.selectedSubtitleTrackId,
    this.selectedVideoTrackId,
    this.subtitleDelay = Duration.zero,
    this.subtitlesEnabled = true,
    this.firstFramePresented = false,
    this.activeSeekGeneration = 0,
    this.lastSeekSettledGeneration = -1,
  });

  /// Nothing opened yet.
  static const uninitialized = MediaForgePlayerValue();

  final bool isInitialized;
  final bool isPlaying;
  final bool isBuffering;
  final bool isCompleted;
  final Duration duration;
  final Duration position;

  /// Legacy single buffered point (kept for backward compat).
  ///
  /// Equals [bufferedPosition]: the contiguous buffered point ahead of the
  /// playhead. Prefer [bufferedRanges]/[bufferedPosition] for new code.
  final Duration buffered;

  /// Contiguous buffered point ahead of the playhead (honest read-ahead,
  /// never faked from playback position alone).
  final Duration bufferedPosition;

  /// Genuinely available ranges (engine read-ahead merged with optional
  /// host-provided cache ranges). May be non-contiguous after seeks or
  /// with sparse network/torrent caches.
  final List<MediaForgeBufferedRange> bufferedRanges;

  /// [bufferedPosition] − [position] (never negative).
  final Duration bufferedAhead;

  /// Playback cannot continue (stall). Show a loading indicator.
  ///
  /// Distinct from [isPreloading]: background read-ahead while healthy or
  /// paused must never show a large spinner.
  final bool isRebuffering;

  /// Background read-ahead while playback is healthy or paused.
  final bool isPreloading;

  /// Compressed packet read-ahead (demux/network layer, not decoded frames).
  final Duration packetBufferedDuration;

  /// Compressed packet bytes currently held.
  final int packetBufferedBytes;

  /// Decoded video frames waiting for presentation (small: ~2–3).
  final int decodedVideoFrames;

  /// Estimated retained decoded-frame memory (bytes).
  final int decodedFrameMemoryBytes;
  final double volume;
  final bool isMuted;
  final double playbackRate;
  final int videoWidth;
  final int videoHeight;

  /// Container rotation metadata (0/90/180/270).
  final int rotationDegrees;
  final String? errorDescription;

  final List<MediaForgeAudioTrack> audioTracks;
  final List<MediaForgeSubtitleTrack> subtitleTracks;

  /// Discovered video tracks (codec/dims for the info panel).
  final List<MediaForgeVideoTrack> videoTracks;
  final int? selectedVideoTrackId;
  final int? selectedAudioTrackId;
  final int? selectedSubtitleTrackId;

  /// User subtitle delay (signed; applied by the engine at cue ingest).
  final Duration subtitleDelay;

  /// Gates cue delivery in `pollSubtitleText`.
  final bool subtitlesEnabled;

  /// True once the first frame has been presented since open.
  final bool firstFramePresented;

  /// Monotonic seek generation (incremented on every seek/open).
  final int activeSeekGeneration;

  /// Latest seek generation that reached a valid presented frame (-1 = none).
  final int lastSeekSettledGeneration;

  bool get hasError => errorDescription != null;
  bool get hasVideo => videoWidth > 0 && videoHeight > 0;

  /// Display aspect ratio honouring rotation metadata.
  double get aspectRatio {
    if (!hasVideo) return 16 / 9;
    final swapped = rotationDegrees == 90 || rotationDegrees == 270;
    final w = swapped ? videoHeight : videoWidth;
    final h = swapped ? videoWidth : videoHeight;
    if (w <= 0 || h <= 0) return 16 / 9;
    return w / h;
  }

  MediaForgePlayerValue copyWith({
    bool? isInitialized,
    bool? isPlaying,
    bool? isBuffering,
    bool? isCompleted,
    Duration? duration,
    Duration? position,
    Duration? buffered,
    Duration? bufferedPosition,
    List<MediaForgeBufferedRange>? bufferedRanges,
    Duration? bufferedAhead,
    bool? isRebuffering,
    bool? isPreloading,
    Duration? packetBufferedDuration,
    int? packetBufferedBytes,
    int? decodedVideoFrames,
    int? decodedFrameMemoryBytes,
    double? volume,
    bool? isMuted,
    double? playbackRate,
    int? videoWidth,
    int? videoHeight,
    int? rotationDegrees,
    String? errorDescription,
    bool clearError = false,
    List<MediaForgeAudioTrack>? audioTracks,
    List<MediaForgeSubtitleTrack>? subtitleTracks,
    List<MediaForgeVideoTrack>? videoTracks,
    int? selectedAudioTrackId,
    int? selectedSubtitleTrackId,
    int? selectedVideoTrackId,
    Duration? subtitleDelay,
    bool? subtitlesEnabled,
    bool clearAudioSelection = false,
    bool clearSubtitleSelection = false,
    bool clearVideoSelection = false,
    bool? firstFramePresented,
    int? activeSeekGeneration,
    int? lastSeekSettledGeneration,
  }) {
    return MediaForgePlayerValue(
      isInitialized: isInitialized ?? this.isInitialized,
      isPlaying: isPlaying ?? this.isPlaying,
      isBuffering: isBuffering ?? this.isBuffering,
      isCompleted: isCompleted ?? this.isCompleted,
      duration: duration ?? this.duration,
      position: position ?? this.position,
      buffered: buffered ?? bufferedPosition ?? this.buffered,
      bufferedPosition: bufferedPosition ?? this.bufferedPosition,
      bufferedRanges: bufferedRanges ?? this.bufferedRanges,
      bufferedAhead: bufferedAhead ?? this.bufferedAhead,
      isRebuffering: isRebuffering ?? this.isRebuffering,
      isPreloading: isPreloading ?? this.isPreloading,
      packetBufferedDuration:
          packetBufferedDuration ?? this.packetBufferedDuration,
      packetBufferedBytes: packetBufferedBytes ?? this.packetBufferedBytes,
      decodedVideoFrames: decodedVideoFrames ?? this.decodedVideoFrames,
      decodedFrameMemoryBytes:
          decodedFrameMemoryBytes ?? this.decodedFrameMemoryBytes,
      volume: volume ?? this.volume,
      isMuted: isMuted ?? this.isMuted,
      playbackRate: playbackRate ?? this.playbackRate,
      videoWidth: videoWidth ?? this.videoWidth,
      videoHeight: videoHeight ?? this.videoHeight,
      rotationDegrees: rotationDegrees ?? this.rotationDegrees,
      errorDescription:
          clearError ? null : (errorDescription ?? this.errorDescription),
      audioTracks: audioTracks ?? this.audioTracks,
      subtitleTracks: subtitleTracks ?? this.subtitleTracks,
      videoTracks: videoTracks ?? this.videoTracks,
      selectedAudioTrackId: clearAudioSelection
          ? null
          : (selectedAudioTrackId ?? this.selectedAudioTrackId),
      selectedSubtitleTrackId: clearSubtitleSelection
          ? null
          : (selectedSubtitleTrackId ?? this.selectedSubtitleTrackId),
      selectedVideoTrackId: clearVideoSelection
          ? null
          : (selectedVideoTrackId ?? this.selectedVideoTrackId),
      subtitleDelay: subtitleDelay ?? this.subtitleDelay,
      subtitlesEnabled: subtitlesEnabled ?? this.subtitlesEnabled,
      firstFramePresented: firstFramePresented ?? this.firstFramePresented,
      activeSeekGeneration: activeSeekGeneration ?? this.activeSeekGeneration,
      lastSeekSettledGeneration:
          lastSeekSettledGeneration ?? this.lastSeekSettledGeneration,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MediaForgePlayerValue &&
      other.isInitialized == isInitialized &&
      other.isPlaying == isPlaying &&
      other.isBuffering == isBuffering &&
      other.isCompleted == isCompleted &&
      other.duration == duration &&
      other.position == position &&
      other.buffered == buffered &&
      other.bufferedPosition == bufferedPosition &&
      listEquals(other.bufferedRanges, bufferedRanges) &&
      other.bufferedAhead == bufferedAhead &&
      other.isRebuffering == isRebuffering &&
      other.isPreloading == isPreloading &&
      other.packetBufferedDuration == packetBufferedDuration &&
      other.packetBufferedBytes == packetBufferedBytes &&
      other.decodedVideoFrames == decodedVideoFrames &&
      other.decodedFrameMemoryBytes == decodedFrameMemoryBytes &&
      other.volume == volume &&
      other.isMuted == isMuted &&
      other.playbackRate == playbackRate &&
      other.videoWidth == videoWidth &&
      other.videoHeight == videoHeight &&
      other.rotationDegrees == rotationDegrees &&
      other.errorDescription == errorDescription &&
      listEquals(other.audioTracks, audioTracks) &&
      listEquals(other.subtitleTracks, subtitleTracks) &&
      listEquals(other.videoTracks, videoTracks) &&
      other.selectedAudioTrackId == selectedAudioTrackId &&
      other.selectedSubtitleTrackId == selectedSubtitleTrackId &&
      other.selectedVideoTrackId == selectedVideoTrackId &&
      other.subtitleDelay == subtitleDelay &&
      other.subtitlesEnabled == subtitlesEnabled &&
      other.firstFramePresented == firstFramePresented &&
      other.activeSeekGeneration == activeSeekGeneration &&
      other.lastSeekSettledGeneration == lastSeekSettledGeneration;

  @override
  int get hashCode => Object.hashAll([
        isInitialized,
        isPlaying,
        isBuffering,
        isCompleted,
        duration,
        position,
        buffered,
        bufferedPosition,
        Object.hashAll(bufferedRanges),
        bufferedAhead,
        isRebuffering,
        isPreloading,
        packetBufferedDuration,
        packetBufferedBytes,
        decodedVideoFrames,
        decodedFrameMemoryBytes,
        volume,
        isMuted,
        playbackRate,
        videoWidth,
        videoHeight,
        rotationDegrees,
        errorDescription,
        Object.hashAll(audioTracks),
        Object.hashAll(subtitleTracks),
        Object.hashAll(videoTracks),
        selectedAudioTrackId,
        selectedSubtitleTrackId,
        selectedVideoTrackId,
        subtitleDelay,
        subtitlesEnabled,
        firstFramePresented,
        activeSeekGeneration,
        lastSeekSettledGeneration,
      ]);
}
