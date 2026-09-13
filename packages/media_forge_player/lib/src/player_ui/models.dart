import 'package:flutter/foundation.dart';

/// How the video frame maps into the surface (UI-level display fit).
enum MediaPlayerFit {
  contain,
  cover,
  fill,
  original,
}

/// Chapter marker for the timeline (`chapters` are app-provided; the
/// engine does not expose container chapters).
@immutable
class MediaPlayerChapter {
  const MediaPlayerChapter({required this.title, required this.position});
  final String title;
  final Duration position;
}

/// Torrent/swarm statistics surfaced by the *application* (e.g. PeerStream).
///
/// Kept separate from the generic player API: `media_forge_player` never
/// sees torrent data. Pass a [ValueListenable] of this into
/// [MediaPlayerScreen.torrentStats] to enable the swarm section.
@immutable
class MediaPlayerTorrentStats {
  const MediaPlayerTorrentStats({
    this.downloadSpeedBps = 0,
    this.uploadSpeedBps = 0,
    this.peers = 0,
    this.seeds = 0,
    this.downloadedBytes = 0,
    this.totalBytes = 0,
    this.streamBufferMs = 0,
  });

  final int downloadSpeedBps;
  final int uploadSpeedBps;
  final int peers;
  final int seeds;
  final int downloadedBytes;
  final int totalBytes;

  /// Application-side readahead estimate (ms).
  final int streamBufferMs;

  double get progress =>
      totalBytes <= 0 ? 0 : downloadedBytes.clamp(0, totalBytes) / totalBytes;
}

/// Caption position inside the video surface.
enum PlayerSubtitlePosition { top, bottom }

/// Dart-side caption rendering preferences (no engine support needed).
@immutable
class MediaPlayerSubtitleStyle {
  const MediaPlayerSubtitleStyle({
    this.fontSize = 15,
    this.bold = false,
    this.backgroundOpacity = 0.65,
    this.position = PlayerSubtitlePosition.bottom,
  });

  final double fontSize;
  final bool bold;
  final double backgroundOpacity;
  final PlayerSubtitlePosition position;

  MediaPlayerSubtitleStyle copyWith({
    double? fontSize,
    bool? bold,
    double? backgroundOpacity,
    PlayerSubtitlePosition? position,
  }) {
    return MediaPlayerSubtitleStyle(
      fontSize: fontSize ?? this.fontSize,
      bold: bold ?? this.bold,
      backgroundOpacity: backgroundOpacity ?? this.backgroundOpacity,
      position: position ?? this.position,
    );
  }
}
