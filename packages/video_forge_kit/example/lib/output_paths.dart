import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Resolves writable output folders for the example app.
///
/// Prefers [example/output/compress_video] and [example/output/thumbnail]
/// inside the project when the process can write there (typical `flutter run`).
/// Falls back to the app documents directory when sandbox blocks project writes.
class OutputPaths {
  OutputPaths._({
    required this.root,
    required this.compressVideoDir,
    required this.thumbnailDir,
    required this.statusDir,
    required this.isProjectLocal,
  });

  final String root;
  final String compressVideoDir;
  final String thumbnailDir;
  final String statusDir;

  /// True when outputs live under `example/output/` in the repo.
  final bool isProjectLocal;

  static OutputPaths? _cached;

  /// Call after picking a new file so paths are not reused from a prior session.
  static void clearCache() => _cached = null;

  static Future<OutputPaths> resolve() async {
    if (_cached != null) return _cached!;

    // Phones cannot write to the dev machine's project `example/output/` tree.
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      final docs = await getApplicationDocumentsDirectory();
      final root = p.join(docs.path, 'video_forge_kit_example', 'output');
      final paths = await _createDirs(root, isProjectLocal: false);
      _cached = paths;
      return paths;
    }

    final projectOut = await _tryProjectOutput();
    if (projectOut != null) {
      _cached = projectOut;
      return projectOut;
    }

    final docs = await getApplicationDocumentsDirectory();
    final root = p.join(docs.path, 'video_forge_kit_example', 'output');
    final paths = await _createDirs(root, isProjectLocal: false);
    _cached = paths;
    return paths;
  }

  static Future<OutputPaths?> _tryProjectOutput() async {
    final exampleDir = _findExampleDirectory();
    if (exampleDir == null) return null;

    final root = p.join(exampleDir, 'output');
    try {
      return await _createDirs(root, isProjectLocal: true);
    } catch (_) {
      return null;
    }
  }

  static String? _findExampleDirectory() {
    final candidates = <String>{
      Directory.current.path,
      p.dirname(Platform.script.toFilePath()),
      p.dirname(p.dirname(Platform.script.toFilePath())),
    };

    for (final start in candidates) {
      var dir = Directory(start);
      for (var i = 0; i < 6; i++) {
        final pubspec = File(p.join(dir.path, 'pubspec.yaml'));
        if (pubspec.existsSync()) {
          final name = _pubspecName(pubspec.path);
          if (name == 'video_forge_kit_example') {
            return dir.path;
          }
        }
        final parent = dir.parent;
        if (parent.path == dir.path) break;
        dir = parent;
      }
    }
    return null;
  }

  static String? _pubspecName(String pubspecPath) {
    try {
      final content = File(pubspecPath).readAsStringSync();
      final match = RegExp(r'^name:\s*(\S+)', multiLine: true).firstMatch(content);
      return match?.group(1);
    } catch (_) {
      return null;
    }
  }

  static Future<OutputPaths> _createDirs(
    String root, {
    required bool isProjectLocal,
  }) async {
    final compressVideoDir = p.join(root, 'compress_video');
    final thumbnailDir = p.join(root, 'thumbnail');
    final statusDir = p.join(root, 'status');

    for (final dir in [root, compressVideoDir, thumbnailDir, statusDir]) {
      await Directory(dir).create(recursive: true);
    }

    // Verify write access (macOS sandbox returns "Operation not permitted" otherwise).
    final probe = File(p.join(root, '.write_probe'));
    await probe.writeAsString('ok');
    await probe.delete();

    return OutputPaths._(
      root: root,
      compressVideoDir: compressVideoDir,
      thumbnailDir: thumbnailDir,
      statusDir: statusDir,
      isProjectLocal: isProjectLocal,
    );
  }

  /// WhatsApp-style status output: `status/<id>_status.mp4`.
  String statusOutputFor(String itemId) {
    return p.join(statusDir, '${itemId}_status.mp4');
  }

  /// Builds `compress_video/<stem>_compressed.mp4` under the output root.
  ///
  /// Works for local paths and network URLs ([safeStem] derived from the URL).
  String compressOutputFor(String input) {
    return p.join(compressVideoDir, '${_safeStem(input)}_compressed.mp4');
  }

  /// Builds `thumbnail/<stem>_thumb.jpg` under the output root.
  String thumbnailOutputFor(String input, {String ext = 'jpg'}) {
    return p.join(thumbnailDir, '${_safeStem(input)}_thumb.$ext');
  }

  /// Directory for batch thumbnails: `thumbnail/<stem>_frames/`.
  String batchThumbnailDirFor(String input) {
    return p.join(thumbnailDir, '${_safeStem(input)}_frames');
  }

  /// Writable work dir for on-device benchmark outputs.
  String benchmarkWorkDir() => p.join(root, 'benchmark');

  /// Scratch dir for Studio filmstrip / preview (OS temp/cache — never project `output/`).
  static Future<String> studioScratchDir() async {
    final Directory base = kIsWeb
        ? Directory((await resolve()).benchmarkWorkDir())
        : await getTemporaryDirectory();
    final dir = Directory(p.join(base.path, 'video_forge_kit_studio'));
    await dir.create(recursive: true);
    return dir.path;
  }

  /// Safe filename stem from a local path or URL (for benchmark/temp outputs).
  String safeStem(String input) => _safeStem(input);

  String _safeStem(String input) {
    final trimmed = input.trim();
    String name;
    if (_isNetworkUrl(trimmed)) {
      final withoutQuery = trimmed.split('?').first;
      name = p.basename(withoutQuery);
      if (name.isEmpty) name = 'remote_video';
    } else {
      name = p.basename(trimmed);
    }
    final stem = p.basenameWithoutExtension(name);
    return stem.replaceAll(RegExp(r'[^\w\-.]'), '_');
  }

  bool _isNetworkUrl(String value) {
    final lower = value.toLowerCase();
    return lower.startsWith('http://') ||
        lower.startsWith('https://') ||
        lower.startsWith('rtmp://') ||
        lower.startsWith('rtsp://') ||
        lower.startsWith('ftp://');
  }
}
