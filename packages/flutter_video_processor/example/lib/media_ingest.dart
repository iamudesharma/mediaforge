import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_video_processor/flutter_video_processor.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'video_input.dart';

/// Local ingest lifecycle for stable FFmpeg input paths (esp. iOS Photos temps).
enum MediaIngestPhase {
  idle,
  copying,
  probing,
  ready,
  failed,
}

class MediaIngestResult {
  const MediaIngestResult({
    required this.phase,
    this.stablePath,
    this.info,
    this.error,
    this.skippedCopy = false,
  });

  final MediaIngestPhase phase;
  final String? stablePath;
  final MediaInfo? info;
  final String? error;
  final bool skippedCopy;
}

abstract final class MediaIngest {
  static const _ingestSegment = 'flutter_video_processor/ingest';

  /// Directory for stable ingested copies under app documents.
  static Future<Directory> ingestDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, _ingestSegment));
    await dir.create(recursive: true);
    return dir;
  }

  static bool isUnderIngestDir(String path) {
    return path.contains(_ingestSegment);
  }

  /// Copy [sourcePath] to a stable location (or return as-is if already ingested).
  ///
  /// When [cacheRemoteLocally] is true, remote URLs are stream-copied into [ingestDir]
  /// once so later compress/thumbnail jobs use a local path.
  static Future<MediaIngestResult> ingestLocalVideo(
    String sourcePath, {
    void Function(String status)? onStatus,
    bool cacheRemoteLocally = false,
  }) async {
    final trimmed = sourcePath.trim();
    if (trimmed.isEmpty) {
      return const MediaIngestResult(
        phase: MediaIngestPhase.failed,
        error: 'Empty path',
      );
    }

    if (VideoInput.isNetworkUrl(trimmed)) {
      if (cacheRemoteLocally) {
        onStatus?.call('Caching remote video locally…');
        try {
          await VideoProcessor.initialize();
          final dir = await ingestDir();
          final local = await VideoProcessor.prefetchRemoteInput(
            url: trimmed,
            destDir: dir.path,
          );
          onStatus?.call('Cached — probing local copy…');
          return probeOnly(local, onStatus: onStatus, skippedCopy: false);
        } catch (e) {
          return MediaIngestResult(
            phase: MediaIngestPhase.failed,
            error: 'Remote cache failed: $e',
          );
        }
      }
      onStatus?.call('Using remote URL (no local copy)…');
      return probeOnly(trimmed, onStatus: onStatus);
    }

    if (!kIsWeb && !File(trimmed).existsSync()) {
      return MediaIngestResult(
        phase: MediaIngestPhase.failed,
        error: 'File not found: $trimmed',
      );
    }

    if (isUnderIngestDir(trimmed)) {
      onStatus?.call('Already ingested — probing…');
      return probeOnly(trimmed, onStatus: onStatus, skippedCopy: true);
    }

    onStatus?.call('Copying video to app storage…');
    String stablePath;
    try {
      stablePath = await _copyToIngest(trimmed);
    } catch (e) {
      return MediaIngestResult(
        phase: MediaIngestPhase.failed,
        error: 'Copy failed: $e',
      );
    }

    return probeOnly(
      stablePath,
      onStatus: onStatus,
      skippedCopy: false,
    );
  }

  static Future<MediaIngestResult> probeOnly(
    String path, {
    void Function(String status)? onStatus,
    bool skippedCopy = false,
  }) async {
    onStatus?.call('Probing video…');
    try {
      await VideoProcessor.initialize();
      final info = await VideoProcessor.getMediaInfo(path);
      return MediaIngestResult(
        phase: MediaIngestPhase.ready,
        stablePath: path,
        info: info,
        skippedCopy: skippedCopy,
      );
    } catch (e) {
      return MediaIngestResult(
        phase: MediaIngestPhase.failed,
        stablePath: path,
        error: _friendlyProbeError(e),
      );
    }
  }

  static String _friendlyProbeError(Object e) {
    final msg = e.toString();
    if (msg.contains('403') || msg.contains('Forbidden')) {
      return 'HTTP 403 Forbidden — this server blocks direct MP4 access. '
          'Use the Big Buck Bunny sample chips or another public video URL.';
    }
    if (msg.contains('404') || msg.contains('Not Found')) {
      return 'HTTP 404 — URL not found. Check the link or try a sample chip.';
    }
    return 'Probe failed: $e';
  }

  static Future<String> _copyToIngest(String sourcePath) async {
    final src = File(sourcePath);
    final ext = p.extension(sourcePath);
    final safeExt = ext.isNotEmpty ? ext : '.mp4';
    final dir = await ingestDir();
    final dest = p.join(dir.path, '${const Uuid().v4()}$safeExt');
    await src.copy(dest);
    return dest;
  }
}
