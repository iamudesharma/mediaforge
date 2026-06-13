import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'video_input.dart';

/// Writable export/cache directories for the video editor.
class EditorOutputPaths {
  EditorOutputPaths._({
    required this.root,
    required this.compressVideoDir,
    required this.thumbnailDir,
  });

  final String root;
  final String compressVideoDir;
  final String thumbnailDir;

  static EditorOutputPaths? _cached;
  static String _cacheSegment = 'video_forge_editor';

  /// Override the documents subdirectory (default `video_forge_editor`).
  static void configure({String cacheSegment = 'video_forge_editor'}) {
    _cacheSegment = cacheSegment;
    _cached = null;
  }

  static Future<EditorOutputPaths> resolve() async {
    if (_cached != null) return _cached!;
    final docs = await getApplicationDocumentsDirectory();
    final root = p.join(docs.path, _cacheSegment, 'output');
    final compressVideoDir = p.join(root, 'compress_video');
    final thumbnailDir = p.join(root, 'thumbnail');
    await Directory(compressVideoDir).create(recursive: true);
    await Directory(thumbnailDir).create(recursive: true);
    _cached = EditorOutputPaths._(
      root: root,
      compressVideoDir: compressVideoDir,
      thumbnailDir: thumbnailDir,
    );
    return _cached!;
  }

  String safeStem(String inputPath) => VideoInput.safeStem(inputPath);
}
