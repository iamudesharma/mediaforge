import 'package:flutter/foundation.dart';

/// Kind of media track inside a container.
enum MediaTrackKind { video, audio, subtitle }

/// Base class for discovered tracks.
@immutable
abstract class MediaForgeTrack {
  const MediaForgeTrack({
    required this.id,
    required this.kind,
    this.language,
    this.label,
    this.codec,
  });

  /// Stable id for [MediaForgePlayerController.selectAudioTrack] etc.
  /// For v1 this is the FFmpeg stream index when known, else 0-based order.
  final int id;
  final MediaTrackKind kind;
  final String? language;
  final String? label;
  final String? codec;
}

/// Audio track discovered in the opened media.
@immutable
class MediaForgeAudioTrack extends MediaForgeTrack {
  const MediaForgeAudioTrack({
    required super.id,
    super.language,
    super.label,
    super.codec,
    this.channels,
    this.sampleRate,
  }) : super(kind: MediaTrackKind.audio);

  final int? channels;
  final int? sampleRate;
}

/// Subtitle track (embedded or external).
@immutable
class MediaForgeSubtitleTrack extends MediaForgeTrack {
  const MediaForgeSubtitleTrack({
    required super.id,
    super.language,
    super.label,
    super.codec,
    this.isEmbedded = true,
    this.externalUri,
  }) : super(kind: MediaTrackKind.subtitle);

  /// `true` for in-container subtitles, `false` for sidecar files.
  final bool isEmbedded;

  /// Set for external (sidecar) subtitles.
  final Uri? externalUri;
}

/// Video track (usually one per file; exposed for completeness).
@immutable
class MediaForgeVideoTrack extends MediaForgeTrack {
  const MediaForgeVideoTrack({
    required super.id,
    super.language,
    super.label,
    super.codec,
    this.width,
    this.height,
  }) : super(kind: MediaTrackKind.video);

  final int? width;
  final int? height;
}
