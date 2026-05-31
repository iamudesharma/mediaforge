import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:squadron/squadron.dart';
import 'package:image_forge/image_forge.dart';
import 'package:image_forge/image_forge.dart';
import 'package:image_forge_editor/src/image_forge_editor.dart';

import '../models/beauty_params.dart';
import 'filter_descriptor.dart';

import 'rust_worker_service.activator.g.dart';
part 'rust_worker_service.worker.g.dart';

@SquadronService()
base class RustWorkerService {
  Future<void>? _initFuture;

  Future<void> _ensureInitialized() {
    return _initFuture ??= RustImageEditor.ensureInitialized();
  }

  @SquadronMethod()
  Future<Uint8List> filterBytes({
    required TransferableTypedData bytes,
    required String filterKind,
    required Map<dynamic, dynamic> filterParams,
    required int formatIndex,
    required int quality,
  }) async {
    await _ensureInitialized();
    final filter = FilterDescriptor(filterKind, Map<String, dynamic>.from(filterParams));
    final format = OutputFormat.values[formatIndex];
    return RustImageEditor.filter(
      bytes: bytes.materialize().asUint8List(),
      filter: filter.toImageFilter(),
      format: format,
      quality: quality,
    );
  }

  @SquadronMethod()
  Future<Map<String, Object>> filterRgba({
    required int width,
    required int height,
    required TransferableTypedData pixels,
    required String filterKind,
    required Map<dynamic, dynamic> filterParams,
    required int backendIndex,
    required int previewMaxEdge,
    required int previewQuality,
    required bool encodePreviewJpeg,
  }) async {
    await _ensureInitialized();
    final filter = FilterDescriptor(filterKind, Map<String, dynamic>.from(filterParams));
    final backend = ProcessingBackend.values[backendIndex];
    
    final total = Stopwatch()..start();
    var buffer = RgbaImageBuffer(width: width, height: height, pixels: pixels.materialize().asUint8List());
    final filterSw = Stopwatch()..start();
    buffer = RustImageEditor.filterRgba(
      buffer,
      filter.toImageFilter(),
      backend: backend,
    );
    final filterMs = filterSw.elapsedMilliseconds;
    var previewMs = 0;
    TransferableTypedData? previewTd;
    if (encodePreviewJpeg) {
      final previewSw = Stopwatch()..start();
      final preview = _encodePreviewBuffer(buffer, previewMaxEdge, previewQuality);
      previewMs = previewSw.elapsedMilliseconds;
      previewTd = TransferableTypedData.fromList([preview]);
    }
    final path = RustImageEditor.filterExecutionPath(
      filter.toImageFilter(),
      backend,
    );
    return {
      'width': buffer.width,
      'height': buffer.height,
      'pixels': TransferableTypedData.fromList([buffer.pixels]),
      if (previewTd != null) 'preview': previewTd,
      'filter_ms': filterMs,
      'preview_ms': previewMs,
      'path': path,
      'total_ms': total.elapsedMilliseconds,
    };
  }

  @SquadronMethod()
  Future<Map<String, Object>> replayEditPipeline({
    required int width,
    required int height,
    required TransferableTypedData pixels,
    required List<EditOp> ops,
    required int backendIndex,
    required int previewMaxEdge,
    required int previewQuality,
    required bool encodePreviewJpeg,
  }) async {
    await _ensureInitialized();
    final backend = ProcessingBackend.values[backendIndex];

    final total = Stopwatch()..start();
    var buffer = RgbaImageBuffer(width: width, height: height, pixels: pixels.materialize().asUint8List());
    final filterSw = Stopwatch()..start();
    if (ops.isNotEmpty) {
      buffer = RustImageEditor.applyEditGraph(
        buffer,
        ops,
        backend: backend,
      );
    }
    final filterMs = filterSw.elapsedMilliseconds;
    var previewMs = 0;
    TransferableTypedData? previewTd;
    if (encodePreviewJpeg) {
      final previewSw = Stopwatch()..start();
      final preview = _encodePreviewBuffer(buffer, previewMaxEdge, previewQuality);
      previewMs = previewSw.elapsedMilliseconds;
      previewTd = TransferableTypedData.fromList([preview]);
    }
    return {
      'width': buffer.width,
      'height': buffer.height,
      'pixels': TransferableTypedData.fromList([buffer.pixels]),
      if (previewTd != null) 'preview': previewTd,
      'filter_ms': filterMs,
      'preview_ms': previewMs,
      'path': ops.isEmpty ? '' : 'pipeline',
      'total_ms': total.elapsedMilliseconds,
    };
  }

  @SquadronMethod()
  Future<Map<String, Object>> applyEditPipelineFull({
    required int width,
    required int height,
    required TransferableTypedData pixels,
    required List<EditOp> ops,
    required int backendIndex,
  }) async {
    await _ensureInitialized();
    final backend = ProcessingBackend.values[backendIndex];
    var buffer = RgbaImageBuffer(width: width, height: height, pixels: pixels.materialize().asUint8List());
    if (ops.isNotEmpty) {
      buffer = RustImageEditor.applyEditGraph(
        buffer,
        ops,
        backend: backend,
      );
    }
    return {
      'width': buffer.width,
      'height': buffer.height,
      'pixels': TransferableTypedData.fromList([buffer.pixels]),
    };
  }

  @SquadronMethod()
  Future<Uint8List> encodePreview({
    required int width,
    required int height,
    required TransferableTypedData pixels,
    required int previewMaxEdge,
    required int quality,
  }) async {
    await _ensureInitialized();
    final buffer = RgbaImageBuffer(width: width, height: height, pixels: pixels.materialize().asUint8List());
    return _encodePreviewBuffer(buffer, previewMaxEdge, quality);
  }

  @SquadronMethod()
  Future<Uint8List> encodeFullRgba({
    required int width,
    required int height,
    required TransferableTypedData pixels,
    required int formatIndex,
    required int quality,
  }) async {
    await _ensureInitialized();
    final format = OutputFormat.values[formatIndex];
    final buffer = RgbaImageBuffer(width: width, height: height, pixels: pixels.materialize().asUint8List());
    return RustImageEditor.encodeRgba(
      buffer,
      format: format,
      quality: quality,
    );
  }

  @SquadronMethod()
  Future<Map<String, Object>> applySkinSmooth({
    required int width,
    required int height,
    required TransferableTypedData pixels,
    required int maskW,
    required int maskH,
    required TransferableTypedData maskPixels,
    required double strength,
  }) async {
    await _ensureInitialized();
    final buffer = RgbaImageBuffer(width: width, height: height, pixels: pixels.materialize().asUint8List());
    final mask = SegmentationMask(
      width: maskW,
      height: maskH,
      pixels: maskPixels.materialize().asUint8List(),
    );
    final out = applySkinSmoothCpu(
      buffer: buffer,
      mask: mask,
      strength: strength,
    );
    return {
      'width': out.width,
      'height': out.height,
      'pixels': TransferableTypedData.fromList([out.pixels]),
    };
  }

  @SquadronMethod()
  Future<Map<String, Object>> applyBeauty({
    required int width,
    required int height,
    required TransferableTypedData pixels,
    required List<Landmark2D> landmarks,
    required int faceContourCount,
    required List<int> regionCounts,
    required int maskW,
    required int maskH,
    required TransferableTypedData maskPixels,
    required double skinSmooth,
    required double eyeBrighten,
    required int lipTintIndex,
    required double lipTintStrength,
    required double lipPlump,
    required double blush,
    required double underEye,
    required double teethWhiten,
    required int exW,
    required int exH,
    required TransferableTypedData? exRaw,
  }) async {
    await _ensureInitialized();
    final params = BeautyParams(
      skinSmooth: skinSmooth,
      eyeBrighten: eyeBrighten,
      lipTint: LipTintPreset.values[lipTintIndex],
      lipTintStrength: lipTintStrength,
      lipPlump: lipPlump,
      blush: blush,
      underEye: underEye,
      teethWhiten: teethWhiten,
      skinPreserveDetail: 0,
      eyeEnlarge: 0,
      jawSlim: 0,
      noseSlim: 0,
      faceSlim: 0,
      chinVshape: 0,
    );
    SegmentationMask? excludeMask;
    if (exRaw != null && exW > 0 && exH > 0) {
      final exPixels = exRaw.materialize().asUint8List();
      excludeMask = SegmentationMask(
        width: exW,
        height: exH,
        pixels: exPixels,
      );
    }
    final buffer = RgbaImageBuffer(width: width, height: height, pixels: pixels.materialize().asUint8List());
    final skinMask = SegmentationMask(
      width: maskW,
      height: maskH,
      pixels: maskPixels.materialize().asUint8List(),
    );
    final out = applyBeautyCpu(
      buffer: buffer,
      landmarks: landmarks,
      faceContourCount: faceContourCount,
      regionCounts: regionCounts,
      skinMask: skinMask,
      params: params,
      excludeMask: excludeMask,
    );
    return {
      'width': out.width,
      'height': out.height,
      'pixels': TransferableTypedData.fromList([out.pixels]),
    };
  }

  @SquadronMethod()
  Future<Map<String, Object>> buildSkinMask({
    required List<Landmark2D> landmarks,
    required int faceContourCount,
    required List<int> regionCounts,
    required int segW,
    required int segH,
    required TransferableTypedData? segRaw,
    required int width,
    required int height,
  }) async {
    await _ensureInitialized();
    SegmentationMask? segmentation;
    if (segRaw != null && segW > 0 && segH > 0) {
      final segPixels = segRaw.materialize().asUint8List();
      segmentation = SegmentationMask(
        width: segW,
        height: segH,
        pixels: segPixels,
      );
    }
    final mask = buildSkinMaskFromLandmarks(
      landmarks: landmarks,
      faceContourCount: faceContourCount,
      regionCounts: regionCounts,
      segmentation: segmentation,
      width: width,
      height: height,
    );
    return {
      'width': mask.width,
      'height': mask.height,
      'pixels': TransferableTypedData.fromList([mask.pixels]),
    };
  }

  @SquadronMethod()
  Future<String> blurHashEncode(TransferableTypedData bytes) async {
    await _ensureInitialized();
    return RustImageEditor.blurHashEncode(bytes.materialize().asUint8List());
  }

  @SquadronMethod()
  Future<Map<String, Object>> decodeProgressive({
    required TransferableTypedData bytes,
    required int previewMaxEdge,
    required int liveEditMaxEdge,
  }) async {
    await _ensureInitialized();
    final prog = RustImageEditor.decodeProgressive(
      bytes.materialize().asUint8List(),
      previewMaxEdge: previewMaxEdge,
      fixExif: true,
    );
    final edit = RustImageEditor.fitMaxEdgeRgba(
      prog.buffer,
      maxEdge: liveEditMaxEdge,
      previewQuality: PreviewQuality.fast,
    );
    return {
      'width': prog.buffer.width,
      'height': prog.buffer.height,
      'pixels': TransferableTypedData.fromList([prog.buffer.pixels]),
      'edit_width': edit.width,
      'edit_height': edit.height,
      'edit_pixels': TransferableTypedData.fromList([edit.pixels]),
      'preview_rgba': TransferableTypedData.fromList([prog.previewRgba.pixels]),
      'preview_width': prog.previewRgba.width,
      'preview_height': prog.previewRgba.height,
      'info_width': prog.info.width,
      'info_height': prog.info.height,
      'info_format': prog.info.format ?? '',
    };
  }

  /// Decode once → full-res base + edit-scale buffer (Sprint 13 import path).
  @SquadronMethod()
  Future<Map<String, Object>> decodeAndPrepareEditBase({
    required TransferableTypedData bytes,
    required int liveEditMaxEdge,
  }) async {
    await _ensureInitialized();
    final decoded = RustImageEditor.decodeToRgba(
      bytes.materialize().asUint8List(),
      fixExif: true,
    );
    final edit = RustImageEditor.fitMaxEdgeRgba(
      decoded,
      maxEdge: liveEditMaxEdge,
      previewQuality: PreviewQuality.fast,
    );
    return {
      'base_width': decoded.width,
      'base_height': decoded.height,
      'base_pixels': TransferableTypedData.fromList([decoded.pixels]),
      'edit_width': edit.width,
      'edit_height': edit.height,
      'edit_pixels': TransferableTypedData.fromList([edit.pixels]),
    };
  }

  /// Downscale an existing RGBA buffer to edit max edge off the UI thread.
  @SquadronMethod()
  Future<Map<String, Object>> prepareEditBaseFromRgba({
    required int width,
    required int height,
    required TransferableTypedData pixels,
    required int liveEditMaxEdge,
  }) async {
    await _ensureInitialized();
    final base = RgbaImageBuffer(
      width: width,
      height: height,
      pixels: pixels.materialize().asUint8List(),
    );
    final edit = RustImageEditor.fitMaxEdgeRgba(
      base,
      maxEdge: liveEditMaxEdge,
      previewQuality: PreviewQuality.fast,
    );
    return {
      'base_width': base.width,
      'base_height': base.height,
      'base_pixels': TransferableTypedData.fromList([base.pixels]),
      'edit_width': edit.width,
      'edit_height': edit.height,
      'edit_pixels': TransferableTypedData.fromList([edit.pixels]),
    };
  }

  /// HEIC/HEIF → PNG off the UI thread (Sprint 13).
  @SquadronMethod()
  Future<TransferableTypedData> transcribeHeicToPng(
    TransferableTypedData bytes,
  ) async {
    final input = bytes.materialize().asUint8List();
    ui.Image? image;
    try {
      final codec = await ui.instantiateImageCodec(input);
      final frame = await codec.getNextFrame();
      image = frame.image;
      final bd = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bd == null) {
        throw StateError('Could not encode HEIC preview as PNG');
      }
      final png = bd.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes);
      return TransferableTypedData.fromList([png]);
    } catch (e) {
      throw FormatException(
        'HEIC/HEIF could not be decoded on this device. '
        'Export the photo as JPEG from Photos and try again. ($e)',
      );
    } finally {
      image?.dispose();
    }
  }

  /// Composite raster layers + paint strokes onto [buffer] (export path).
  @SquadronMethod()
  Future<Map<String, Object>> bakeLayersRgba({
    required int width,
    required int height,
    required TransferableTypedData pixels,
    required List<RasterLayerInput> rasterLayers,
    required List<PaintStrokeInput> paintStrokes,
  }) async {
    await _ensureInitialized();
    var buffer = RgbaImageBuffer(
      width: width,
      height: height,
      pixels: pixels.materialize().asUint8List(),
    );
    buffer = RustImageEditor.bakeLayers(
      buffer: buffer,
      rasterLayers: rasterLayers,
      paintStrokes: paintStrokes,
    );
    return {
      'width': buffer.width,
      'height': buffer.height,
      'pixels': TransferableTypedData.fromList([buffer.pixels]),
    };
  }

  @SquadronMethod()
  Future<Uint8List> batchResizeDemo({
    required TransferableTypedData bytes,
    required int backendIndex,
  }) async {
    await _ensureInitialized();
    final backend = ProcessingBackend.values[backendIndex];
    final out = RustImageEditor.batchResize(
      items: [
        BatchResizeItem(bytes: bytes.materialize().asUint8List(), width: 256, height: 256),
        BatchResizeItem(bytes: bytes.materialize().asUint8List(), width: 512, height: 512),
      ],
      backend: backend,
    );
    return out.last;
  }

  @SquadronMethod()
  Future<Map<String, Object>> applyCropRgba({
    required int width,
    required int height,
    required TransferableTypedData pixels,
    required double straighten,
    required int cropX,
    required int cropY,
    required int cropW,
    required int cropH,
    required int liveEditMaxEdge,
    required int previewMaxEdge,
    required int previewQuality,
  }) async {
    await _ensureInitialized();
    var buffer = RgbaImageBuffer(width: width, height: height, pixels: pixels.materialize().asUint8List());
    if (straighten.abs() >= 0.05) {
      buffer = rotateRgbaArbitrary(buffer: buffer, degrees: straighten);
    }
    buffer = RustImageEditor.cropRgba(
      buffer,
      x: cropX,
      y: cropY,
      width: cropW,
      height: cropH,
    );
    final base = buffer;
    final edit = RustImageEditor.fitMaxEdgeRgba(
      buffer,
      maxEdge: liveEditMaxEdge,
      previewQuality: PreviewQuality.fast,
    );
    final preview = _encodePreviewBuffer(edit, previewMaxEdge, previewQuality);
    return {
      'base_width': base.width,
      'base_height': base.height,
      'base_pixels': TransferableTypedData.fromList([base.pixels]),
      'edit_width': edit.width,
      'edit_height': edit.height,
      'edit_pixels': TransferableTypedData.fromList([edit.pixels]),
      'preview': TransferableTypedData.fromList([preview]),
    };
  }

  @SquadronMethod()
  Future<Map<String, Object>> resizeRgba({
    required int width,
    required int height,
    required TransferableTypedData pixels,
    required int targetW,
    required int targetH,
    required int algorithmIndex,
    required int backendIndex,
    required int previewMaxEdge,
    required int previewQuality,
  }) async {
    await _ensureInitialized();
    final algorithm = ResizeAlgorithm.values[algorithmIndex];
    final backend = ProcessingBackend.values[backendIndex];
    var buffer = RgbaImageBuffer(width: width, height: height, pixels: pixels.materialize().asUint8List());
    buffer = RustImageEditor.resizeRgba(
      buffer,
      width: targetW,
      height: targetH,
      algorithm: algorithm,
      backend: backend,
    );
    final preview = _encodePreviewBuffer(buffer, previewMaxEdge, previewQuality);
    return {
      'width': buffer.width,
      'height': buffer.height,
      'pixels': TransferableTypedData.fromList([buffer.pixels]),
      'preview': TransferableTypedData.fromList([preview]),
    };
  }

  @SquadronMethod()
  Future<Uint8List> bytesTransform({
    required String op,
    required TransferableTypedData bytes,
    required Map<dynamic, dynamic> params,
  }) async {
    await _ensureInitialized();
    return _bytesTransform(bytes.materialize().asUint8List(), op, Map<String, Object?>.from(params));
  }

  @SquadronMethod()
  Future<Map<String, Object>> drawLine({
    required int width,
    required int height,
    required TransferableTypedData pixels,
    required int x0,
    required int y0,
    required int x1,
    required int y1,
    required int colorR,
    required int colorG,
    required int colorB,
    required int colorA,
    required int previewMaxEdge,
    required int previewQuality,
    required bool encodePreviewJpeg,
  }) async {
    await _ensureInitialized();
    final line = DrawLine(
      x0: x0,
      y0: y0,
      x1: x1,
      y1: y1,
      colorR: colorR,
      colorG: colorG,
      colorB: colorB,
      colorA: colorA,
    );
    return _drawOp(
      width: width,
      height: height,
      pixels: pixels,
      draw: (buffer) => RustImageEditor.drawLineRgba(buffer, line: line),
      previewMaxEdge: previewMaxEdge,
      previewQuality: previewQuality,
      encodePreviewJpeg: encodePreviewJpeg,
    );
  }

  @SquadronMethod()
  Future<Map<String, Object>> drawCircle({
    required int width,
    required int height,
    required TransferableTypedData pixels,
    required int centerX,
    required int centerY,
    required int radius,
    required int colorR,
    required int colorG,
    required int colorB,
    required int colorA,
    required int previewMaxEdge,
    required int previewQuality,
    required bool encodePreviewJpeg,
  }) async {
    await _ensureInitialized();
    final circle = DrawCircle(
      centerX: centerX,
      centerY: centerY,
      radius: radius,
      colorR: colorR,
      colorG: colorG,
      colorB: colorB,
      colorA: colorA,
    );
    return _drawOp(
      width: width,
      height: height,
      pixels: pixels,
      draw: (buffer) => RustImageEditor.drawCircleRgba(buffer, circle: circle),
      previewMaxEdge: previewMaxEdge,
      previewQuality: previewQuality,
      encodePreviewJpeg: encodePreviewJpeg,
    );
  }

  @SquadronMethod()
  Future<Map<String, Object>> drawText({
    required int width,
    required int height,
    required TransferableTypedData pixels,
    required String text,
    required int x,
    required int y,
    required double fontSize,
    required int colorR,
    required int colorG,
    required int colorB,
    required int colorA,
    required int previewMaxEdge,
    required int previewQuality,
    required bool encodePreviewJpeg,
  }) async {
    await _ensureInitialized();
    final overlay = TextOverlay(
      text: text,
      x: x,
      y: y,
      fontSize: fontSize,
      colorR: colorR,
      colorG: colorG,
      colorB: colorB,
      colorA: colorA,
    );
    return _drawOp(
      width: width,
      height: height,
      pixels: pixels,
      draw: (buffer) => RustImageEditor.drawTextRgba(buffer, overlay: overlay),
      previewMaxEdge: previewMaxEdge,
      previewQuality: previewQuality,
      encodePreviewJpeg: encodePreviewJpeg,
    );
  }

  @SquadronMethod()
  Future<Map<String, Object>> overlayRgba({
    required int width,
    required int height,
    required TransferableTypedData pixels,
    required TransferableTypedData overlayBytes,
    required int x,
    required int y,
    required int blendModeIndex,
    required int overlayWidth,
    required int overlayHeight,
    required int previewMaxEdge,
    required int previewQuality,
    required bool encodePreviewJpeg,
  }) async {
    await _ensureInitialized();
    final blend = BlendMode.values[blendModeIndex];
    var buffer = RgbaImageBuffer(width: width, height: height, pixels: pixels.materialize().asUint8List());
    buffer = RustImageEditor.overlayRgba(
      buffer,
      overlayBytes.materialize().asUint8List(),
      x: x,
      y: y,
      blendMode: blend,
      overlayWidth: overlayWidth,
      overlayHeight: overlayHeight,
    );
    TransferableTypedData? previewTd;
    if (encodePreviewJpeg) {
      final preview = _encodePreviewBuffer(buffer, previewMaxEdge, previewQuality);
      previewTd = TransferableTypedData.fromList([preview]);
    }
    return {
      'width': buffer.width,
      'height': buffer.height,
      'pixels': TransferableTypedData.fromList([buffer.pixels]),
      if (previewTd != null) 'preview': previewTd,
    };
  }

  @SquadronMethod()
  Future<Map<String, Object>> decodeRgba(TransferableTypedData bytes) async {
    await _ensureInitialized();
    final decoded = RustImageEditor.decodeToRgba(bytes.materialize().asUint8List(), fixExif: true);
    return {
      'width': decoded.width,
      'height': decoded.height,
      'pixels': TransferableTypedData.fromList([decoded.pixels]),
    };
  }

  @SquadronMethod()
  Future<Map<String, Object>> convertCameraImage({
    required int width,
    required int height,
    required List<TransferableTypedData> planesData,
    required List<int> planesBytesPerRow,
    required List<int?> planesBytesPerPixel,
    required int liveCameraMaxEdge,
    required bool isAndroid,
  }) async {
    final planesCount = planesData.length;
    final planes = <_IsolatePlane>[];
    for (var i = 0; i < planesCount; i++) {
      planes.add(_IsolatePlane(
        bytes: planesData[i].materialize().asUint8List(),
        bytesPerRow: planesBytesPerRow[i],
        bytesPerPixel: planesBytesPerPixel[i],
      ));
    }

    RgbaImageBuffer? src;
    if (planesCount == 2) {
      src = _nv21ToRgba(width, height, planes);
    } else if (planesCount >= 3) {
      src = _yuv420ToRgba(width, height, planes);
    }

    if (src == null) {
      throw StateError('Unsupported camera image format');
    }

    var base = _downscaleMaxEdge(src, liveCameraMaxEdge);
    base = _mirrorHorizontal(base, isAndroid);

    return {
      'width': base.width,
      'height': base.height,
      'pixels': TransferableTypedData.fromList([base.pixels]),
    };
  }
}

Map<String, Object> _drawOp({
  required int width,
  required int height,
  required TransferableTypedData pixels,
  required RgbaImageBuffer Function(RgbaImageBuffer buffer) draw,
  required int previewMaxEdge,
  required int previewQuality,
  required bool encodePreviewJpeg,
}) {
  var buffer = RgbaImageBuffer(width: width, height: height, pixels: pixels.materialize().asUint8List());
  buffer = draw(buffer);
  TransferableTypedData? previewTd;
  if (encodePreviewJpeg) {
    final preview = RustImageEditor.encodeRgbaPreview(
      buffer,
      maxEdge: previewMaxEdge,
      quality: previewQuality,
    );
    previewTd = TransferableTypedData.fromList([preview]);
  }
  return {
    'width': buffer.width,
    'height': buffer.height,
    'pixels': TransferableTypedData.fromList([buffer.pixels]),
    if (previewTd != null) 'preview': previewTd,
  };
}

Uint8List _bytesTransform(
  Uint8List bytes,
  String op,
  Map<String, Object?> params,
) {
  switch (op) {
    case 'compress':
      return RustImageEditor.compress(
        bytes: bytes,
        format: OutputFormat.values[params['format']! as int],
        quality: params['quality']! as int,
      );
    case 'resize':
      return RustImageEditor.resize(
        bytes: bytes,
        width: params['width']! as int,
        height: params['height']! as int,
        algorithm: ResizeAlgorithm.values[params['algorithm']! as int],
        format: OutputFormat.values[params['format']! as int],
        quality: params['quality']! as int,
        backend: ProcessingBackend.values[params['backend']! as int],
      );
    case 'thumbnail':
      return RustImageEditor.thumbnail(
        bytes: bytes,
        maxEdge: params['maxEdge']! as int,
        format: OutputFormat.values[params['format']! as int],
        quality: params['quality']! as int,
        backend: ProcessingBackend.values[params['backend']! as int],
      );
    case 'crop':
      return RustImageEditor.crop(
        bytes: bytes,
        x: params['x']! as int,
        y: params['y']! as int,
        width: params['width']! as int,
        height: params['height']! as int,
        format: OutputFormat.values[params['format']! as int],
        quality: params['quality']! as int,
      );
    case 'rotate':
      return RustImageEditor.rotate(
        bytes: bytes,
        rotation: Rotation.values[params['rotation']! as int],
        format: OutputFormat.values[params['format']! as int],
        quality: params['quality']! as int,
      );
    case 'fixExif':
      return RustImageEditor.fixExif(
        bytes: bytes,
        format: OutputFormat.values[params['format']! as int],
        quality: params['quality']! as int,
      );
    case 'blurHashDecode':
      return RustImageEditor.blurHashDecode(
        hash: params['hash']! as String,
        width: params['width']! as int,
        height: params['height']! as int,
        format: OutputFormat.values[params['format']! as int],
        quality: params['quality']! as int,
      );
    default:
      throw UnsupportedError('bytesTransform: $op');
  }
}

Uint8List _encodePreviewBuffer(RgbaImageBuffer buffer, int previewMaxEdge, int quality) {
  var b = buffer;
  final maxDim = b.width > b.height ? b.width : b.height;
  if (maxDim > previewMaxEdge) {
    final scale = previewMaxEdge / maxDim;
    final w = (b.width * scale).round().clamp(1, b.width);
    final h = (b.height * scale).round().clamp(1, b.height);
    b = RustImageEditor.resizeRgba(
      b,
      width: w,
      height: h,
      algorithm: ResizeAlgorithm.box,
      backend: ProcessingBackend.cpu,
    );
  }
  return RustImageEditor.encodeRgbaPreview(
    b,
    maxEdge: previewMaxEdge,
    quality: quality,
  );
}

class _IsolatePlane {
  final Uint8List bytes;
  final int bytesPerRow;
  final int? bytesPerPixel;

  const _IsolatePlane({
    required this.bytes,
    required this.bytesPerRow,
    this.bytesPerPixel,
  });
}

RgbaImageBuffer? _yuv420ToRgba(int width, int height, List<_IsolatePlane> planes) {
  final yPlane = planes[0];
  final uPlane = planes[1];
  final vPlane = planes[2];
  final uPixel = uPlane.bytesPerPixel ?? 1;
  final vPixel = vPlane.bytesPerPixel ?? 1;

  final out = Uint8List(width * height * 4);
  var o = 0;
  for (var y = 0; y < height; y++) {
    final yRow = y * yPlane.bytesPerRow;
    final uvRow = (y >> 1);
    for (var x = 0; x < width; x++) {
      final yi = yRow + x;
      if (yi >= yPlane.bytes.length) continue;
      final uvi = uvRow * uPlane.bytesPerRow + (x >> 1) * uPixel;
      final vvi = uvRow * vPlane.bytesPerRow + (x >> 1) * vPixel;
      if (uvi >= uPlane.bytes.length || vvi >= vPlane.bytes.length) continue;

      final rgb = _yuvToRgb(
        yPlane.bytes[yi],
        uPlane.bytes[uvi],
        vPlane.bytes[vvi],
      );
      out[o++] = rgb[0];
      out[o++] = rgb[1];
      out[o++] = rgb[2];
      out[o++] = 255;
    }
  }
  return RgbaImageBuffer(width: width, height: height, pixels: out);
}

RgbaImageBuffer? _nv21ToRgba(int width, int height, List<_IsolatePlane> planes) {
  final yPlane = planes[0];
  final uvPlane = planes[1];
  final uvPixel = uvPlane.bytesPerPixel ?? 2;

  final out = Uint8List(width * height * 4);
  var o = 0;
  for (var y = 0; y < height; y++) {
    final yRow = y * yPlane.bytesPerRow;
    final uvRow = (y >> 1) * uvPlane.bytesPerRow;
    for (var x = 0; x < width; x++) {
      final yi = yRow + x;
      if (yi >= yPlane.bytes.length) continue;
      final uvIndex = uvRow + (x >> 1) * uvPixel;
      if (uvIndex + 1 >= uvPlane.bytes.length) continue;

      final vVal = uvPlane.bytes[uvIndex];
      final uVal = uvPlane.bytes[uvIndex + 1];
      final rgb = _yuvToRgb(yPlane.bytes[yi], uVal, vVal);
      out[o++] = rgb[0];
      out[o++] = rgb[1];
      out[o++] = rgb[2];
      out[o++] = 255;
    }
  }
  return RgbaImageBuffer(width: width, height: height, pixels: out);
}

RgbaImageBuffer _downscaleMaxEdge(RgbaImageBuffer src, int maxEdge) {
  if (maxEdge <= 0) return src;
  final w = src.width;
  final h = src.height;
  final edge = w > h ? w : h;
  if (edge <= maxEdge) return src;
  final scale = maxEdge / edge;
  final nw = (w * scale).round().clamp(1, w);
  final nh = (h * scale).round().clamp(1, h);
  final out = Uint8List(nw * nh * 4);
  for (var y = 0; y < nh; y++) {
    final sy = (y * h / nh).floor().clamp(0, h - 1);
    for (var x = 0; x < nw; x++) {
      final sx = (x * w / nw).floor().clamp(0, w - 1);
      final si = (sy * w + sx) * 4;
      final di = (y * nw + x) * 4;
      out[di] = src.pixels[si];
      out[di + 1] = src.pixels[si + 1];
      out[di + 2] = src.pixels[si + 2];
      out[di + 3] = src.pixels[si + 3];
    }
  }
  return RgbaImageBuffer(width: nw, height: nh, pixels: out);
}

RgbaImageBuffer _mirrorHorizontal(RgbaImageBuffer src, bool isAndroid) {
  if (!isAndroid) return src;
  final w = src.width;
  final h = src.height;
  final out = Uint8List.fromList(src.pixels);
  for (var y = 0; y < h; y++) {
    final row = y * w * 4;
    for (var x = 0; x < w ~/ 2; x++) {
      final left = row + x * 4;
      final right = row + (w - 1 - x) * 4;
      for (var c = 0; c < 4; c++) {
        final t = out[left + c];
        out[left + c] = out[right + c];
        out[right + c] = t;
      }
    }
  }
  return RgbaImageBuffer(width: w, height: h, pixels: out);
}

List<int> _yuvToRgb(int y, int u, int v) {
  final c = y - 16;
  final d = u - 128;
  final e = v - 128;
  final r = ((298 * c + 409 * e + 128) >> 8).clamp(0, 255);
  final g = ((298 * c - 100 * d - 208 * e + 128) >> 8).clamp(0, 255);
  final b = ((298 * c + 516 * d + 128) >> 8).clamp(0, 255);
  return [r, g, b];
}
