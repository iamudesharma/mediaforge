import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:squadron/squadron.dart';
import 'package:rust_image/src/rust/api/face.dart';
import 'package:rust_image/src/rust/api/layers.dart';
import 'package:rust_image/src/rust_image_editor.dart';

import '../models/beauty_params.dart';
import '../models/operation_profile.dart';
import 'filter_descriptor.dart';
import 'rust_worker_service.dart';
import 'rust_worker_pool_config.dart';
import 'coalesce_tracker.dart';

/// Long-lived isolate worker pool for Rust image work so the UI thread stays responsive.
abstract final class RustWorker {
  static RustWorkerServiceWorkerPool? _pool;
  static RustWorkerServiceWorker? _cameraWorker;
  static final _coalesce = CoalesceTracker();

  static Future<void> ensureStarted() async {
    if (_pool != null) return;
    final config = RustWorkerPoolConfig.auto();
    _pool = RustWorkerServiceWorkerPool(
      concurrencySettings: ConcurrencySettings(
        minWorkers: config.minWorkers,
        maxWorkers: config.maxWorkers,
        maxParallel: 1,
      ),
    );
    await _pool!.start();
  }

  /// Dedicated isolate for live camera frames — never contends with editor ops.
  static Future<void> ensureCameraWorkerStarted() async {
    if (_cameraWorker != null) return;
    _cameraWorker = RustWorkerServiceWorker();
    await _cameraWorker!.start();
  }

  static Future<Uint8List> filterBytes({
    required Uint8List bytes,
    required FilterDescriptor filter,
    required OutputFormat format,
    required int quality,
  }) async {
    await ensureStarted();
    return _pool!.filterBytes(
      bytes: TransferableTypedData.fromList([bytes]),
      filterKind: filter.kind,
      filterParams: filter.params,
      formatIndex: format.index,
      quality: quality,
    );
  }

  /// Replay [ops] on [base] (Sprint 3 edit graph). Optional JPEG for legacy preview.
  static Future<
      ({
        RgbaImageBuffer buffer,
        Uint8List? preview,
        OperationProfile? profile,
      })> replayEditPipeline({
    required RgbaImageBuffer base,
    required List<EditOp> ops,
    required ProcessingBackend backend,
    required int previewMaxEdge,
    required int previewQuality,
    bool encodePreviewJpeg = false,
  }) {
    return _coalesce.execute('replayEditPipeline', (_) async {
      await ensureStarted();
      final raw = await _pool!.replayEditPipeline(
        width: base.width,
        height: base.height,
        pixels: TransferableTypedData.fromList([base.pixels]),
        ops: ops,
        backendIndex: backend.index,
        previewMaxEdge: previewMaxEdge,
        previewQuality: previewQuality,
        encodePreviewJpeg: encodePreviewJpeg,
      );
      OperationProfile? profile;
      if (raw.containsKey('filter_ms')) {
        profile = OperationProfile(
          totalMs: (raw['total_ms'] as num?)?.toInt() ?? 0,
          filterMs: (raw['filter_ms'] as num).toInt(),
          previewEncodeMs: (raw['preview_ms'] as num?)?.toInt() ?? 0,
          executionPath: raw['path'] as String? ?? '',
        );
      }
      final previewPayload = raw['preview'];
      return (
        buffer: _bufferFromPayload(raw),
        preview: previewPayload == null
            ? null
            : _bytesFromPayload(previewPayload),
        profile: profile,
      );
    });
  }

  /// Full-resolution replay for export (no preview JPEG).
  static Future<RgbaImageBuffer> applyEditPipelineFull({
    required RgbaImageBuffer base,
    required List<EditOp> ops,
    required ProcessingBackend backend,
  }) async {
    await ensureStarted();
    final raw = await _pool!.applyEditPipelineFull(
      width: base.width,
      height: base.height,
      pixels: TransferableTypedData.fromList([base.pixels]),
      ops: ops,
      backendIndex: backend.index,
    );
    return _bufferFromPayload(raw);
  }

  static Future<
      ({
        RgbaImageBuffer buffer,
        Uint8List? preview,
        OperationProfile? profile,
      })> filterRgba({
    required RgbaImageBuffer buffer,
    required FilterDescriptor filter,
    required ProcessingBackend backend,
    required int previewMaxEdge,
    required int previewQuality,
    bool encodePreviewJpeg = true,
  }) {
    return _coalesce.execute('filterRgba', (_) async {
      await ensureStarted();
      final raw = await _pool!.filterRgba(
        width: buffer.width,
        height: buffer.height,
        pixels: TransferableTypedData.fromList([buffer.pixels]),
        filterKind: filter.kind,
        filterParams: filter.params,
        backendIndex: backend.index,
        previewMaxEdge: previewMaxEdge,
        previewQuality: previewQuality,
        encodePreviewJpeg: encodePreviewJpeg,
      );
      OperationProfile? profile;
      if (raw.containsKey('filter_ms')) {
        profile = OperationProfile(
          totalMs: (raw['total_ms'] as num?)?.toInt() ?? 0,
          filterMs: (raw['filter_ms'] as num).toInt(),
          previewEncodeMs: (raw['preview_ms'] as num).toInt(),
          executionPath: raw['path'] as String? ?? '',
        );
      }
      final previewPayload = raw['preview'];
      return (
        buffer: _bufferFromPayload(raw),
        preview: previewPayload == null
            ? null
            : _bytesFromPayload(previewPayload),
        profile: profile,
      );
    });
  }

  static Future<Uint8List> encodePreview({
    required RgbaImageBuffer buffer,
    required int previewMaxEdge,
    required int quality,
  }) async {
    await ensureStarted();
    return _pool!.encodePreview(
      width: buffer.width,
      height: buffer.height,
      pixels: TransferableTypedData.fromList([buffer.pixels]),
      previewMaxEdge: previewMaxEdge,
      quality: quality,
    );
  }

  /// Full-resolution encode for export (runs in worker isolate).
  static Future<Uint8List> encodeFullRgba({
    required RgbaImageBuffer buffer,
    required OutputFormat format,
    required int quality,
  }) async {
    await ensureStarted();
    return _pool!.encodeFullRgba(
      width: buffer.width,
      height: buffer.height,
      pixels: TransferableTypedData.fromList([buffer.pixels]),
      formatIndex: format.index,
      quality: quality,
    );
  }

  /// Regional skin smooth (Sprint 12) — runs in worker isolate.
  static Future<RgbaImageBuffer> applySkinSmooth({
    required RgbaImageBuffer buffer,
    required SegmentationMask mask,
    required double strength,
  }) {
    return _coalesce.execute('applySkinSmooth', (_) async {
      await ensureStarted();
      final raw = await _pool!.applySkinSmooth(
        width: buffer.width,
        height: buffer.height,
        pixels: TransferableTypedData.fromList([buffer.pixels]),
        maskW: mask.width,
        maskH: mask.height,
        maskPixels: TransferableTypedData.fromList([mask.pixels]),
        strength: strength,
      );
      return _bufferFromPayload(raw);
    });
  }

  /// Full regional beauty (Nexus B) — runs in worker isolate.
  static Future<RgbaImageBuffer> applyBeauty({
    required RgbaImageBuffer buffer,
    required FaceAnalysisResult analysis,
    required SegmentationMask skinMask,
    required BeautyParams params,
    SegmentationMask? excludeMask,
  }) {
    return _coalesce.execute('applyBeauty', (_) async {
      await ensureStarted();
      final raw = await _pool!.applyBeauty(
        width: buffer.width,
        height: buffer.height,
        pixels: TransferableTypedData.fromList([buffer.pixels]),
        landmarks: analysis.landmarks,
        faceContourCount: analysis.faceContourCount,
        regionCounts: regionCountsForAnalysis(analysis),
        maskW: skinMask.width,
        maskH: skinMask.height,
        maskPixels: TransferableTypedData.fromList([skinMask.pixels]),
        skinSmooth: params.skinSmooth,
        eyeBrighten: params.eyeBrighten,
        lipTintIndex: params.lipTint.index,
        lipTintStrength: params.lipTintStrength,
        lipPlump: params.lipPlump,
        blush: params.blush,
        underEye: params.underEye,
        teethWhiten: params.teethWhiten,
        exW: excludeMask?.width ?? 0,
        exH: excludeMask?.height ?? 0,
        exRaw: excludeMask != null
            ? TransferableTypedData.fromList([excludeMask.pixels])
            : null,
      );
      return _bufferFromPayload(raw);
    });
  }

  /// Dedicated beauty method for live camera loops.
  static Future<RgbaImageBuffer> applyBeautyCamera({
    required RgbaImageBuffer buffer,
    required FaceAnalysisResult analysis,
    required SegmentationMask skinMask,
    required BeautyParams params,
    SegmentationMask? excludeMask,
  }) async {
    await ensureCameraWorkerStarted();
    final raw = await _cameraWorker!.applyBeauty(
      width: buffer.width,
      height: buffer.height,
      pixels: TransferableTypedData.fromList([buffer.pixels]),
      landmarks: analysis.landmarks,
      faceContourCount: analysis.faceContourCount,
      regionCounts: regionCountsForAnalysis(analysis),
      maskW: skinMask.width,
      maskH: skinMask.height,
      maskPixels: TransferableTypedData.fromList([skinMask.pixels]),
      skinSmooth: params.skinSmooth,
      eyeBrighten: params.eyeBrighten,
      lipTintIndex: params.lipTint.index,
      lipTintStrength: params.lipTintStrength,
      lipPlump: params.lipPlump,
      blush: params.blush,
      underEye: params.underEye,
      teethWhiten: params.teethWhiten,
      exW: excludeMask?.width ?? 0,
      exH: excludeMask?.height ?? 0,
      exRaw: excludeMask != null
          ? TransferableTypedData.fromList([excludeMask.pixels])
          : null,
    );
    return _bufferFromPayload(raw);
  }

  /// Feathered skin mask from native face analysis (off UI thread).
  static Future<SegmentationMask> buildSkinMaskFromAnalysis({
    required FaceAnalysisResult analysis,
    required int width,
    required int height,
  }) async {
    await ensureStarted();
    final seg = analysis.segmentation;
    final raw = await _pool!.buildSkinMask(
      landmarks: analysis.landmarks,
      faceContourCount: analysis.faceContourCount,
      regionCounts: regionCountsForAnalysis(analysis),
      segW: seg?.width ?? 0,
      segH: seg?.height ?? 0,
      segRaw: seg != null ? TransferableTypedData.fromList([seg.pixels]) : null,
      width: width,
      height: height,
    );
    return SegmentationMask(
      width: raw['width']! as int,
      height: raw['height']! as int,
      pixels: _bytesFromPayload(raw['pixels']!),
    );
  }

  /// Dedicated skin mask method for live camera loops.
  static Future<SegmentationMask> buildSkinMaskFromAnalysisCamera({
    required FaceAnalysisResult analysis,
    required int width,
    required int height,
  }) async {
    await ensureCameraWorkerStarted();
    final seg = analysis.segmentation;
    final raw = await _cameraWorker!.buildSkinMask(
      landmarks: analysis.landmarks,
      faceContourCount: analysis.faceContourCount,
      regionCounts: regionCountsForAnalysis(analysis),
      segW: seg?.width ?? 0,
      segH: seg?.height ?? 0,
      segRaw: seg != null ? TransferableTypedData.fromList([seg.pixels]) : null,
      width: width,
      height: height,
    );
    return SegmentationMask(
      width: raw['width']! as int,
      height: raw['height']! as int,
      pixels: _bytesFromPayload(raw['pixels']!),
    );
  }

  static Future<String> blurHashEncode(Uint8List bytes) async {
    await ensureStarted();
    return _pool!.blurHashEncode(
      TransferableTypedData.fromList([bytes]),
    );
  }

  static Future<
      ({
        RgbaImageBuffer previewRgba,
        RgbaImageBuffer base,
        RgbaImageBuffer edit,
        ImageInfo info,
      })> decodeProgressive({
    required Uint8List bytes,
    int previewMaxEdge = 200,
    required int liveEditMaxEdge,
  }) async {
    await ensureStarted();
    final raw = await _pool!.decodeProgressive(
      bytes: TransferableTypedData.fromList([bytes]),
      previewMaxEdge: previewMaxEdge,
      liveEditMaxEdge: liveEditMaxEdge,
    );
    final previewRgba = RgbaImageBuffer(
      width: raw['preview_width']! as int,
      height: raw['preview_height']! as int,
      pixels: _bytesFromPayload(raw['preview_rgba']!),
    );
    return (
      previewRgba: previewRgba,
      base: RgbaImageBuffer(
        width: raw['width']! as int,
        height: raw['height']! as int,
        pixels: _bytesFromPayload(raw['pixels']!),
      ),
      edit: RgbaImageBuffer(
        width: raw['edit_width']! as int,
        height: raw['edit_height']! as int,
        pixels: _bytesFromPayload(raw['edit_pixels']!),
      ),
      info: ImageInfo(
        width: raw['info_width']! as int,
        height: raw['info_height']! as int,
        format: raw['info_format'] as String?,
      ),
    );
  }

  /// Decode full-res RGBA + edit-scale downscale in one worker round-trip.
  static Future<
      ({
        RgbaImageBuffer base,
        RgbaImageBuffer edit,
      })> decodeAndPrepareEditBase({
    required Uint8List bytes,
    required int liveEditMaxEdge,
  }) async {
    await ensureStarted();
    final raw = await _pool!.decodeAndPrepareEditBase(
      bytes: TransferableTypedData.fromList([bytes]),
      liveEditMaxEdge: liveEditMaxEdge,
    );
    return (
      base: RgbaImageBuffer(
        width: raw['base_width']! as int,
        height: raw['base_height']! as int,
        pixels: _bytesFromPayload(raw['base_pixels']!),
      ),
      edit: RgbaImageBuffer(
        width: raw['edit_width']! as int,
        height: raw['edit_height']! as int,
        pixels: _bytesFromPayload(raw['edit_pixels']!),
      ),
    );
  }

  /// Fit existing full-res RGBA to edit max edge off the UI thread.
  static Future<
      ({
        RgbaImageBuffer base,
        RgbaImageBuffer edit,
      })> prepareEditBaseFromRgba({
    required RgbaImageBuffer buffer,
    required int liveEditMaxEdge,
  }) async {
    await ensureStarted();
    final raw = await _pool!.prepareEditBaseFromRgba(
      width: buffer.width,
      height: buffer.height,
      pixels: TransferableTypedData.fromList([buffer.pixels]),
      liveEditMaxEdge: liveEditMaxEdge,
    );
    return (
      base: RgbaImageBuffer(
        width: raw['base_width']! as int,
        height: raw['base_height']! as int,
        pixels: _bytesFromPayload(raw['base_pixels']!),
      ),
      edit: RgbaImageBuffer(
        width: raw['edit_width']! as int,
        height: raw['edit_height']! as int,
        pixels: _bytesFromPayload(raw['edit_pixels']!),
      ),
    );
  }

  /// HEIC/HEIF → PNG in worker isolate.
  static Future<Uint8List> transcribeHeicToPng(Uint8List bytes) async {
    await ensureStarted();
    final td = await _pool!.transcribeHeicToPng(
      TransferableTypedData.fromList([bytes]),
    );
    return td.materialize().asUint8List();
  }

  /// Bake raster layers + paint strokes onto [buffer] in worker isolate.
  static Future<RgbaImageBuffer> bakeLayersRgba({
    required RgbaImageBuffer buffer,
    required List<RasterLayerInput> rasterLayers,
    required List<PaintStrokeInput> paintStrokes,
  }) async {
    await ensureStarted();
    final raw = await _pool!.bakeLayersRgba(
      width: buffer.width,
      height: buffer.height,
      pixels: TransferableTypedData.fromList([buffer.pixels]),
      rasterLayers: rasterLayers,
      paintStrokes: paintStrokes,
    );
    return _bufferFromPayload(raw);
  }

  static Future<Uint8List> batchResizeDemo({
    required Uint8List bytes,
    required ProcessingBackend backend,
  }) async {
    await ensureStarted();
    return _pool!.batchResizeDemo(
      bytes: TransferableTypedData.fromList([bytes]),
      backendIndex: backend.index,
    );
  }

  /// Straighten (optional), crop, fit edit max edge, and JPEG preview — all off the UI thread.
  static Future<
      ({
        RgbaImageBuffer base,
        RgbaImageBuffer edit,
        Uint8List preview,
      })> applyCropRgba({
    required RgbaImageBuffer buffer,
    required double straightenDegrees,
    required int x,
    required int y,
    required int width,
    required int height,
    required int liveEditMaxEdge,
    required int previewMaxEdge,
    required int previewQuality,
  }) async {
    await ensureStarted();
    final raw = await _pool!.applyCropRgba(
      width: buffer.width,
      height: buffer.height,
      pixels: TransferableTypedData.fromList([buffer.pixels]),
      straighten: straightenDegrees,
      cropX: x,
      cropY: y,
      cropW: width,
      cropH: height,
      liveEditMaxEdge: liveEditMaxEdge,
      previewMaxEdge: previewMaxEdge,
      previewQuality: previewQuality,
    );
    return (
      base: RgbaImageBuffer(
        width: raw['base_width']! as int,
        height: raw['base_height']! as int,
        pixels: _bytesFromPayload(raw['base_pixels']!),
      ),
      edit: RgbaImageBuffer(
        width: raw['edit_width']! as int,
        height: raw['edit_height']! as int,
        pixels: _bytesFromPayload(raw['edit_pixels']!),
      ),
      preview: _bytesFromPayload(raw['preview']!),
    );
  }

  static Future<({RgbaImageBuffer buffer, Uint8List preview})> resizeRgba({
    required RgbaImageBuffer buffer,
    required int width,
    required int height,
    required ProcessingBackend backend,
    required int previewMaxEdge,
    required int previewQuality,
    ResizeAlgorithm algorithm = ResizeAlgorithm.lanczos3,
  }) {
    return _coalesce.execute('resizeRgba', (_) async {
      await ensureStarted();
      final raw = await _pool!.resizeRgba(
        width: buffer.width,
        height: buffer.height,
        pixels: TransferableTypedData.fromList([buffer.pixels]),
        targetW: width,
        targetH: height,
        algorithmIndex: algorithm.index,
        backendIndex: backend.index,
        previewMaxEdge: previewMaxEdge,
        previewQuality: previewQuality,
      );
      return (
        buffer: _bufferFromPayload(raw),
        preview: _bytesFromPayload(raw['preview']!),
      );
    });
  }

  /// Heavy byte-path ops off the UI thread (compress, crop, resize, …).
  static Future<Uint8List> bytesTransform({
    required Uint8List bytes,
    required String op,
    required Map<String, Object?> params,
  }) async {
    await ensureStarted();
    return _pool!.bytesTransform(
      op: op,
      bytes: TransferableTypedData.fromList([bytes]),
      params: params,
    );
  }

  static Future<({RgbaImageBuffer buffer, Uint8List? preview})> drawLine({
    required RgbaImageBuffer buffer,
    required DrawLine line,
    required int previewMaxEdge,
    required int previewQuality,
    bool encodePreviewJpeg = true,
  }) {
    return _coalesce.execute('drawLine', (_) async {
      await ensureStarted();
      final raw = await _pool!.drawLine(
        width: buffer.width,
        height: buffer.height,
        pixels: TransferableTypedData.fromList([buffer.pixels]),
        x0: line.x0,
        y0: line.y0,
        x1: line.x1,
        y1: line.y1,
        colorR: line.colorR,
        colorG: line.colorG,
        colorB: line.colorB,
        colorA: line.colorA,
        previewMaxEdge: previewMaxEdge,
        previewQuality: previewQuality,
        encodePreviewJpeg: encodePreviewJpeg,
      );
      final previewPayload = raw['preview'];
      return (
        buffer: _bufferFromPayload(raw),
        preview: previewPayload == null
            ? null
            : _bytesFromPayload(previewPayload),
      );
    });
  }

  static Future<({RgbaImageBuffer buffer, Uint8List? preview})> drawCircle({
    required RgbaImageBuffer buffer,
    required DrawCircle circle,
    required int previewMaxEdge,
    required int previewQuality,
    bool encodePreviewJpeg = true,
  }) {
    return _coalesce.execute('drawCircle', (_) async {
      await ensureStarted();
      final raw = await _pool!.drawCircle(
        width: buffer.width,
        height: buffer.height,
        pixels: TransferableTypedData.fromList([buffer.pixels]),
        centerX: circle.centerX,
        centerY: circle.centerY,
        radius: circle.radius,
        colorR: circle.colorR,
        colorG: circle.colorG,
        colorB: circle.colorB,
        colorA: circle.colorA,
        previewMaxEdge: previewMaxEdge,
        previewQuality: previewQuality,
        encodePreviewJpeg: encodePreviewJpeg,
      );
      final previewPayload = raw['preview'];
      return (
        buffer: _bufferFromPayload(raw),
        preview: previewPayload == null
            ? null
            : _bytesFromPayload(previewPayload),
      );
    });
  }

  static Future<({RgbaImageBuffer buffer, Uint8List? preview})> drawText({
    required RgbaImageBuffer buffer,
    required TextOverlay overlay,
    required int previewMaxEdge,
    required int previewQuality,
    bool encodePreviewJpeg = true,
  }) {
    return _coalesce.execute('drawText', (_) async {
      await ensureStarted();
      final raw = await _pool!.drawText(
        width: buffer.width,
        height: buffer.height,
        pixels: TransferableTypedData.fromList([buffer.pixels]),
        text: overlay.text,
        x: overlay.x,
        y: overlay.y,
        fontSize: overlay.fontSize,
        colorR: overlay.colorR,
        colorG: overlay.colorG,
        colorB: overlay.colorB,
        colorA: overlay.colorA,
        previewMaxEdge: previewMaxEdge,
        previewQuality: previewQuality,
        encodePreviewJpeg: encodePreviewJpeg,
      );
      final previewPayload = raw['preview'];
      return (
        buffer: _bufferFromPayload(raw),
        preview: previewPayload == null
            ? null
            : _bytesFromPayload(previewPayload),
      );
    });
  }

  static Future<({RgbaImageBuffer buffer, Uint8List? preview})> overlayComposite({
    required RgbaImageBuffer base,
    required Uint8List overlayBytes,
    required int x,
    required int y,
    required BlendMode blendMode,
    required int overlayWidth,
    required int overlayHeight,
    required int previewMaxEdge,
    required int previewQuality,
    bool encodePreviewJpeg = true,
  }) {
    return _coalesce.execute('overlayRgba', (_) async {
      await ensureStarted();
      final raw = await _pool!.overlayRgba(
        width: base.width,
        height: base.height,
        pixels: TransferableTypedData.fromList([base.pixels]),
        overlayBytes: TransferableTypedData.fromList([overlayBytes]),
        x: x,
        y: y,
        blendModeIndex: blendMode.index,
        overlayWidth: overlayWidth,
        overlayHeight: overlayHeight,
        previewMaxEdge: previewMaxEdge,
        previewQuality: previewQuality,
        encodePreviewJpeg: encodePreviewJpeg,
      );
      final previewPayload = raw['preview'];
      return (
        buffer: _bufferFromPayload(raw),
        preview: previewPayload == null
            ? null
            : _bytesFromPayload(previewPayload),
      );
    });
  }

  static Future<Map<String, Object>> convertCameraImage({
    required int width,
    required int height,
    required List<TransferableTypedData> planesData,
    required List<int> planesBytesPerRow,
    required List<int?> planesBytesPerPixel,
    required int liveCameraMaxEdge,
    required bool isAndroid,
  }) async {
    await ensureCameraWorkerStarted();
    return _cameraWorker!.convertCameraImage(
      width: width,
      height: height,
      planesData: planesData,
      planesBytesPerRow: planesBytesPerRow,
      planesBytesPerPixel: planesBytesPerPixel,
      liveCameraMaxEdge: liveCameraMaxEdge,
      isAndroid: isAndroid,
    );
  }

  static Future<RgbaImageBuffer> decodeRgba(Uint8List bytes) async {
    await ensureStarted();
    final raw = await _pool!.decodeRgba(TransferableTypedData.fromList([bytes]));
    return _bufferFromPayload(raw);
  }

  static RgbaImageBuffer _bufferFromPayload(Map<String, Object> raw) {
    return RgbaImageBuffer(
      width: raw['width']! as int,
      height: raw['height']! as int,
      pixels: _bytesFromPayload(raw['pixels']!),
    );
  }

  static Uint8List _bytesFromPayload(Object payload) {
    return (payload as TransferableTypedData).materialize().asUint8List();
  }

  static Future<void> shutdown() async {
    if (_pool != null) {
      _pool!.stop();
      _pool = null;
    }
    if (_cameraWorker != null) {
      _cameraWorker!.stop();
      _cameraWorker = null;
    }
  }
}
