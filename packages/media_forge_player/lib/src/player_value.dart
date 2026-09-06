import 'package:flutter/foundation.dart';

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
    this.volume = 1.0,
    this.isMuted = false,
    this.playbackRate = 1.0,
    this.videoWidth = 0,
    this.videoHeight = 0,
    this.rotationDegrees = 0,
    this.errorDescription,
    this.audioTracks = const [],
    this.subtitleTracks = const [],
    this.selectedAudioTrackId,
    this.selectedSubtitleTrackId,
    this.subtitleDelay = Duration.zero,
    this.subtitlesEnabled = true,
  });

  /// Nothing opened yet.
  static const uninitialized = MediaForgePlayerValue();

  final bool isInitialized;
  final bool isPlaying;
  final bool isBuffering;
  final bool isCompleted;
  final Duration duration;
  final Duration position;
  final Duration buffered;
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
  final int? selectedAudioTrackId;
  final int? selectedSubtitleTrackId;

  /// User subtitle delay (signed; applied by the engine at cue ingest).
  final Duration subtitleDelay;

  /// Gates cue delivery in `pollSubtitleText`.
  final bool subtitlesEnabled;

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
    int? selectedAudioTrackId,
    int? selectedSubtitleTrackId,
    Duration? subtitleDelay,
    bool? subtitlesEnabled,
    bool clearAudioSelection = false,
    bool clearSubtitleSelection = false,
  }) {
    return MediaForgePlayerValue(
      isInitialized: isInitialized ?? this.isInitialized,
      isPlaying: isPlaying ?? this.isPlaying,
      isBuffering: isBuffering ?? this.isBuffering,
      isCompleted: isCompleted ?? this.isCompleted,
      duration: duration ?? this.duration,
      position: position ?? this.position,
      buffered: buffered ?? this.buffered,
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
      selectedAudioTrackId: clearAudioSelection
          ? null
          : (selectedAudioTrackId ?? this.selectedAudioTrackId),
      selectedSubtitleTrackId: clearSubtitleSelection
          ? null
          : (selectedSubtitleTrackId ?? this.selectedSubtitleTrackId),
      subtitleDelay: subtitleDelay ?? this.subtitleDelay,
      subtitlesEnabled: subtitlesEnabled ?? this.subtitlesEnabled,
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
      other.volume == volume &&
      other.isMuted == isMuted &&
      other.playbackRate == playbackRate &&
      other.videoWidth == videoWidth &&
      other.videoHeight == videoHeight &&
      other.rotationDegrees == rotationDegrees &&
      other.errorDescription == errorDescription &&
      listEquals(other.audioTracks, audioTracks) &&
      listEquals(other.subtitleTracks, subtitleTracks) &&
      other.selectedAudioTrackId == selectedAudioTrackId &&
      other.selectedSubtitleTrackId == selectedSubtitleTrackId &&
      other.subtitleDelay == subtitleDelay &&
      other.subtitlesEnabled == subtitlesEnabled;

  @override
  int get hashCode => Object.hash(
        isInitialized,
        isPlaying,
        isBuffering,
        isCompleted,
        duration,
        position,
        buffered,
        volume,
        isMuted,
        playbackRate,
        videoWidth,
        videoHeight,
        rotationDegrees,
        errorDescription,
        Object.hashAll(audioTracks),
        Object.hashAll(subtitleTracks),
        selectedAudioTrackId,
        selectedSubtitleTrackId,
        subtitleDelay,
        subtitlesEnabled,
      );
}
