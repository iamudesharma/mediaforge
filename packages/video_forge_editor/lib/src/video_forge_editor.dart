import 'package:flutter/foundation.dart';
import 'package:media_forge/media_forge.dart' as media_forge;
import 'package:video_forge_kit/video_forge_kit.dart';

/// High-performance video editor powered by [VideoProcessor] and [media_forge].
///
/// Call [VideoForgeEditor.ensureInitialized] once before using any editor API.
class VideoForgeEditor {
  VideoForgeEditor._();

  static Future<void>? _initFuture;

  /// Safe to call multiple times (e.g. from `main` and [VideoForgeEditorWidget]).
  static Future<void> ensureInitialized() async {
    if (_initFuture != null) {
      try {
        await _initFuture;
        return;
      } catch (_) {
        _initFuture = null;
      }
    }
    _initFuture = _initOnce();
    try {
      await _initFuture;
    } catch (_) {
      _initFuture = null;
      rethrow;
    }
  }

  static Future<void> _initOnce() async {
    debugPrint('[VideoEditor] initializing VideoProcessor + media_forge');
    await VideoProcessor.initialize();
    await media_forge.RustLib.init();
    debugPrint('[VideoEditor] native engines ready');
  }
}
