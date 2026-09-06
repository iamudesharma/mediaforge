import 'package:flutter/foundation.dart';

/// Media to open with [MediaForgePlayerController.open].
///
/// The player never fetches bytes in Dart. [MediaForgeMedia.network] URLs
/// are handed to FFmpeg inside `media_forge` so seeking issues HTTP Range
/// requests (required for PeerStream-style `127.0.0.1` servers).
@immutable
sealed class MediaForgeMedia {
  const MediaForgeMedia();

  /// Local file path (MP4, MKV, MOV, WebM, …).
  const factory MediaForgeMedia.file(String path) = MediaForgeFile._;

  /// Seekable HTTP/HTTPS URL, including localhost range servers.
  ///
  /// [headers] are stored on the source and forwarded to the engine once
  /// `media_forge` gains an `open_url` with options (v1 logs them and
  /// opens the URL directly; FFmpeg sends default Range headers).
  const factory MediaForgeMedia.network(
    String url, {
    Map<String, String> headers,
  }) = MediaForgeNetwork._;

  /// Flutter asset (`assets/...` or `packages/...`). Copied to a temp file
  /// on open because the engine opens filesystem paths.
  const factory MediaForgeMedia.asset(String assetKey) = MediaForgeAsset._;
}

/// Local file source.
@immutable
final class MediaForgeFile extends MediaForgeMedia {
  const MediaForgeFile._(this.path) : assert(path.length > 0);
  final String path;
}

/// Seekable network source.
@immutable
final class MediaForgeNetwork extends MediaForgeMedia {
  const MediaForgeNetwork._(this.url, {this.headers = const {}})
    : assert(url.length > 0);
  final String url;
  final Map<String, String> headers;

  /// `true` for PeerStream-style localhost servers.
  bool get isLoopback {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    return uri.host == '127.0.0.1' ||
        uri.host == 'localhost' ||
        uri.host == '::1';
  }
}

/// Bundled asset source.
@immutable
final class MediaForgeAsset extends MediaForgeMedia {
  const MediaForgeAsset._(this.assetKey) : assert(assetKey.length > 0);
  final String assetKey;
}
