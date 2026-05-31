import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:video_forge/video_forge.dart';
import 'package:video_forge/video_forge.dart' as core;

/// Disk cache for thumbnail JPEG/WebP files keyed by input identity + seek params.
abstract final class ThumbnailCache {
  static const _cacheDirName = 'video_forge/thumb_cache';
  static const defaultMaxBytes = 256 * 1024 * 1024; // 256 MB
  static const defaultMissConcurrency = 2;

  static Directory? _root;

  /// Root directory for cached thumbnails (created on first use).
  static Future<Directory> rootDir() async {
    if (_root != null) return _root!;
    final base = await getTemporaryDirectory();
    _root = Directory(p.join(base.path, _cacheDirName));
    await _root!.create(recursive: true);
    return _root!;
  }

  static Future<void> _ensureInitialized() =>
      core.NativeBindings.ensureInitialized();

  static bool isNetworkInput(String input) {
    final lower = input.trim().toLowerCase();
    return lower.startsWith('http://') ||
        lower.startsWith('https://') ||
        lower.startsWith('rtmp://') ||
        lower.startsWith('rtsp://') ||
        lower.startsWith('ftp://');
  }

  /// Fingerprint for [input] used in cache keys (local mtime/size or normalized URL).
  static Future<String> inputFingerprint(String input) async {
    final trimmed = input.trim();
    if (isNetworkInput(trimmed)) {
      return _sha256Hex(_normalizeUrl(trimmed));
    }
    final file = File(trimmed);
    if (!await file.exists()) {
      return _sha256Hex(trimmed);
    }
    final stat = await file.stat();
    return _sha256Hex('${trimmed}|${stat.size}|${stat.modified.millisecondsSinceEpoch}');
  }

  /// Cache file for one thumbnail (creates on miss via [VideoProcessor.thumbnail]).
  static Future<File> getOrCreate({
    required String input,
    Duration position = Duration.zero,
    ThumbnailFormat format = ThumbnailFormat.jpeg,
    int? width,
    int? height,
    String? explicitOutputPath,
  }) async {
    final positionMs = position.inMilliseconds;
    final file = await _cacheFile(
      input: input,
      positionMs: positionMs,
      width: width,
      format: format,
    );
    if (await file.exists()) {
      return file;
    }
    await _ensureInitialized();
    await file.parent.create(recursive: true);
    final out = explicitOutputPath ?? file.path;
    await core.thumbnail(
      options: ThumbnailOptions(
        inputPath: input,
        outputPath: out,
        positionMs: BigInt.from(positionMs),
        width: width,
        height: height,
        format: format,
      ),
    );
    if (out != file.path) {
      await File(out).copy(file.path);
      try {
        await File(out).delete();
      } catch (_) {}
    }
    await _enforceMaxBytes();
    return file;
  }

  /// One cache file per [positions] entry (parallel misses, bounded concurrency).
  static Future<List<File>> batchGetOrCreate({
    required String input,
    required List<Duration> positions,
    ThumbnailFormat format = ThumbnailFormat.jpeg,
    int? width,
    int? height,
    int missConcurrency = defaultMissConcurrency,
  }) async {
    if (positions.isEmpty) return [];

    final fingerprint = await inputFingerprint(input);
    final files = <File>[];
    final misses = <int>[];

    for (var i = 0; i < positions.length; i++) {
      final file = await _cacheFileForFingerprint(
        fingerprint: fingerprint,
        positionMs: positions[i].inMilliseconds,
        width: width,
        format: format,
      );
      files.add(file);
      if (!await file.exists()) {
        misses.add(i);
      }
    }

    if (misses.isEmpty) {
      return files;
    }

    // Prefer one Rust batch pass for multiple misses on the same input.
    if (misses.length >= 2) {
      await _fillMissesViaBatch(
        input: input,
        positions: positions,
        misses: misses,
        files: files,
        fingerprint: fingerprint,
        format: format,
        width: width,
        height: height,
      );
      await _enforceMaxBytes();
      return files;
    }

    await _runWithConcurrency(
      misses,
      missConcurrency,
      (i) => getOrCreate(
        input: input,
        position: positions[i],
        format: format,
        width: width,
        height: height,
      ),
    );
    await _enforceMaxBytes();
    return files;
  }

  static Future<void> _fillMissesViaBatch({
    required String input,
    required List<Duration> positions,
    required List<int> misses,
    required List<File> files,
    required String fingerprint,
    required ThumbnailFormat format,
    int? width,
    int? height,
  }) async {
    final missPositions = misses.map((i) => positions[i]).toList();
    final outputPaths = misses.map((i) => files[i].path).toList();
    for (final path in outputPaths) {
      await Directory(p.dirname(path)).create(recursive: true);
    }
    await _ensureInitialized();
    final result = await core.batchThumbnails(
      options: BatchThumbnailOptions(
        inputPath: input,
        outputDir: '',
        outputPaths: outputPaths,
        positionsMs: Uint64List.fromList(
          missPositions.map((d) => d.inMilliseconds).toList(),
        ),
        width: width,
        height: height,
        format: format,
      ),
    );
    if (result.paths.length != misses.length) {
      throw StateError(
        'batchThumbnails returned ${result.paths.length} paths for ${misses.length} positions',
      );
    }
    for (var j = 0; j < misses.length; j++) {
      if (!await files[misses[j]].exists()) {
        throw StateError(
          'batch thumbnail missing on disk: ${files[misses[j]].path}',
        );
      }
    }
  }

  static Future<void> _runWithConcurrency(
    List<int> indices,
    int concurrency,
    Future<File> Function(int index) work,
  ) async {
    if (indices.isEmpty) return;
    final limit = concurrency.clamp(1, indices.length);
    var next = 0;
    Future<void> worker() async {
      while (true) {
        final slot = next;
        next++;
        if (slot >= indices.length) return;
        await work(indices[slot]);
      }
    }

    await Future.wait(List.generate(limit, (_) => worker()));
  }

  /// Remove all cached thumbnails for this [input] fingerprint.
  static Future<void> evictForInput(String input) async {
    final fingerprint = await inputFingerprint(input);
    final root = await rootDir();
    final prefix = '${fingerprint}_';
    await for (final entity in root.list()) {
      if (entity is File && p.basename(entity.path).startsWith(prefix)) {
        try {
          await entity.delete();
        } catch (_) {}
      }
    }
  }

  /// Clear the entire thumbnail cache directory.
  static Future<void> evictAll() async {
    final root = await rootDir();
    if (await root.exists()) {
      try {
        await root.delete(recursive: true);
      } catch (_) {}
    }
    _root = null;
  }

  /// Delete oldest files until total cache size is under [maxBytes].
  static Future<void> enforceMaxBytes([int maxBytes = defaultMaxBytes]) async {
    await _enforceMaxBytes(maxBytes);
  }

  static Future<File> _cacheFile({
    required String input,
    required int positionMs,
    int? width,
    required ThumbnailFormat format,
  }) async {
    final fingerprint = await inputFingerprint(input);
    return _cacheFileForFingerprint(
      fingerprint: fingerprint,
      positionMs: positionMs,
      width: width,
      format: format,
    );
  }

  static Future<File> _cacheFileForFingerprint({
    required String fingerprint,
    required int positionMs,
    int? width,
    required ThumbnailFormat format,
  }) async {
    final root = await rootDir();
    final ext = format == ThumbnailFormat.webp ? 'webp' : 'jpg';
    final w = width ?? 0;
    final name = '${fingerprint}_${positionMs}_${w}.$ext';
    return File(p.join(root.path, name));
  }

  static Future<void> _enforceMaxBytes([int maxBytes = defaultMaxBytes]) async {
    final root = await rootDir();
    if (!await root.exists()) return;

    final entries = <({File file, int modified, int size})>[];
    var total = 0;
    await for (final entity in root.list()) {
      if (entity is! File) continue;
      final stat = await entity.stat();
      total += stat.size;
      entries.add((
        file: entity,
        modified: stat.modified.millisecondsSinceEpoch,
        size: stat.size,
      ));
    }

    if (total <= maxBytes) return;

    entries.sort((a, b) => a.modified.compareTo(b.modified));
    for (final e in entries) {
      if (total <= maxBytes) break;
      try {
        await e.file.delete();
        total -= e.size;
      } catch (_) {}
    }
  }

  static String _normalizeUrl(String url) {
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

  static String _sha256Hex(String value) {
    return sha256.convert(utf8.encode(value)).toString();
  }
}
