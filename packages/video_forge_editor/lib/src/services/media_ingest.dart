import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:video_forge_kit/video_forge_kit.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'package:video_forge_editor/src/services/video_input.dart';

import 'remote_ingest_cache.dart';

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
    this.normalizedPathFuture,
    this.cacheKey,
    this.resumePositionMs = 0,
    this.cacheHit = false,
  });

  final MediaIngestPhase phase;
  final String? stablePath;
  final MediaInfo? info;
  final String? error;
  final bool skippedCopy;

  /// Cache key when the source came from [RemoteIngestCache] (null for
  /// local files / FFmpeg-prefetch fallbacks). Pass back via
  /// `VideoForgeEditorConfig.cacheKey` so the editor can persist resume
  /// position and skip re-downloads on reopen.
  final String? cacheKey;

  /// Last saved playback position for [cacheKey] (0 = start).
  final int resumePositionMs;

  /// True when the source was served from disk without network.
  final bool cacheHit;

  MediaIngestResult copyWith({
    MediaIngestPhase? phase,
    String? stablePath,
    MediaInfo? info,
    String? error,
    bool? skippedCopy,
    Future<String>? normalizedPathFuture,
    String? cacheKey,
    int? resumePositionMs,
    bool? cacheHit,
  }) {
    return MediaIngestResult(
      phase: phase ?? this.phase,
      stablePath: stablePath ?? this.stablePath,
      info: info ?? this.info,
      error: error ?? this.error,
      skippedCopy: skippedCopy ?? this.skippedCopy,
      normalizedPathFuture: normalizedPathFuture ?? this.normalizedPathFuture,
      cacheKey: cacheKey ?? this.cacheKey,
      resumePositionMs: resumePositionMs ?? this.resumePositionMs,
      cacheHit: cacheHit ?? this.cacheHit,
    );
  }

  /// If non-null, audio normalization to AAC is running in the background.
  /// Await this future to get the normalized path. Until it completes,
  /// [stablePath] contains the original (possibly non-AAC) copy which still
  /// works for timeline placement but may need the AAC path for export mux.
  final Future<String>? normalizedPathFuture;
}

abstract final class MediaIngest {
  /// Default ingest segment under app documents.
  static const defaultIngestSegment = 'video_forge_editor/ingest';

  static String _ingestSegmentOverride = defaultIngestSegment;

  static void configure({String ingestSegment = defaultIngestSegment}) {
    _ingestSegmentOverride = ingestSegment;
    RemoteIngestCache.configure(ingestSegment: ingestSegment);
  }

  static String get _activeIngestSegment => _ingestSegmentOverride;

  /// Directory for stable ingested copies under app documents.
  static Future<Directory> ingestDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, _activeIngestSegment));
    await dir.create(recursive: true);
    return dir;
  }

  static bool isUnderIngestDir(String path) {
    return path.contains(_activeIngestSegment);
  }

  /// Copy [sourcePath] to a stable location (or return as-is if already ingested).
  ///
  /// When [cacheRemoteLocally] is true, remote URLs are downloaded once into
  /// a URL-keyed cache ([RemoteIngestCache]) with HTTP Range resume, so
  /// reopening a video you already watched is a disk hit. Streaming
  /// playlists fall back to the FFmpeg stream-copy prefetch.
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
        // Stable URL-keyed cache with Range resume: reopening a video you
        // already watched is a disk hit instead of a full re-download.
        try {
          final entry = await RemoteIngestCache.fetch(
            trimmed,
            onStatus: onStatus,
          );
          onStatus?.call(entry.cacheHit
              ? 'Cache hit — probing local copy…'
              : 'Cached — probing local copy…');
          final probed = await probeOnly(
            entry.filePath,
            onStatus: onStatus,
            skippedCopy: false,
          );
          if (probed.phase != MediaIngestPhase.ready) return probed;
          final resume =
              await RemoteIngestCache.lastPositionMs(entry.cacheKey);
          debugPrint('[MediaIngest] remote cache key=${entry.cacheKey} '
              'hit=${entry.cacheHit} resumedFrom=${entry.resumedFromBytes} '
              'resumePositionMs=$resume');
          return probed.copyWith(
            cacheKey: entry.cacheKey,
            resumePositionMs: resume,
            cacheHit: entry.cacheHit,
          );
        } on RemoteCacheStreamingSource {
          // Playlists/streams cannot be byte-cached — fall through to the
          // FFmpeg stream-copy prefetch below.
          debugPrint('[MediaIngest] streaming source, FFmpeg prefetch: $trimmed');
        } catch (e) {
          return MediaIngestResult(
            phase: MediaIngestPhase.failed,
            error: 'Remote cache failed: $e',
          );
        }
        onStatus?.call('Caching remote video locally…');
        String local;
        try {
          await VideoProcessor.initialize();
          final dir = await ingestDir();
          local = await VideoProcessor.prefetchRemoteInput(
            url: trimmed,
            destDir: dir.path,
          );
        } catch (e) {
          return MediaIngestResult(
            phase: MediaIngestPhase.failed,
            error: 'Remote cache failed: $e',
          );
        }
        onStatus?.call('Cached — probing local copy…');
        return probeOnly(local, onStatus: onStatus, skippedCopy: false);
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
          'Use the sample chips or another public video URL.';
    }
    if (msg.contains('404') || msg.contains('Not Found')) {
      return 'HTTP 404 — URL not found. Check the link or try a sample chip.';
    }
    return 'Probe failed: $e';
  }

  /// Copy a picked audio file to stable app storage, then probe duration.
  static Future<MediaIngestResult> ingestLocalAudio(
    String sourcePath, {
    void Function(String status)? onStatus,
  }) async {
    final trimmed = sourcePath.trim();
    if (trimmed.isEmpty) {
      return const MediaIngestResult(
        phase: MediaIngestPhase.failed,
        error: 'Empty path',
      );
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

    onStatus?.call('Copying audio to app storage…');
    String stablePath;
    try {
      stablePath = await _copyToIngest(trimmed, defaultExt: '.m4a');
    } catch (e) {
      return MediaIngestResult(
        phase: MediaIngestPhase.failed,
        error: 'Copy failed: $e',
      );
    }

    onStatus?.call('Probing audio codec…');
    final probe = await probeOnly(stablePath, onStatus: null, skippedCopy: false);
    if (probe.phase != MediaIngestPhase.ready || probe.info == null) {
      return probe;
    }

    final codec = probe.info!.audioCodec?.toLowerCase() ?? '';
    // Normalize anything that isn't native AAC/ALAC (e.g. OPUS, FLAC, VBR MP3).
    // Kick off normalization as a background future so the caller can add the
    // audio clip to the timeline immediately without waiting.
    if (codec != 'aac' && codec != 'alac' && codec.isNotEmpty) {
      final pathToNormalize = stablePath;
      final info = probe.info!;
      final normalizeFuture = _normalizeAudioToAac(pathToNormalize, info);
      return MediaIngestResult(
        phase: MediaIngestPhase.ready,
        stablePath: stablePath,
        info: info,
        skippedCopy: false,
        normalizedPathFuture: normalizeFuture,
      );
    }

    return probeOnly(
      stablePath,
      onStatus: onStatus,
      skippedCopy: false,
    );
  }

  /// Re-encodes [sourcePath] to AAC in a background isolate-friendly way.
  /// Returns the path to the normalized AAC file.
  static Future<String> _normalizeAudioToAac(
    String sourcePath,
    MediaInfo info,
  ) async {
    final dir = await ingestDir();
    final aacPath = p.join(dir.path, 'norm_${const Uuid().v4()}.m4a');
    final job = await VideoProcessor.compressJob(
      input: sourcePath,
      output: aacPath,
      audioTracks: [
        AudioTrackInput(
          sourcePath: sourcePath,
          sourceStartMs: BigInt.zero,
          durationMs: info.durationMs,
          timelineStartMs: BigInt.zero,
          volume: 1.0,
          muted: false,
        )
      ],
      muteOriginalAudio: true,
      includeAudio: true,
    );
    await job.result;
    return aacPath;
  }

  static Future<String> _copyToIngest(
    String sourcePath, {
    String defaultExt = '.mp4',
  }) async {
    final src = File(sourcePath);
    final ext = p.extension(sourcePath);
    final safeExt = ext.isNotEmpty ? ext : defaultExt;
    final dir = await ingestDir();
    final dest = p.join(dir.path, '${const Uuid().v4()}$safeExt');
    await src.copy(dest);
    return dest;
  }
}
