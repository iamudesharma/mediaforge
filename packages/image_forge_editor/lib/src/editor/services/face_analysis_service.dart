import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_forge/image_forge.dart';
import 'package:image_forge_editor/src/image_forge_editor.dart';

import '../models/beauty_params.dart';
import 'mediapipe_model_service.dart';

/// Native MediaPipe / Vision face analysis (Sprint 12).
abstract final class FaceAnalysisService {
  static const _channel = MethodChannel('rust_image/face');

  /// Matches Rust [visionMinLandmarkCount] / Vision fallback threshold.
  static const minLandmarksForValid = 68;

  static bool get isSupported =>
      !kIsWeb &&
      (Platform.isMacOS || Platform.isIOS || Platform.isAndroid);

  /// Dart-side validity check — avoids FFI round-trip with full segmentation mask.
  static bool isAnalysisValid(FaceAnalysisResult? analysis) {
    if (analysis == null) return false;
    return analysis.confidence > 0.5 &&
        analysis.landmarks.length >= minLandmarksForValid &&
        analysis.segmentation != null;
  }

  static Future<bool> isAvailable() async {
    if (!isSupported) return false;
    try {
      final v = await _channel.invokeMethod<bool>('isAvailable');
      return v == true;
    } catch (_) {
      return false;
    }
  }

  /// Whether optional MediaPipe models are on disk (468-point mesh when native SDK linked).
  static Future<bool> isMediaPipeReady() => MediaPipeModelService.isMediaPipeReady();

  /// Analyze image bytes at [targetWidth]×[targetHeight] (edit-scale).
  /// Pass [pixelFormat] `rgba` for raw RGBA frames (live camera); default JPEG/PNG.
  static Future<FaceAnalysisResult?> analyzeImage({
    required Uint8List bytes,
    required int targetWidth,
    required int targetHeight,
    int maxEdge = 1280,
    String pixelFormat = 'jpeg',
    String? modelDir,
  }) async {
    if (!isSupported) return null;
    final dir = modelDir ?? await MediaPipeModelService.modelDirectory();
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
        'analyzeImage',
        {
          'bytes': bytes,
          'width': targetWidth,
          'height': targetHeight,
          'maxEdge': maxEdge,
          'pixelFormat': pixelFormat,
          'modelDir': dir,
        },
      );
      if (raw == null) return null;
      return _parseResult(raw);
    } catch (e, st) {
      debugPrint('FaceAnalysisService: $e\n$st');
      return null;
    }
  }

  /// Build feathered skin mask via Rust from native analysis.
  static SegmentationMask buildSkinMask({
    required FaceAnalysisResult analysis,
    required int width,
    required int height,
  }) {
    return buildSkinMaskFromLandmarks(
      landmarks: analysis.landmarks,
      faceContourCount: analysis.faceContourCount,
      regionCounts: regionCountsForAnalysis(analysis),
      segmentation: analysis.segmentation,
      width: width,
      height: height,
    );
  }

  static FaceAnalysisResult? _parseResult(Map<Object?, Object?> raw) {
    final conf = (raw['confidence'] as num?)?.toDouble() ?? 0.0;
    final lmRaw = raw['landmarks'] as List<Object?>?;
    if (lmRaw == null) return null;
    final landmarks = <Landmark2D>[];
    for (final item in lmRaw) {
      final m = item as Map<Object?, Object?>?;
      if (m == null) continue;
      landmarks.add(Landmark2D(
        x: (m['x'] as num?)?.toDouble() ?? 0,
        y: (m['y'] as num?)?.toDouble() ?? 0,
        z: (m['z'] as num?)?.toDouble() ?? 0,
      ));
    }
    SegmentationMask? seg;
    final maskRaw = raw['mask'] as Map<Object?, Object?>?;
    if (maskRaw != null) {
      final w = (maskRaw['width'] as num?)?.toInt() ?? 0;
      final h = (maskRaw['height'] as num?)?.toInt() ?? 0;
      final bytes = maskRaw['bytes'];
      Uint8List? pixels;
      if (bytes is Uint8List) {
        pixels = bytes;
      } else if (bytes != null) {
        // FlutterStandardTypedData on some platforms
        try {
          pixels = (bytes as dynamic).data as Uint8List;
        } catch (_) {}
      }
      if (pixels != null && w > 0 && h > 0) {
        seg = SegmentationMask(width: w, height: h, pixels: pixels);
      }
    }
    return FaceAnalysisResult(
      landmarks: landmarks,
      confidence: conf,
      segmentation: seg,
      faceContourCount: (raw['faceContourCount'] as num?)?.toInt() ?? 0,
      regionCounts: _parseRegionCounts(raw['regionCounts']),
    );
  }

  static Uint32List _parseRegionCounts(Object? raw) {
    if (raw == null) return Uint32List(0);
    if (raw is Uint32List) return raw;
    if (raw is List) {
      return Uint32List.fromList(raw.map((e) => (e as num).toInt()).toList());
    }
    return Uint32List(0);
  }
}
