import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// URL-keyed disk cache for progressive remote video downloads.
///
/// Problem this solves: `prefetch_remote_input` (Rust) mints a fresh
/// `{uuid}_prefetch.mp4` on every call, so reopening a video you already
/// watched five minutes of re-downloads from byte 0. This cache stores one
/// stable file per normalized URL and **resumes** partial downloads with
/// HTTP `Range` requests, so the second open is a cache hit and an
/// interrupted first open continues where it stopped.
///
/// Design notes:
///
/// * Dart `HttpClient` does the byte transfer (no new deps, no FRB regen).
///   Files are raw server bytes — no remux — so resume is exact.
/// * Streaming playlists (`m3u8`/`mpd`/`rtmp`/`rtsp`) cannot be byte-resumed;
///   [fetch] throws [RemoteCacheStreamingSource] and callers fall back to
///   the FFmpeg stream-copy prefetch.
/// * Playback position memory (`savePosition` / [lastPositionMs]) lives in
///   the same sidecar JSON so reopen can also seek to where you stopped.
///   Throttling saves is the caller's job (save on pause/dispose, not per
///   frame).
///
/// Layout under the ingest dir (`<docs>/<ingestSegment>/remote_cache/`):
/// `{key}.mp4` (complete), `{key}.part` (partial), `{key}.json` (sidecar).
abstract final class RemoteIngestCache {
  /// Default ingest segment (mirrors `MediaIngest`).
  static const defaultIngestSegment = 'video_forge_editor/ingest';

  static const _remoteDirName = 'remote_cache';

  /// LRU budget for completed downloads (partial `.part` files are never
  /// evicted by the budget pass).
  static const defaultMaxBytes = 2 * 1024 * 1024 * 1024; // 2 GB

  static String _ingestSegment = defaultIngestSegment;

  @visibleForTesting
  static Directory? testDirOverride;

  /// Point the cache at a different ingest segment (called next to
  /// `MediaIngest.configure`).
  static void configure({String ingestSegment = defaultIngestSegment}) {
    _ingestSegment = ingestSegment;
  }

  /// Cache directory, creating it on first use.
  static Future<Directory> cacheDir() async {
    final override = testDirOverride;
    if (override != null) {
      await override.create(recursive: true);
      return override;
    }
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, _ingestSegment, _remoteDirName));
    await dir.create(recursive: true);
    return dir;
  }

  /// Stable key for [url] (normalized + host-prefixed FNV-1a hash).
  static String cacheKeyFor(String url) {
    final normalized = normalizeUrl(url.trim());
    final uri = Uri.tryParse(normalized);
    final host = (uri?.host ?? 'remote')
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9-]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final shortHost = host.isEmpty
        ? 'remote'
        : host.substring(0, host.length > 24 ? 24 : host.length);
    return '${shortHost}_${_fnv1aHex(normalized)}';
  }

  /// Normalize a URL the same way the thumbnail cache does (Google hosts
  /// http → https) so equivalent URLs share one entry.
  static String normalizeUrl(String url) {
    final trimmed = url.trim();
    final lower = trimmed.toLowerCase();
    if (trimmed.startsWith('http://') &&
        (lower.contains('googleapis.com') ||
            lower.contains('googleusercontent.com') ||
            lower.contains('gstatic.com'))) {
      return trimmed.replaceFirst(
        RegExp(r'^http://', caseSensitive: false),
        'https://',
      );
    }
    return trimmed;
  }

  /// True for playlist/streaming protocols that cannot be byte-resumed.
  static bool isStreamingSource(String url) {
    final lower = url.trim().toLowerCase().split('?').first;
    return lower.endsWith('.m3u8') ||
        lower.endsWith('.mpd') ||
        lower.startsWith('rtmp://') ||
        lower.startsWith('rtsp://');
  }

  /// Download [url] into the cache, resuming any partial file.
  ///
  /// Returns the complete local file. A second call for the same URL is a
  /// cache hit (no network). Throws [RemoteCacheStreamingSource] for
  /// playlists/streams and [RemoteCacheFailure] for HTTP/IO errors.
  static Future<RemoteCacheEntry> fetch(
    String url, {
    void Function(String status)? onStatus,
    HttpClient? client,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      throw const RemoteCacheFailure('Empty URL');
    }
    final lower = trimmed.toLowerCase();
    if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
      throw RemoteCacheFailure('Not a remote URL: $trimmed');
    }
    if (isStreamingSource(trimmed)) {
      throw RemoteCacheStreamingSource(trimmed);
    }

    final key = cacheKeyFor(trimmed);
    final dir = await cacheDir();
    final complete = File(p.join(dir.path, '$key.mp4'));
    final part = File(p.join(dir.path, '$key.part'));
    var meta = await _readMeta(dir, key, trimmed);

    // Fast path: complete file already on disk.
    if (await complete.exists()) {
      final size = await complete.length();
      final total = meta.totalBytes;
      if (size > 0 && (total == null || total <= 0 || size == total)) {
        meta = meta.touched();
        await _writeMeta(dir, key, meta);
        debugPrint(
            '[RemoteCache] hit key=$key bytes=$size url=${_shortUrl(trimmed)}');
        return RemoteCacheEntry(
          cacheKey: key,
          filePath: complete.path,
          cacheHit: true,
          resumedFromBytes: size,
          totalBytes: total ?? size,
          downloadedBytes: size,
        );
      }
      // Size mismatch (e.g. origin file changed) — re-download below.
      debugPrint(
          '[RemoteCache] size mismatch key=$key have=$size total=$total → refetch');
      try {
        await complete.delete();
      } catch (_) {}
    }

    final http = client ?? HttpClient();
    final ownedClient = client == null;
    try {
      http.connectionTimeout = timeout;
      return await _download(
        http: http,
        url: trimmed,
        key: key,
        dir: dir,
        complete: complete,
        part: part,
        meta: meta,
        onStatus: onStatus,
        timeout: timeout,
      );
    } finally {
      if (ownedClient) http.close(force: true);
    }
  }

  static Future<RemoteCacheEntry> _download({
    required HttpClient http,
    required String url,
    required String key,
    required Directory dir,
    required File complete,
    required File part,
    required RemoteCacheMeta meta,
    required void Function(String status)? onStatus,
    required Duration timeout,
  }) async {
    var have = await part.exists() ? await part.length() : 0;
    var m = meta;

    // HEAD to learn total size + resume support (best-effort; GET proceeds
    // regardless — many servers omit HEAD support).
    try {
      final headReq = await http.headUrl(Uri.parse(url)).timeout(timeout);
      final headRes = await headReq.close().timeout(timeout);
      await headRes.drain<void>();
      final total = headRes.contentLength >= 0 ? headRes.contentLength : null;
      final acceptRanges =
          headRes.headers.value(HttpHeaders.acceptRangesHeader);
      final etag = headRes.headers.value(HttpHeaders.etagHeader);
      m = m.withProbe(
        totalBytes: total,
        acceptRanges: acceptRanges?.toLowerCase().contains('bytes') ?? false,
        etag: etag,
      );
      if (etag != null && meta.etag != null && etag != meta.etag && have > 0) {
        debugPrint('[RemoteCache] etag changed key=$key → restart');
        try {
          await part.delete();
        } catch (_) {}
        have = 0;
      }
    } catch (e) {
      debugPrint('[RemoteCache] HEAD failed key=$key: $e');
    }

    if (have > 0 && !m.acceptRanges && (m.totalBytes ?? 0) > have) {
      debugPrint('[RemoteCache] no range support key=$key → restart');
      try {
        await part.delete();
      } catch (_) {}
      have = 0;
    }

    final resumedFrom = have;
    if (resumedFrom > 0) {
      onStatus?.call('Resuming download…');
      debugPrint('[RemoteCache] resume key=$key from=$resumedFrom');
    } else {
      onStatus?.call('Caching remote video locally…');
      debugPrint('[RemoteCache] fetch key=$key url=${_shortUrl(url)}');
    }

    final getReq = await http.getUrl(Uri.parse(url)).timeout(timeout);
    if (have > 0) {
      getReq.headers.set(HttpHeaders.rangeHeader, 'bytes=$have-');
    }
    final res = await getReq.close().timeout(timeout);
    final status = res.statusCode;

    if (status == HttpStatus.requestedRangeNotSatisfiable) {
      await res.drain<void>();
      // Already have everything (or origin shrank) — verify and promote.
      final total = m.totalBytes;
      if (total != null && have >= total && have > 0) {
        await _promote(part: part, complete: complete, have: have);
        m = m.withComplete(totalBytes: total, downloadedBytes: have);
        await _writeMeta(dir, key, m);
        await enforceMaxBytes(keepKey: key);
        debugPrint('[RemoteCache] complete (416) key=$key bytes=$have');
        return RemoteCacheEntry(
          cacheKey: key,
          filePath: complete.path,
          cacheHit: false,
          resumedFromBytes: resumedFrom,
          totalBytes: total,
          downloadedBytes: have,
        );
      }
      debugPrint('[RemoteCache] 416 key=$key have=$have total=$total → restart');
      try {
        await part.delete();
      } catch (_) {}
      have = 0;
      return _download(
        http: http,
        url: url,
        key: key,
        dir: dir,
        complete: complete,
        part: part,
        meta: m,
        onStatus: onStatus,
        timeout: timeout,
      );
    }

    final isPartial = status == HttpStatus.partialContent;
    if (status != HttpStatus.ok && !isPartial) {
      await res.drain<void>();
      throw RemoteCacheFailure('HTTP $status for ${_shortUrl(url)}');
    }
    if (have > 0 && !isPartial) {
      // Server ignored Range — restart from zero to avoid corrupt concat.
      debugPrint('[RemoteCache] range ignored (200) key=$key → restart');
      try {
        await part.delete();
      } catch (_) {}
      have = 0;
    }

    // Learn total from Content-Range (`bytes have-end/total`) or GET length.
    var total = m.totalBytes;
    final contentRange = res.headers.value(HttpHeaders.contentRangeHeader);
    if (contentRange != null) {
      final slash = contentRange.lastIndexOf('/');
      if (slash >= 0) {
        total = int.tryParse(contentRange.substring(slash + 1)) ?? total;
      }
    }
    total ??= res.contentLength >= 0 ? have + res.contentLength : null;

    final sink = part.openWrite(mode: have > 0 ? FileMode.append : FileMode.write);
    var written = have;
    try {
      await for (final chunk in res.timeout(timeout)) {
        sink.add(chunk);
        written += chunk.length;
      }
      await sink.flush();
    } catch (e) {
      try {
        await sink.close();
      } catch (_) {}
      m = m.withProgress(downloadedBytes: written, totalBytes: total);
      await _writeMeta(dir, key, m);
      throw RemoteCacheFailure('Download interrupted key=$key: $e');
    }
    await sink.close();

    if (total != null && total > 0 && written != total) {
      m = m.withProgress(downloadedBytes: written, totalBytes: total);
      await _writeMeta(dir, key, m);
      throw RemoteCacheFailure(
          'Incomplete download key=$key have=$written total=$total');
    }

    await _promote(part: part, complete: complete, have: written);
    m = m.withComplete(totalBytes: total ?? written, downloadedBytes: written);
    await _writeMeta(dir, key, m);
    await enforceMaxBytes(keepKey: key);
    debugPrint(
        '[RemoteCache] complete key=$key bytes=$written resumedFrom=$resumedFrom');
    return RemoteCacheEntry(
      cacheKey: key,
      filePath: complete.path,
      cacheHit: false,
      resumedFromBytes: resumedFrom,
      totalBytes: total ?? written,
      downloadedBytes: written,
    );
  }

  static Future<void> _promote({
    required File part,
    required File complete,
    required int have,
  }) async {
    if (await complete.exists()) {
      try {
        await complete.delete();
      } catch (_) {}
    }
    await part.rename(complete.path);
  }

  /// Last saved playback position for [cacheKey] (0 when unknown).
  static Future<int> lastPositionMs(String cacheKey) async {
    try {
      final dir = await cacheDir();
      final meta = await _readMeta(dir, cacheKey, '');
      return meta.lastPositionMs;
    } catch (_) {
      return 0;
    }
  }

  /// Remember playback position for [cacheKey] (call on pause/dispose, not
  /// per frame).
  static Future<void> savePosition(String cacheKey, int positionMs) async {
    if (positionMs < 0) return;
    try {
      final dir = await cacheDir();
      final meta = await _readMeta(dir, cacheKey, '');
      await _writeMeta(dir, cacheKey, meta.withPosition(positionMs));
    } catch (e) {
      debugPrint('[RemoteCache] savePosition failed key=$cacheKey: $e');
    }
  }

  /// Delete cached files for one URL.
  static Future<void> evictForUrl(String url) async {
    try {
      final dir = await cacheDir();
      final key = cacheKeyFor(url);
      for (final ext in ['.mp4', '.part', '.json']) {
        try {
          await File(p.join(dir.path, '$key$ext')).delete();
        } catch (_) {}
      }
    } catch (_) {}
  }

  /// Clear the whole remote-video cache.
  static Future<void> evictAll() async {
    try {
      final dir = await cacheDir();
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          try {
            await entity.delete(recursive: true);
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  /// Delete oldest complete files until under [maxBytes] (never the entry
  /// being fetched, never `.part` files).
  static Future<void> enforceMaxBytes({
    int maxBytes = defaultMaxBytes,
    String? keepKey,
  }) async {
    try {
      final dir = await cacheDir();
      if (!await dir.exists()) return;
      final entries = <({File file, int size, int modified, String key})>[];
      var total = 0;
      await for (final entity in dir.list()) {
        if (entity is! File || !entity.path.endsWith('.mp4')) continue;
        final stat = await entity.stat();
        total += stat.size;
        entries.add((
          file: entity,
          size: stat.size,
          modified: stat.modified.millisecondsSinceEpoch,
          key: p.basenameWithoutExtension(entity.path),
        ));
      }
      if (total <= maxBytes) return;
      entries.sort((a, b) => a.modified.compareTo(b.modified));
      for (final e in entries) {
        if (total <= maxBytes) break;
        if (e.key == keepKey) continue;
        try {
          await e.file.delete();
          try {
            await File(p.join(dir.path, '${e.key}.json')).delete();
          } catch (_) {}
          total -= e.size;
          debugPrint('[RemoteCache] evicted key=${e.key} bytes=${e.size}');
        } catch (_) {}
      }
    } catch (_) {}
  }

  static Future<RemoteCacheMeta> _readMeta(
    Directory dir,
    String key,
    String url,
  ) async {
    try {
      final file = File(p.join(dir.path, '$key.json'));
      if (!await file.exists()) return RemoteCacheMeta(url: url);
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map) return RemoteCacheMeta(url: url);
      return RemoteCacheMeta.fromJson(raw, fallbackUrl: url);
    } catch (_) {
      return RemoteCacheMeta(url: url);
    }
  }

  static Future<void> _writeMeta(
    Directory dir,
    String key,
    RemoteCacheMeta meta,
  ) async {
    try {
      await File(p.join(dir.path, '$key.json'))
          .writeAsString(jsonEncode(meta.toJson()));
    } catch (_) {}
  }

  static String _shortUrl(String url) =>
      url.length > 80 ? '${url.substring(0, 80)}…' : url;

  /// 64-bit FNV-1a hex (stable, no deps; BigInt keeps it unsigned —
  /// Dart ints are signed 64-bit so masking alone can stay negative).
  static String _fnv1aHex(String value) {
    var hash = BigInt.parse('cbf29ce484222325', radix: 16);
    final prime = BigInt.parse('100000001b3', radix: 16);
    final mask = BigInt.parse('ffffffffffffffff', radix: 16);
    for (final unit in utf8.encode(value)) {
      hash = ((hash ^ BigInt.from(unit)) * prime) & mask;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }
}

/// Result of [RemoteIngestCache.fetch].
@immutable
class RemoteCacheEntry {
  const RemoteCacheEntry({
    required this.cacheKey,
    required this.filePath,
    required this.cacheHit,
    required this.resumedFromBytes,
    required this.totalBytes,
    required this.downloadedBytes,
  });

  final String cacheKey;
  final String filePath;
  final bool cacheHit;
  final int resumedFromBytes;
  final int totalBytes;
  final int downloadedBytes;
}

/// Sidecar metadata for one cache key.
@immutable
class RemoteCacheMeta {
  const RemoteCacheMeta({
    this.url = '',
    this.totalBytes,
    this.downloadedBytes = 0,
    this.etag,
    this.acceptRanges = false,
    this.lastPositionMs = 0,
    this.updatedAtMs = 0,
  });

  final String url;
  final int? totalBytes;
  final int downloadedBytes;
  final String? etag;
  final bool acceptRanges;
  final int lastPositionMs;
  final int updatedAtMs;

  RemoteCacheMeta touched() => RemoteCacheMeta(
        url: url,
        totalBytes: totalBytes,
        downloadedBytes: downloadedBytes,
        etag: etag,
        acceptRanges: acceptRanges,
        lastPositionMs: lastPositionMs,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      );

  RemoteCacheMeta withProbe({
    int? totalBytes,
    required bool acceptRanges,
    String? etag,
  }) =>
      RemoteCacheMeta(
        url: url,
        totalBytes: totalBytes ?? this.totalBytes,
        downloadedBytes: downloadedBytes,
        etag: etag ?? this.etag,
        acceptRanges: acceptRanges,
        lastPositionMs: lastPositionMs,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      );

  RemoteCacheMeta withProgress({
    required int downloadedBytes,
    int? totalBytes,
  }) =>
      RemoteCacheMeta(
        url: url,
        totalBytes: totalBytes ?? this.totalBytes,
        downloadedBytes: downloadedBytes,
        etag: etag,
        acceptRanges: acceptRanges,
        lastPositionMs: lastPositionMs,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      );

  RemoteCacheMeta withComplete({
    required int totalBytes,
    required int downloadedBytes,
  }) =>
      RemoteCacheMeta(
        url: url,
        totalBytes: totalBytes,
        downloadedBytes: downloadedBytes,
        etag: etag,
        acceptRanges: acceptRanges,
        lastPositionMs: lastPositionMs,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      );

  RemoteCacheMeta withPosition(int positionMs) => RemoteCacheMeta(
        url: url,
        totalBytes: totalBytes,
        downloadedBytes: downloadedBytes,
        etag: etag,
        acceptRanges: acceptRanges,
        lastPositionMs: positionMs,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      );

  factory RemoteCacheMeta.fromJson(Map<dynamic, dynamic> json,
      {String fallbackUrl = ''}) {
    int? asInt(dynamic v) => v is int ? v : int.tryParse('$v');
    return RemoteCacheMeta(
      url: json['url'] is String && (json['url'] as String).isNotEmpty
          ? json['url'] as String
          : fallbackUrl,
      totalBytes: asInt(json['totalBytes']),
      downloadedBytes: asInt(json['downloadedBytes']) ?? 0,
      etag: json['etag'] is String ? json['etag'] as String : null,
      acceptRanges: json['acceptRanges'] == true,
      lastPositionMs: asInt(json['lastPositionMs']) ?? 0,
      updatedAtMs: asInt(json['updatedAtMs']) ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'url': url,
        'totalBytes': totalBytes,
        'downloadedBytes': downloadedBytes,
        'etag': etag,
        'acceptRanges': acceptRanges,
        'lastPositionMs': lastPositionMs,
        'updatedAtMs': updatedAtMs,
      };
}

/// Playlists/streams cannot be byte-cached — callers fall back to FFmpeg.
class RemoteCacheStreamingSource implements Exception {
  const RemoteCacheStreamingSource(this.url);
  final String url;
  @override
  String toString() => 'RemoteCacheStreamingSource($url)';
}

/// HTTP/IO failure during cache fetch.
class RemoteCacheFailure implements Exception {
  const RemoteCacheFailure(this.message);
  final String message;
  @override
  String toString() => 'RemoteCacheFailure($message)';
}
