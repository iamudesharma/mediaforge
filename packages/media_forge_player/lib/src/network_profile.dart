import 'package:flutter/foundation.dart';

import 'media_source.dart';

/// Source/network profile abstraction.
///
/// FFmpeg/libavformat remains responsible for actual reads — Dart never
/// fetches media bytes. The profile only tunes timeouts, reconnect policy,
/// probing budgets and seek assumptions handed to the engine.
@immutable
class MediaForgeNetworkProfile {
  const MediaForgeNetworkProfile({
    required this.timeout,
    required this.reconnect,
    required this.isSeekableRange,
    required this.allowRedirects,
    required this.fastProbeBytes,
    required this.largeProbeBytes,
    required this.fastAnalyzeMs,
    required this.largeAnalyzeMs,
    this.name = 'custom',
  });

  /// PeerStream-style localhost Range streaming (e.g. torrent servers).
  ///
  /// * ~60 s read timeout
  /// * reconnect enabled
  /// * seekable Range input assumptions
  /// * optimized fast initial probe for local HTTP streaming
  const MediaForgeNetworkProfile.torrentLocalhost({
    Duration timeout = const Duration(seconds: 60),
    bool reconnect = true,
  }) : this(
          timeout: timeout,
          reconnect: reconnect,
          isSeekableRange: true,
          allowRedirects: true,
          fastProbeBytes: 1 * 1024 * 1024,
          largeProbeBytes: 20 * 1024 * 1024,
          fastAnalyzeMs: 1000,
          largeAnalyzeMs: 5000,
          name: 'torrent_localhost',
        );

  /// Direct HTTP(S) with caller headers.
  ///
  /// * ~30 s timeout
  /// * caller headers preserved
  /// * reconnect controlled by caller/config
  /// * normal redirects
  const MediaForgeNetworkProfile.directHttp({
    Duration timeout = const Duration(seconds: 30),
    bool reconnect = false,
  }) : this(
          timeout: timeout,
          reconnect: reconnect,
          isSeekableRange: true,
          allowRedirects: true,
          fastProbeBytes: 2 * 1024 * 1024,
          largeProbeBytes: 20 * 1024 * 1024,
          fastAnalyzeMs: 2000,
          largeAnalyzeMs: 8000,
          name: 'direct_http',
        );

  /// Cached/file content: opened as a file, no network options.
  const MediaForgeNetworkProfile.cachedFile()
      : this(
          timeout: Duration.zero,
          reconnect: false,
          isSeekableRange: true,
          allowRedirects: false,
          fastProbeBytes: 1 * 1024 * 1024,
          largeProbeBytes: 20 * 1024 * 1024,
          fastAnalyzeMs: 1000,
          largeAnalyzeMs: 5000,
          name: 'cached_file',
        );

  /// Read timeout for open/handshake (zero = engine default / file).
  final Duration timeout;

  /// Whether libavformat reconnect options are enabled.
  final bool reconnect;

  /// Whether the source is assumed seekable via HTTP Range.
  final bool isSeekableRange;

  /// Whether HTTP redirects are followed.
  final bool allowRedirects;

  /// Fast initial probe budget (bytes) for seekable file-like sources.
  final int fastProbeBytes;

  /// Fallback larger probe budget when metadata is incomplete.
  final int largeProbeBytes;

  /// Fast initial analyze duration (ms).
  final int fastAnalyzeMs;

  /// Fallback larger analyze duration (ms).
  final int largeAnalyzeMs;

  final String name;

  /// Infer a sensible profile for [media].
  static MediaForgeNetworkProfile inferFor(
    MediaForgeMedia media, {
    MediaForgeNetworkProfile? configured,
    Duration? callerTimeout,
    bool? callerReconnect,
  }) {
    switch (media) {
      case MediaForgeFile():
        return const MediaForgeNetworkProfile.cachedFile();
      case MediaForgeAsset():
        return const MediaForgeNetworkProfile.cachedFile();
      case MediaForgeNetwork(:final url):
        final uri = Uri.tryParse(url);
        final loopback = uri != null &&
            (uri.host == '127.0.0.1' ||
                uri.host == 'localhost' ||
                uri.host == '::1');
        if (loopback) {
          // Torrent-localhost defaults win for loopback: ~60 s + reconnect.
          // Caller-explicit timeout/reconnect still override.
          final timeout = callerTimeout ?? const Duration(seconds: 60);
          final reconnect = callerReconnect ?? true;
          // Preserve probe tuning from the configured profile when present.
          final base = configured;
          if (base != null) {
            return base.copyWith(
              timeout: timeout,
              reconnect: reconnect,
              isSeekableRange: true,
              allowRedirects: true,
              name: 'torrent_localhost',
            );
          }
          return MediaForgeNetworkProfile.torrentLocalhost(
            timeout: timeout,
            reconnect: reconnect,
          );
        }
        return MediaForgeNetworkProfile.directHttp(
          timeout: callerTimeout ??
              configured?.timeout ??
              const Duration(seconds: 30),
          reconnect: callerReconnect ?? configured?.reconnect ?? false,
        );
    }
  }

  MediaForgeNetworkProfile copyWith({
    Duration? timeout,
    bool? reconnect,
    bool? isSeekableRange,
    bool? allowRedirects,
    int? fastProbeBytes,
    int? largeProbeBytes,
    int? fastAnalyzeMs,
    int? largeAnalyzeMs,
    String? name,
  }) {
    return MediaForgeNetworkProfile(
      timeout: timeout ?? this.timeout,
      reconnect: reconnect ?? this.reconnect,
      isSeekableRange: isSeekableRange ?? this.isSeekableRange,
      allowRedirects: allowRedirects ?? this.allowRedirects,
      fastProbeBytes: fastProbeBytes ?? this.fastProbeBytes,
      largeProbeBytes: largeProbeBytes ?? this.largeProbeBytes,
      fastAnalyzeMs: fastAnalyzeMs ?? this.fastAnalyzeMs,
      largeAnalyzeMs: largeAnalyzeMs ?? this.largeAnalyzeMs,
      name: name ?? this.name,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MediaForgeNetworkProfile &&
      other.timeout == timeout &&
      other.reconnect == reconnect &&
      other.isSeekableRange == isSeekableRange &&
      other.allowRedirects == allowRedirects &&
      other.fastProbeBytes == fastProbeBytes &&
      other.largeProbeBytes == largeProbeBytes &&
      other.fastAnalyzeMs == fastAnalyzeMs &&
      other.largeAnalyzeMs == largeAnalyzeMs &&
      other.name == name;

  @override
  int get hashCode => Object.hash(
        timeout,
        reconnect,
        isSeekableRange,
        allowRedirects,
        fastProbeBytes,
        largeProbeBytes,
        fastAnalyzeMs,
        largeAnalyzeMs,
        name,
      );

  @override
  String toString() =>
      'MediaForgeNetworkProfile($name, timeout=${timeout.inSeconds}s, reconnect=$reconnect)';
}
