import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Optional first-run download for MediaPipe 468-point face mesh (Nexus A/D).
abstract final class MediaPipeModelService {
  static const faceFileName = 'face_landmarker.task';
  static const segmenterFileName = 'selfie_segmenter.tflite';
  static const dismissMarkerName = '.mediapipe_prompt_dismissed';

  static const faceUrl =
      'https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/latest/face_landmarker.task';
  /// Image Segmenter ships as TFLite only (no `.task` bundle on GCS).
  static const segmenterUrl =
      'https://storage.googleapis.com/mediapipe-models/image_segmenter/selfie_segmenter/float16/latest/selfie_segmenter.tflite';

  /// Approximate combined download size for UI copy.
  static const estimatedSizeMb = 4;

  static bool get isPlatformSupported =>
      !kIsWeb &&
      (Platform.isIOS || Platform.isAndroid || Platform.isMacOS);

  static Future<String> modelDirectory() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/mediapipe');
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir.path;
  }

  static Future<bool> isMediaPipeReady() async {
    if (!isPlatformSupported) return false;
    final dir = await modelDirectory();
    return File('$dir/$faceFileName').existsSync() &&
        File('$dir/$segmenterFileName').existsSync();
  }

  static Future<bool> isPromptDismissed() async {
    final dir = await modelDirectory();
    return File('$dir/$dismissMarkerName').existsSync();
  }

  static Future<void> dismissPrompt() async {
    final dir = await modelDirectory();
    await File('$dir/$dismissMarkerName').writeAsString('1');
  }

  static Future<void> downloadModels({
    void Function(double progress)? onProgress,
  }) async {
    if (!isPlatformSupported) {
      throw UnsupportedError('MediaPipe models not supported on this platform');
    }
    final dir = await modelDirectory();
    final facePath = '$dir/$faceFileName';
    final segPath = '$dir/$segmenterFileName';

    // Remove stale segmenter artifacts from older broken `.task` URL.
    final legacySeg = File('$dir/selfie_segmenter.task');
    if (legacySeg.existsSync()) {
      await legacySeg.delete();
    }

    onProgress?.call(0.02);
    try {
      await _downloadUrl(
        faceUrl,
        facePath,
        (p) => onProgress?.call(0.02 + p * 0.48),
      );
      onProgress?.call(0.52);
      await _downloadUrl(
        segmenterUrl,
        segPath,
        (p) => onProgress?.call(0.52 + p * 0.48),
      );
      onProgress?.call(1.0);
    } catch (e) {
      if (File(facePath).existsSync()) await File(facePath).delete();
      if (File(segPath).existsSync()) await File(segPath).delete();
      rethrow;
    }
  }

  static Future<void> _downloadUrl(
    String url,
    String destPath,
    void Function(double progress) onProgress,
  ) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode != 200) {
        throw HttpException('Download failed (${response.statusCode}): $url');
      }
      final total = response.contentLength;
      final file = File(destPath);
      final sink = file.openWrite();
      var received = 0;
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          onProgress(received / total);
        }
      }
      await sink.close();
    } finally {
      client.close();
    }
  }
}
