import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_video_processor/flutter_video_processor.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Builds a single preview MP4 with video + mixed audio tracks (same path as export).
///
/// TikTok / Instagram-style editors use one playback clock and one mixed soundtrack
/// for preview, not a second platform audio player fighting the video decoder.
class PreviewPlaybackMux {
  PreviewPlaybackMux._();

  static String? _cachedPath;
  static String? _cacheKey;

  /// Returns a muxed preview file path, or [videoPath] when [audioTracks] is empty.
  static Future<String> ensure({
    required String videoPath,
    required int startMs,
    required int endMs,
    required List<AudioTrackInput> audioTracks,
    required bool muteOriginalAudio,
    void Function(String status)? onStatus,
  }) async {
    if (audioTracks.isEmpty) {
      return videoPath;
    }

    final key = _cacheKeyFor(
      videoPath: videoPath,
      startMs: startMs,
      endMs: endMs,
      audioTracks: audioTracks,
      muteOriginalAudio: muteOriginalAudio,
    );
    if (_cacheKey == key &&
        _cachedPath != null &&
        File(_cachedPath!).existsSync()) {
      return _cachedPath!;
    }

    onStatus?.call('Mixing audio for preview…');
    final dir = await getTemporaryDirectory();
    final outDir = Directory(p.join(dir.path, 'preview_mux'));
    await outDir.create(recursive: true);
    // Cache key is base-36 hash (often < 16 chars); never truncate past length.
    final outPath = p.join(outDir.path, 'preview_$key.mp4');

    if (File(outPath).existsSync()) {
      try {
        File(outPath).deleteSync();
      } catch (_) {}
    }

    debugPrint('[PreviewMux] building $outPath (${audioTracks.length} track(s))');
    final job = await VideoProcessor.compressJob(
      input: videoPath,
      output: outPath,
      quality: VideoQuality.medium,
      preferHardwareEncoder: true,
      startMs: startMs,
      endMs: endMs > startMs ? endMs : null,
      audioTracks: audioTracks,
      muteOriginalAudio: muteOriginalAudio,
      includeAudio: true,
    );
    final result = await job.result;
    final path = result.outputPath;
    final info = await VideoProcessor.getMediaInfo(path);
    if (info.durationMs <= BigInt.zero) {
      throw StateError('Preview mix produced no playable duration');
    }
    _cacheKey = key;
    _cachedPath = path;
    debugPrint('[PreviewMux] ready ${info.durationMs}ms → $path');
    onStatus?.call('Preview mix ready');
    return path;
  }

  static void invalidate() {
    _cacheKey = null;
    _cachedPath = null;
  }

  static String _cacheKeyFor({
    required String videoPath,
    required int startMs,
    required int endMs,
    required List<AudioTrackInput> audioTracks,
    required bool muteOriginalAudio,
  }) {
    return Object.hash(
      videoPath,
      startMs,
      endMs,
      muteOriginalAudio,
      Object.hashAll(
        audioTracks.map(
          (t) => Object.hash(
            t.sourcePath,
            t.sourceStartMs,
            t.durationMs,
            t.timelineStartMs,
            t.volume,
            t.muted,
          ),
        ),
      ),
    ).toUnsigned(36).toRadixString(36);
  }
}
