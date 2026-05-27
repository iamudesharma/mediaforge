// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'rust_worker_service.dart';

// **************************************************************************
// Generator: WorkerGenerator 9.3.0 (Squadron 7.4.3)
// **************************************************************************

// dart format width=80
/// Command ids used in operations map
const int _$applyBeautyId = 1;
const int _$applyCropRgbaId = 2;
const int _$applyEditPipelineFullId = 3;
const int _$applySkinSmoothId = 4;
const int _$bakeLayersRgbaId = 5;
const int _$batchResizeDemoId = 6;
const int _$blurHashEncodeId = 7;
const int _$buildSkinMaskId = 8;
const int _$bytesTransformId = 9;
const int _$convertCameraImageId = 10;
const int _$decodeAndPrepareEditBaseId = 11;
const int _$decodeProgressiveId = 12;
const int _$decodeRgbaId = 13;
const int _$drawCircleId = 14;
const int _$drawLineId = 15;
const int _$drawTextId = 16;
const int _$encodeFullRgbaId = 17;
const int _$encodePreviewId = 18;
const int _$filterBytesId = 19;
const int _$filterRgbaId = 20;
const int _$overlayRgbaId = 21;
const int _$prepareEditBaseFromRgbaId = 22;
const int _$replayEditPipelineId = 23;
const int _$resizeRgbaId = 24;
const int _$transcribeHeicToPngId = 25;

/// WorkerService operations for RustWorkerService
extension on RustWorkerService {
  OperationsMap _$getOperations() => OperationsMap({
    _$applyBeautyId: ($req) async {
      final Map<String, Object> $res;
      try {
        final $dsr = _$Deser(contextAware: false);
        $res = await applyBeauty(
          width: $dsr.$0($req.args[0]),
          height: $dsr.$0($req.args[1]),
          pixels: $dsr.$1($req.args[2]),
          landmarks: $dsr.$3($req.args[3]),
          faceContourCount: $dsr.$0($req.args[4]),
          regionCounts: $dsr.$4($req.args[5]),
          maskW: $dsr.$0($req.args[6]),
          maskH: $dsr.$0($req.args[7]),
          maskPixels: $dsr.$1($req.args[8]),
          skinSmooth: $dsr.$5($req.args[9]),
          eyeBrighten: $dsr.$5($req.args[10]),
          lipTintIndex: $dsr.$0($req.args[11]),
          lipTintStrength: $dsr.$5($req.args[12]),
          lipPlump: $dsr.$5($req.args[13]),
          blush: $dsr.$5($req.args[14]),
          underEye: $dsr.$5($req.args[15]),
          teethWhiten: $dsr.$5($req.args[16]),
          exW: $dsr.$0($req.args[17]),
          exH: $dsr.$0($req.args[18]),
          exRaw: $dsr.$6($req.args[19]),
        );
      } finally {}
      return $res;
    },
    _$applyCropRgbaId: ($req) async {
      final Map<String, Object> $res;
      try {
        final $dsr = _$Deser(contextAware: false);
        $res = await applyCropRgba(
          width: $dsr.$0($req.args[0]),
          height: $dsr.$0($req.args[1]),
          pixels: $dsr.$1($req.args[2]),
          straighten: $dsr.$5($req.args[3]),
          cropX: $dsr.$0($req.args[4]),
          cropY: $dsr.$0($req.args[5]),
          cropW: $dsr.$0($req.args[6]),
          cropH: $dsr.$0($req.args[7]),
          liveEditMaxEdge: $dsr.$0($req.args[8]),
          previewMaxEdge: $dsr.$0($req.args[9]),
          previewQuality: $dsr.$0($req.args[10]),
        );
      } finally {}
      return $res;
    },
    _$applyEditPipelineFullId: ($req) async {
      final Map<String, Object> $res;
      try {
        final $dsr = _$Deser(contextAware: false);
        $res = await applyEditPipelineFull(
          width: $dsr.$0($req.args[0]),
          height: $dsr.$0($req.args[1]),
          pixels: $dsr.$1($req.args[2]),
          ops: $dsr.$8($req.args[3]),
          backendIndex: $dsr.$0($req.args[4]),
        );
      } finally {}
      return $res;
    },
    _$applySkinSmoothId: ($req) async {
      final Map<String, Object> $res;
      try {
        final $dsr = _$Deser(contextAware: false);
        $res = await applySkinSmooth(
          width: $dsr.$0($req.args[0]),
          height: $dsr.$0($req.args[1]),
          pixels: $dsr.$1($req.args[2]),
          maskW: $dsr.$0($req.args[3]),
          maskH: $dsr.$0($req.args[4]),
          maskPixels: $dsr.$1($req.args[5]),
          strength: $dsr.$5($req.args[6]),
        );
      } finally {}
      return $res;
    },
    _$bakeLayersRgbaId: ($req) async {
      final Map<String, Object> $res;
      try {
        final $dsr = _$Deser(contextAware: false);
        $res = await bakeLayersRgba(
          width: $dsr.$0($req.args[0]),
          height: $dsr.$0($req.args[1]),
          pixels: $dsr.$1($req.args[2]),
          rasterLayers: $dsr.$10($req.args[3]),
          paintStrokes: $dsr.$12($req.args[4]),
        );
      } finally {}
      return $res;
    },
    _$batchResizeDemoId: ($req) async {
      final Uint8List $res;
      try {
        final $dsr = _$Deser(contextAware: false);
        $res = await batchResizeDemo(
          bytes: $dsr.$1($req.args[0]),
          backendIndex: $dsr.$0($req.args[1]),
        );
      } finally {}
      return $res;
    },
    _$blurHashEncodeId: ($req) async {
      final String $res;
      try {
        final $dsr = _$Deser(contextAware: false);
        $res = await blurHashEncode($dsr.$1($req.args[0]));
      } finally {}
      return $res;
    },
    _$buildSkinMaskId: ($req) async {
      final Map<String, Object> $res;
      try {
        final $dsr = _$Deser(contextAware: false);
        $res = await buildSkinMask(
          landmarks: $dsr.$3($req.args[0]),
          faceContourCount: $dsr.$0($req.args[1]),
          regionCounts: $dsr.$4($req.args[2]),
          segW: $dsr.$0($req.args[3]),
          segH: $dsr.$0($req.args[4]),
          segRaw: $dsr.$6($req.args[5]),
          width: $dsr.$0($req.args[6]),
          height: $dsr.$0($req.args[7]),
        );
      } finally {}
      return $res;
    },
    _$bytesTransformId: ($req) async {
      final Uint8List $res;
      try {
        final $dsr = _$Deser(contextAware: false);
        $res = await bytesTransform(
          op: $dsr.$13($req.args[0]),
          bytes: $dsr.$1($req.args[1]),
          params: $dsr.$15($req.args[2]),
        );
      } finally {}
      return $res;
    },
    _$convertCameraImageId: ($req) async {
      final Map<String, Object> $res;
      try {
        final $dsr = _$Deser(contextAware: false);
        $res = await convertCameraImage(
          width: $dsr.$0($req.args[0]),
          height: $dsr.$0($req.args[1]),
          planesData: $dsr.$16($req.args[2]),
          planesBytesPerRow: $dsr.$4($req.args[3]),
          planesBytesPerPixel: $dsr.$17($req.args[4]),
          liveCameraMaxEdge: $dsr.$0($req.args[5]),
          isAndroid: $dsr.$18($req.args[6]),
        );
      } finally {}
      return $res;
    },
    _$decodeAndPrepareEditBaseId: ($req) async {
      final Map<String, Object> $res;
      try {
        final $dsr = _$Deser(contextAware: false);
        $res = await decodeAndPrepareEditBase(
          bytes: $dsr.$1($req.args[0]),
          liveEditMaxEdge: $dsr.$0($req.args[1]),
        );
      } finally {}
      return $res;
    },
    _$decodeProgressiveId: ($req) async {
      final Map<String, Object> $res;
      try {
        final $dsr = _$Deser(contextAware: false);
        $res = await decodeProgressive(
          bytes: $dsr.$1($req.args[0]),
          previewMaxEdge: $dsr.$0($req.args[1]),
          liveEditMaxEdge: $dsr.$0($req.args[2]),
        );
      } finally {}
      return $res;
    },
    _$decodeRgbaId: ($req) async {
      final Map<String, Object> $res;
      try {
        final $dsr = _$Deser(contextAware: false);
        $res = await decodeRgba($dsr.$1($req.args[0]));
      } finally {}
      return $res;
    },
    _$drawCircleId: ($req) async {
      final Map<String, Object> $res;
      try {
        final $dsr = _$Deser(contextAware: false);
        $res = await drawCircle(
          width: $dsr.$0($req.args[0]),
          height: $dsr.$0($req.args[1]),
          pixels: $dsr.$1($req.args[2]),
          centerX: $dsr.$0($req.args[3]),
          centerY: $dsr.$0($req.args[4]),
          radius: $dsr.$0($req.args[5]),
          colorR: $dsr.$0($req.args[6]),
          colorG: $dsr.$0($req.args[7]),
          colorB: $dsr.$0($req.args[8]),
          colorA: $dsr.$0($req.args[9]),
          previewMaxEdge: $dsr.$0($req.args[10]),
          previewQuality: $dsr.$0($req.args[11]),
          encodePreviewJpeg: $dsr.$18($req.args[12]),
        );
      } finally {}
      return $res;
    },
    _$drawLineId: ($req) async {
      final Map<String, Object> $res;
      try {
        final $dsr = _$Deser(contextAware: false);
        $res = await drawLine(
          width: $dsr.$0($req.args[0]),
          height: $dsr.$0($req.args[1]),
          pixels: $dsr.$1($req.args[2]),
          x0: $dsr.$0($req.args[3]),
          y0: $dsr.$0($req.args[4]),
          x1: $dsr.$0($req.args[5]),
          y1: $dsr.$0($req.args[6]),
          colorR: $dsr.$0($req.args[7]),
          colorG: $dsr.$0($req.args[8]),
          colorB: $dsr.$0($req.args[9]),
          colorA: $dsr.$0($req.args[10]),
          previewMaxEdge: $dsr.$0($req.args[11]),
          previewQuality: $dsr.$0($req.args[12]),
          encodePreviewJpeg: $dsr.$18($req.args[13]),
        );
      } finally {}
      return $res;
    },
    _$drawTextId: ($req) async {
      final Map<String, Object> $res;
      try {
        final $dsr = _$Deser(contextAware: false);
        $res = await drawText(
          width: $dsr.$0($req.args[0]),
          height: $dsr.$0($req.args[1]),
          pixels: $dsr.$1($req.args[2]),
          text: $dsr.$13($req.args[3]),
          x: $dsr.$0($req.args[4]),
          y: $dsr.$0($req.args[5]),
          fontSize: $dsr.$5($req.args[6]),
          colorR: $dsr.$0($req.args[7]),
          colorG: $dsr.$0($req.args[8]),
          colorB: $dsr.$0($req.args[9]),
          colorA: $dsr.$0($req.args[10]),
          previewMaxEdge: $dsr.$0($req.args[11]),
          previewQuality: $dsr.$0($req.args[12]),
          encodePreviewJpeg: $dsr.$18($req.args[13]),
        );
      } finally {}
      return $res;
    },
    _$encodeFullRgbaId: ($req) async {
      final Uint8List $res;
      try {
        final $dsr = _$Deser(contextAware: false);
        $res = await encodeFullRgba(
          width: $dsr.$0($req.args[0]),
          height: $dsr.$0($req.args[1]),
          pixels: $dsr.$1($req.args[2]),
          formatIndex: $dsr.$0($req.args[3]),
          quality: $dsr.$0($req.args[4]),
        );
      } finally {}
      return $res;
    },
    _$encodePreviewId: ($req) async {
      final Uint8List $res;
      try {
        final $dsr = _$Deser(contextAware: false);
        $res = await encodePreview(
          width: $dsr.$0($req.args[0]),
          height: $dsr.$0($req.args[1]),
          pixels: $dsr.$1($req.args[2]),
          previewMaxEdge: $dsr.$0($req.args[3]),
          quality: $dsr.$0($req.args[4]),
        );
      } finally {}
      return $res;
    },
    _$filterBytesId: ($req) async {
      final Uint8List $res;
      try {
        final $dsr = _$Deser(contextAware: false);
        $res = await filterBytes(
          bytes: $dsr.$1($req.args[0]),
          filterKind: $dsr.$13($req.args[1]),
          filterParams: $dsr.$15($req.args[2]),
          formatIndex: $dsr.$0($req.args[3]),
          quality: $dsr.$0($req.args[4]),
        );
      } finally {}
      return $res;
    },
    _$filterRgbaId: ($req) async {
      final Map<String, Object> $res;
      try {
        final $dsr = _$Deser(contextAware: false);
        $res = await filterRgba(
          width: $dsr.$0($req.args[0]),
          height: $dsr.$0($req.args[1]),
          pixels: $dsr.$1($req.args[2]),
          filterKind: $dsr.$13($req.args[3]),
          filterParams: $dsr.$15($req.args[4]),
          backendIndex: $dsr.$0($req.args[5]),
          previewMaxEdge: $dsr.$0($req.args[6]),
          previewQuality: $dsr.$0($req.args[7]),
          encodePreviewJpeg: $dsr.$18($req.args[8]),
        );
      } finally {}
      return $res;
    },
    _$overlayRgbaId: ($req) async {
      final Map<String, Object> $res;
      try {
        final $dsr = _$Deser(contextAware: false);
        $res = await overlayRgba(
          width: $dsr.$0($req.args[0]),
          height: $dsr.$0($req.args[1]),
          pixels: $dsr.$1($req.args[2]),
          overlayBytes: $dsr.$1($req.args[3]),
          x: $dsr.$0($req.args[4]),
          y: $dsr.$0($req.args[5]),
          blendModeIndex: $dsr.$0($req.args[6]),
          overlayWidth: $dsr.$0($req.args[7]),
          overlayHeight: $dsr.$0($req.args[8]),
          previewMaxEdge: $dsr.$0($req.args[9]),
          previewQuality: $dsr.$0($req.args[10]),
          encodePreviewJpeg: $dsr.$18($req.args[11]),
        );
      } finally {}
      return $res;
    },
    _$prepareEditBaseFromRgbaId: ($req) async {
      final Map<String, Object> $res;
      try {
        final $dsr = _$Deser(contextAware: false);
        $res = await prepareEditBaseFromRgba(
          width: $dsr.$0($req.args[0]),
          height: $dsr.$0($req.args[1]),
          pixels: $dsr.$1($req.args[2]),
          liveEditMaxEdge: $dsr.$0($req.args[3]),
        );
      } finally {}
      return $res;
    },
    _$replayEditPipelineId: ($req) async {
      final Map<String, Object> $res;
      try {
        final $dsr = _$Deser(contextAware: false);
        $res = await replayEditPipeline(
          width: $dsr.$0($req.args[0]),
          height: $dsr.$0($req.args[1]),
          pixels: $dsr.$1($req.args[2]),
          ops: $dsr.$8($req.args[3]),
          backendIndex: $dsr.$0($req.args[4]),
          previewMaxEdge: $dsr.$0($req.args[5]),
          previewQuality: $dsr.$0($req.args[6]),
          encodePreviewJpeg: $dsr.$18($req.args[7]),
        );
      } finally {}
      return $res;
    },
    _$resizeRgbaId: ($req) async {
      final Map<String, Object> $res;
      try {
        final $dsr = _$Deser(contextAware: false);
        $res = await resizeRgba(
          width: $dsr.$0($req.args[0]),
          height: $dsr.$0($req.args[1]),
          pixels: $dsr.$1($req.args[2]),
          targetW: $dsr.$0($req.args[3]),
          targetH: $dsr.$0($req.args[4]),
          algorithmIndex: $dsr.$0($req.args[5]),
          backendIndex: $dsr.$0($req.args[6]),
          previewMaxEdge: $dsr.$0($req.args[7]),
          previewQuality: $dsr.$0($req.args[8]),
        );
      } finally {}
      return $res;
    },
    _$transcribeHeicToPngId: ($req) async {
      final TransferableTypedData $res;
      try {
        final $dsr = _$Deser(contextAware: false);
        $res = await transcribeHeicToPng($dsr.$1($req.args[0]));
      } finally {}
      return $res;
    },
  });
}

/// Invoker for RustWorkerService, implements the public interface to invoke the
/// remote service.
base mixin _$RustWorkerService$Invoker on Invoker implements RustWorkerService {
  @override
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
    final dynamic $res = await send(
      _$applyBeautyId,
      args: [
        width,
        height,
        pixels,
        landmarks,
        faceContourCount,
        regionCounts,
        maskW,
        maskH,
        maskPixels,
        skinSmooth,
        eyeBrighten,
        lipTintIndex,
        lipTintStrength,
        lipPlump,
        blush,
        underEye,
        teethWhiten,
        exW,
        exH,
        exRaw,
      ],
    );
    try {
      final $dsr = _$Deser(contextAware: false);
      return $dsr.$19($res);
    } finally {}
  }

  @override
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
    final dynamic $res = await send(
      _$applyCropRgbaId,
      args: [
        width,
        height,
        pixels,
        straighten,
        cropX,
        cropY,
        cropW,
        cropH,
        liveEditMaxEdge,
        previewMaxEdge,
        previewQuality,
      ],
    );
    try {
      final $dsr = _$Deser(contextAware: false);
      return $dsr.$19($res);
    } finally {}
  }

  @override
  Future<Map<String, Object>> applyEditPipelineFull({
    required int width,
    required int height,
    required TransferableTypedData pixels,
    required List<EditOp> ops,
    required int backendIndex,
  }) async {
    final dynamic $res = await send(
      _$applyEditPipelineFullId,
      args: [width, height, pixels, ops, backendIndex],
    );
    try {
      final $dsr = _$Deser(contextAware: false);
      return $dsr.$19($res);
    } finally {}
  }

  @override
  Future<Map<String, Object>> applySkinSmooth({
    required int width,
    required int height,
    required TransferableTypedData pixels,
    required int maskW,
    required int maskH,
    required TransferableTypedData maskPixels,
    required double strength,
  }) async {
    final dynamic $res = await send(
      _$applySkinSmoothId,
      args: [width, height, pixels, maskW, maskH, maskPixels, strength],
    );
    try {
      final $dsr = _$Deser(contextAware: false);
      return $dsr.$19($res);
    } finally {}
  }

  @override
  Future<Map<String, Object>> bakeLayersRgba({
    required int width,
    required int height,
    required TransferableTypedData pixels,
    required List<RasterLayerInput> rasterLayers,
    required List<PaintStrokeInput> paintStrokes,
  }) async {
    final dynamic $res = await send(
      _$bakeLayersRgbaId,
      args: [width, height, pixels, rasterLayers, paintStrokes],
    );
    try {
      final $dsr = _$Deser(contextAware: false);
      return $dsr.$19($res);
    } finally {}
  }

  @override
  Future<Uint8List> batchResizeDemo({
    required TransferableTypedData bytes,
    required int backendIndex,
  }) async {
    final dynamic $res = await send(
      _$batchResizeDemoId,
      args: [bytes, backendIndex],
    );
    try {
      final $dsr = _$Deser(contextAware: false);
      return $dsr.$20($res);
    } finally {}
  }

  @override
  Future<String> blurHashEncode(TransferableTypedData bytes) async {
    final dynamic $res = await send(_$blurHashEncodeId, args: [bytes]);
    try {
      final $dsr = _$Deser(contextAware: false);
      return $dsr.$13($res);
    } finally {}
  }

  @override
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
    final dynamic $res = await send(
      _$buildSkinMaskId,
      args: [
        landmarks,
        faceContourCount,
        regionCounts,
        segW,
        segH,
        segRaw,
        width,
        height,
      ],
    );
    try {
      final $dsr = _$Deser(contextAware: false);
      return $dsr.$19($res);
    } finally {}
  }

  @override
  Future<Uint8List> bytesTransform({
    required String op,
    required TransferableTypedData bytes,
    required Map<dynamic, dynamic> params,
  }) async {
    final dynamic $res = await send(
      _$bytesTransformId,
      args: [op, bytes, params],
    );
    try {
      final $dsr = _$Deser(contextAware: false);
      return $dsr.$20($res);
    } finally {}
  }

  @override
  Future<Map<String, Object>> convertCameraImage({
    required int width,
    required int height,
    required List<TransferableTypedData> planesData,
    required List<int> planesBytesPerRow,
    required List<int?> planesBytesPerPixel,
    required int liveCameraMaxEdge,
    required bool isAndroid,
  }) async {
    final dynamic $res = await send(
      _$convertCameraImageId,
      args: [
        width,
        height,
        planesData,
        planesBytesPerRow,
        planesBytesPerPixel,
        liveCameraMaxEdge,
        isAndroid,
      ],
    );
    try {
      final $dsr = _$Deser(contextAware: false);
      return $dsr.$19($res);
    } finally {}
  }

  @override
  Future<Map<String, Object>> decodeAndPrepareEditBase({
    required TransferableTypedData bytes,
    required int liveEditMaxEdge,
  }) async {
    final dynamic $res = await send(
      _$decodeAndPrepareEditBaseId,
      args: [bytes, liveEditMaxEdge],
    );
    try {
      final $dsr = _$Deser(contextAware: false);
      return $dsr.$19($res);
    } finally {}
  }

  @override
  Future<Map<String, Object>> decodeProgressive({
    required TransferableTypedData bytes,
    required int previewMaxEdge,
    required int liveEditMaxEdge,
  }) async {
    final dynamic $res = await send(
      _$decodeProgressiveId,
      args: [bytes, previewMaxEdge, liveEditMaxEdge],
    );
    try {
      final $dsr = _$Deser(contextAware: false);
      return $dsr.$19($res);
    } finally {}
  }

  @override
  Future<Map<String, Object>> decodeRgba(TransferableTypedData bytes) async {
    final dynamic $res = await send(_$decodeRgbaId, args: [bytes]);
    try {
      final $dsr = _$Deser(contextAware: false);
      return $dsr.$19($res);
    } finally {}
  }

  @override
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
    final dynamic $res = await send(
      _$drawCircleId,
      args: [
        width,
        height,
        pixels,
        centerX,
        centerY,
        radius,
        colorR,
        colorG,
        colorB,
        colorA,
        previewMaxEdge,
        previewQuality,
        encodePreviewJpeg,
      ],
    );
    try {
      final $dsr = _$Deser(contextAware: false);
      return $dsr.$19($res);
    } finally {}
  }

  @override
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
    final dynamic $res = await send(
      _$drawLineId,
      args: [
        width,
        height,
        pixels,
        x0,
        y0,
        x1,
        y1,
        colorR,
        colorG,
        colorB,
        colorA,
        previewMaxEdge,
        previewQuality,
        encodePreviewJpeg,
      ],
    );
    try {
      final $dsr = _$Deser(contextAware: false);
      return $dsr.$19($res);
    } finally {}
  }

  @override
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
    final dynamic $res = await send(
      _$drawTextId,
      args: [
        width,
        height,
        pixels,
        text,
        x,
        y,
        fontSize,
        colorR,
        colorG,
        colorB,
        colorA,
        previewMaxEdge,
        previewQuality,
        encodePreviewJpeg,
      ],
    );
    try {
      final $dsr = _$Deser(contextAware: false);
      return $dsr.$19($res);
    } finally {}
  }

  @override
  Future<Uint8List> encodeFullRgba({
    required int width,
    required int height,
    required TransferableTypedData pixels,
    required int formatIndex,
    required int quality,
  }) async {
    final dynamic $res = await send(
      _$encodeFullRgbaId,
      args: [width, height, pixels, formatIndex, quality],
    );
    try {
      final $dsr = _$Deser(contextAware: false);
      return $dsr.$20($res);
    } finally {}
  }

  @override
  Future<Uint8List> encodePreview({
    required int width,
    required int height,
    required TransferableTypedData pixels,
    required int previewMaxEdge,
    required int quality,
  }) async {
    final dynamic $res = await send(
      _$encodePreviewId,
      args: [width, height, pixels, previewMaxEdge, quality],
    );
    try {
      final $dsr = _$Deser(contextAware: false);
      return $dsr.$20($res);
    } finally {}
  }

  @override
  Future<Uint8List> filterBytes({
    required TransferableTypedData bytes,
    required String filterKind,
    required Map<dynamic, dynamic> filterParams,
    required int formatIndex,
    required int quality,
  }) async {
    final dynamic $res = await send(
      _$filterBytesId,
      args: [bytes, filterKind, filterParams, formatIndex, quality],
    );
    try {
      final $dsr = _$Deser(contextAware: false);
      return $dsr.$20($res);
    } finally {}
  }

  @override
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
    final dynamic $res = await send(
      _$filterRgbaId,
      args: [
        width,
        height,
        pixels,
        filterKind,
        filterParams,
        backendIndex,
        previewMaxEdge,
        previewQuality,
        encodePreviewJpeg,
      ],
    );
    try {
      final $dsr = _$Deser(contextAware: false);
      return $dsr.$19($res);
    } finally {}
  }

  @override
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
    final dynamic $res = await send(
      _$overlayRgbaId,
      args: [
        width,
        height,
        pixels,
        overlayBytes,
        x,
        y,
        blendModeIndex,
        overlayWidth,
        overlayHeight,
        previewMaxEdge,
        previewQuality,
        encodePreviewJpeg,
      ],
    );
    try {
      final $dsr = _$Deser(contextAware: false);
      return $dsr.$19($res);
    } finally {}
  }

  @override
  Future<Map<String, Object>> prepareEditBaseFromRgba({
    required int width,
    required int height,
    required TransferableTypedData pixels,
    required int liveEditMaxEdge,
  }) async {
    final dynamic $res = await send(
      _$prepareEditBaseFromRgbaId,
      args: [width, height, pixels, liveEditMaxEdge],
    );
    try {
      final $dsr = _$Deser(contextAware: false);
      return $dsr.$19($res);
    } finally {}
  }

  @override
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
    final dynamic $res = await send(
      _$replayEditPipelineId,
      args: [
        width,
        height,
        pixels,
        ops,
        backendIndex,
        previewMaxEdge,
        previewQuality,
        encodePreviewJpeg,
      ],
    );
    try {
      final $dsr = _$Deser(contextAware: false);
      return $dsr.$19($res);
    } finally {}
  }

  @override
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
    final dynamic $res = await send(
      _$resizeRgbaId,
      args: [
        width,
        height,
        pixels,
        targetW,
        targetH,
        algorithmIndex,
        backendIndex,
        previewMaxEdge,
        previewQuality,
      ],
    );
    try {
      final $dsr = _$Deser(contextAware: false);
      return $dsr.$19($res);
    } finally {}
  }

  @override
  Future<TransferableTypedData> transcribeHeicToPng(
    TransferableTypedData bytes,
  ) async {
    final dynamic $res = await send(_$transcribeHeicToPngId, args: [bytes]);
    try {
      final $dsr = _$Deser(contextAware: false);
      return $dsr.$1($res);
    } finally {}
  }
}

/// Facade for RustWorkerService, implements other details of the service unrelated to
/// invoking the remote service.
base mixin _$RustWorkerService$Facade implements RustWorkerService {
  @override
  Future<void> _ensureInitialized() => throw UnimplementedError();

  @override
  // ignore: unused_element
  Future<void>? get _initFuture => throw UnimplementedError();

  @override
  // ignore: unused_element
  set _initFuture(void $value) => throw UnimplementedError();
}

/// WorkerClient for RustWorkerService
final class $RustWorkerService$Client extends WorkerClient
    with _$RustWorkerService$Invoker, _$RustWorkerService$Facade
    implements RustWorkerService {
  $RustWorkerService$Client(PlatformChannel channelInfo)
    : super(Channel.deserialize(channelInfo)!);
}

/// Local worker extension for RustWorkerService
extension $RustWorkerServiceLocalWorkerExt on RustWorkerService {
  // Get a fresh local worker instance.
  LocalWorker<RustWorkerService> getLocalWorker([
    ExceptionManager? exceptionManager,
  ]) => LocalWorker.create(this, _$getOperations(), exceptionManager);
}

/// WorkerService class for RustWorkerService
base class _$RustWorkerService$WorkerService extends RustWorkerService
    implements WorkerService {
  _$RustWorkerService$WorkerService() : super();

  @override
  OperationsMap get operations => _$getOperations();
}

/// Service initializer for RustWorkerService
WorkerService $RustWorkerServiceInitializer(WorkerRequest $req) =>
    _$RustWorkerService$WorkerService();

/// Worker for RustWorkerService
base class RustWorkerServiceWorker extends Worker
    with _$RustWorkerService$Invoker, _$RustWorkerService$Facade
    implements RustWorkerService {
  RustWorkerServiceWorker({
    PlatformThreadHook? threadHook,
    ExceptionManager? exceptionManager,
  }) : super(
         $RustWorkerServiceActivator(Squadron.platformType),
         threadHook: threadHook,
         exceptionManager: exceptionManager,
       );

  RustWorkerServiceWorker.vm({
    PlatformThreadHook? threadHook,
    ExceptionManager? exceptionManager,
  }) : super(
         $RustWorkerServiceActivator(SquadronPlatformType.vm),
         threadHook: threadHook,
         exceptionManager: exceptionManager,
       );

  RustWorkerServiceWorker.js({
    PlatformThreadHook? threadHook,
    ExceptionManager? exceptionManager,
  }) : super(
         $RustWorkerServiceActivator(SquadronPlatformType.js),
         threadHook: threadHook,
         exceptionManager: exceptionManager,
       );

  RustWorkerServiceWorker.wasm({
    PlatformThreadHook? threadHook,
    ExceptionManager? exceptionManager,
  }) : super(
         $RustWorkerServiceActivator(SquadronPlatformType.wasm),
         threadHook: threadHook,
         exceptionManager: exceptionManager,
       );

  @override
  List? getStartArgs() => null;
}

/// Worker pool for RustWorkerService
base class RustWorkerServiceWorkerPool
    extends WorkerPool<RustWorkerServiceWorker>
    with _$RustWorkerService$Facade
    implements RustWorkerService {
  RustWorkerServiceWorkerPool({
    PlatformThreadHook? threadHook,
    ExceptionManager? exceptionManager,
    ConcurrencySettings? concurrencySettings,
  }) : super(
         (ExceptionManager exceptionManager) => RustWorkerServiceWorker(
           threadHook: threadHook,
           exceptionManager: exceptionManager,
         ),
         concurrencySettings: concurrencySettings,
         exceptionManager: exceptionManager,
       );

  RustWorkerServiceWorkerPool.vm({
    PlatformThreadHook? threadHook,
    ExceptionManager? exceptionManager,
    ConcurrencySettings? concurrencySettings,
  }) : super(
         (ExceptionManager exceptionManager) => RustWorkerServiceWorker.vm(
           threadHook: threadHook,
           exceptionManager: exceptionManager,
         ),
         concurrencySettings: concurrencySettings,
         exceptionManager: exceptionManager,
       );

  RustWorkerServiceWorkerPool.js({
    PlatformThreadHook? threadHook,
    ExceptionManager? exceptionManager,
    ConcurrencySettings? concurrencySettings,
  }) : super(
         (ExceptionManager exceptionManager) => RustWorkerServiceWorker.js(
           threadHook: threadHook,
           exceptionManager: exceptionManager,
         ),
         concurrencySettings: concurrencySettings,
         exceptionManager: exceptionManager,
       );

  RustWorkerServiceWorkerPool.wasm({
    PlatformThreadHook? threadHook,
    ExceptionManager? exceptionManager,
    ConcurrencySettings? concurrencySettings,
  }) : super(
         (ExceptionManager exceptionManager) => RustWorkerServiceWorker.wasm(
           threadHook: threadHook,
           exceptionManager: exceptionManager,
         ),
         concurrencySettings: concurrencySettings,
         exceptionManager: exceptionManager,
       );

  @override
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
  }) => execute(
    (w) => w.applyBeauty(
      width: width,
      height: height,
      pixels: pixels,
      landmarks: landmarks,
      faceContourCount: faceContourCount,
      regionCounts: regionCounts,
      maskW: maskW,
      maskH: maskH,
      maskPixels: maskPixels,
      skinSmooth: skinSmooth,
      eyeBrighten: eyeBrighten,
      lipTintIndex: lipTintIndex,
      lipTintStrength: lipTintStrength,
      lipPlump: lipPlump,
      blush: blush,
      underEye: underEye,
      teethWhiten: teethWhiten,
      exW: exW,
      exH: exH,
      exRaw: exRaw,
    ),
  );

  @override
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
  }) => execute(
    (w) => w.applyCropRgba(
      width: width,
      height: height,
      pixels: pixels,
      straighten: straighten,
      cropX: cropX,
      cropY: cropY,
      cropW: cropW,
      cropH: cropH,
      liveEditMaxEdge: liveEditMaxEdge,
      previewMaxEdge: previewMaxEdge,
      previewQuality: previewQuality,
    ),
  );

  @override
  Future<Map<String, Object>> applyEditPipelineFull({
    required int width,
    required int height,
    required TransferableTypedData pixels,
    required List<EditOp> ops,
    required int backendIndex,
  }) => execute(
    (w) => w.applyEditPipelineFull(
      width: width,
      height: height,
      pixels: pixels,
      ops: ops,
      backendIndex: backendIndex,
    ),
  );

  @override
  Future<Map<String, Object>> applySkinSmooth({
    required int width,
    required int height,
    required TransferableTypedData pixels,
    required int maskW,
    required int maskH,
    required TransferableTypedData maskPixels,
    required double strength,
  }) => execute(
    (w) => w.applySkinSmooth(
      width: width,
      height: height,
      pixels: pixels,
      maskW: maskW,
      maskH: maskH,
      maskPixels: maskPixels,
      strength: strength,
    ),
  );

  @override
  Future<Map<String, Object>> bakeLayersRgba({
    required int width,
    required int height,
    required TransferableTypedData pixels,
    required List<RasterLayerInput> rasterLayers,
    required List<PaintStrokeInput> paintStrokes,
  }) => execute(
    (w) => w.bakeLayersRgba(
      width: width,
      height: height,
      pixels: pixels,
      rasterLayers: rasterLayers,
      paintStrokes: paintStrokes,
    ),
  );

  @override
  Future<Uint8List> batchResizeDemo({
    required TransferableTypedData bytes,
    required int backendIndex,
  }) => execute(
    (w) => w.batchResizeDemo(bytes: bytes, backendIndex: backendIndex),
  );

  @override
  Future<String> blurHashEncode(TransferableTypedData bytes) =>
      execute((w) => w.blurHashEncode(bytes));

  @override
  Future<Map<String, Object>> buildSkinMask({
    required List<Landmark2D> landmarks,
    required int faceContourCount,
    required List<int> regionCounts,
    required int segW,
    required int segH,
    required TransferableTypedData? segRaw,
    required int width,
    required int height,
  }) => execute(
    (w) => w.buildSkinMask(
      landmarks: landmarks,
      faceContourCount: faceContourCount,
      regionCounts: regionCounts,
      segW: segW,
      segH: segH,
      segRaw: segRaw,
      width: width,
      height: height,
    ),
  );

  @override
  Future<Uint8List> bytesTransform({
    required String op,
    required TransferableTypedData bytes,
    required Map<dynamic, dynamic> params,
  }) => execute((w) => w.bytesTransform(op: op, bytes: bytes, params: params));

  @override
  Future<Map<String, Object>> convertCameraImage({
    required int width,
    required int height,
    required List<TransferableTypedData> planesData,
    required List<int> planesBytesPerRow,
    required List<int?> planesBytesPerPixel,
    required int liveCameraMaxEdge,
    required bool isAndroid,
  }) => execute(
    (w) => w.convertCameraImage(
      width: width,
      height: height,
      planesData: planesData,
      planesBytesPerRow: planesBytesPerRow,
      planesBytesPerPixel: planesBytesPerPixel,
      liveCameraMaxEdge: liveCameraMaxEdge,
      isAndroid: isAndroid,
    ),
  );

  @override
  Future<Map<String, Object>> decodeAndPrepareEditBase({
    required TransferableTypedData bytes,
    required int liveEditMaxEdge,
  }) => execute(
    (w) => w.decodeAndPrepareEditBase(
      bytes: bytes,
      liveEditMaxEdge: liveEditMaxEdge,
    ),
  );

  @override
  Future<Map<String, Object>> decodeProgressive({
    required TransferableTypedData bytes,
    required int previewMaxEdge,
    required int liveEditMaxEdge,
  }) => execute(
    (w) => w.decodeProgressive(
      bytes: bytes,
      previewMaxEdge: previewMaxEdge,
      liveEditMaxEdge: liveEditMaxEdge,
    ),
  );

  @override
  Future<Map<String, Object>> decodeRgba(TransferableTypedData bytes) =>
      execute((w) => w.decodeRgba(bytes));

  @override
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
  }) => execute(
    (w) => w.drawCircle(
      width: width,
      height: height,
      pixels: pixels,
      centerX: centerX,
      centerY: centerY,
      radius: radius,
      colorR: colorR,
      colorG: colorG,
      colorB: colorB,
      colorA: colorA,
      previewMaxEdge: previewMaxEdge,
      previewQuality: previewQuality,
      encodePreviewJpeg: encodePreviewJpeg,
    ),
  );

  @override
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
  }) => execute(
    (w) => w.drawLine(
      width: width,
      height: height,
      pixels: pixels,
      x0: x0,
      y0: y0,
      x1: x1,
      y1: y1,
      colorR: colorR,
      colorG: colorG,
      colorB: colorB,
      colorA: colorA,
      previewMaxEdge: previewMaxEdge,
      previewQuality: previewQuality,
      encodePreviewJpeg: encodePreviewJpeg,
    ),
  );

  @override
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
  }) => execute(
    (w) => w.drawText(
      width: width,
      height: height,
      pixels: pixels,
      text: text,
      x: x,
      y: y,
      fontSize: fontSize,
      colorR: colorR,
      colorG: colorG,
      colorB: colorB,
      colorA: colorA,
      previewMaxEdge: previewMaxEdge,
      previewQuality: previewQuality,
      encodePreviewJpeg: encodePreviewJpeg,
    ),
  );

  @override
  Future<Uint8List> encodeFullRgba({
    required int width,
    required int height,
    required TransferableTypedData pixels,
    required int formatIndex,
    required int quality,
  }) => execute(
    (w) => w.encodeFullRgba(
      width: width,
      height: height,
      pixels: pixels,
      formatIndex: formatIndex,
      quality: quality,
    ),
  );

  @override
  Future<Uint8List> encodePreview({
    required int width,
    required int height,
    required TransferableTypedData pixels,
    required int previewMaxEdge,
    required int quality,
  }) => execute(
    (w) => w.encodePreview(
      width: width,
      height: height,
      pixels: pixels,
      previewMaxEdge: previewMaxEdge,
      quality: quality,
    ),
  );

  @override
  Future<Uint8List> filterBytes({
    required TransferableTypedData bytes,
    required String filterKind,
    required Map<dynamic, dynamic> filterParams,
    required int formatIndex,
    required int quality,
  }) => execute(
    (w) => w.filterBytes(
      bytes: bytes,
      filterKind: filterKind,
      filterParams: filterParams,
      formatIndex: formatIndex,
      quality: quality,
    ),
  );

  @override
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
  }) => execute(
    (w) => w.filterRgba(
      width: width,
      height: height,
      pixels: pixels,
      filterKind: filterKind,
      filterParams: filterParams,
      backendIndex: backendIndex,
      previewMaxEdge: previewMaxEdge,
      previewQuality: previewQuality,
      encodePreviewJpeg: encodePreviewJpeg,
    ),
  );

  @override
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
  }) => execute(
    (w) => w.overlayRgba(
      width: width,
      height: height,
      pixels: pixels,
      overlayBytes: overlayBytes,
      x: x,
      y: y,
      blendModeIndex: blendModeIndex,
      overlayWidth: overlayWidth,
      overlayHeight: overlayHeight,
      previewMaxEdge: previewMaxEdge,
      previewQuality: previewQuality,
      encodePreviewJpeg: encodePreviewJpeg,
    ),
  );

  @override
  Future<Map<String, Object>> prepareEditBaseFromRgba({
    required int width,
    required int height,
    required TransferableTypedData pixels,
    required int liveEditMaxEdge,
  }) => execute(
    (w) => w.prepareEditBaseFromRgba(
      width: width,
      height: height,
      pixels: pixels,
      liveEditMaxEdge: liveEditMaxEdge,
    ),
  );

  @override
  Future<Map<String, Object>> replayEditPipeline({
    required int width,
    required int height,
    required TransferableTypedData pixels,
    required List<EditOp> ops,
    required int backendIndex,
    required int previewMaxEdge,
    required int previewQuality,
    required bool encodePreviewJpeg,
  }) => execute(
    (w) => w.replayEditPipeline(
      width: width,
      height: height,
      pixels: pixels,
      ops: ops,
      backendIndex: backendIndex,
      previewMaxEdge: previewMaxEdge,
      previewQuality: previewQuality,
      encodePreviewJpeg: encodePreviewJpeg,
    ),
  );

  @override
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
  }) => execute(
    (w) => w.resizeRgba(
      width: width,
      height: height,
      pixels: pixels,
      targetW: targetW,
      targetH: targetH,
      algorithmIndex: algorithmIndex,
      backendIndex: backendIndex,
      previewMaxEdge: previewMaxEdge,
      previewQuality: previewQuality,
    ),
  );

  @override
  Future<TransferableTypedData> transcribeHeicToPng(
    TransferableTypedData bytes,
  ) => execute((w) => w.transcribeHeicToPng(bytes));
}

final class _$Deser extends MarshalingContext {
  _$Deser({super.contextAware});
  late final $0 = value<int>();
  late final $1 = value<TransferableTypedData>();
  late final $2 = value<Landmark2D>();
  late final $3 = list<Landmark2D>($2);
  late final $4 = list<int>($0);
  late final $5 = value<double>();
  late final $6 = Converter.allowNull($1);
  late final $7 = value<EditOp>();
  late final $8 = list<EditOp>($7);
  late final $9 = value<RasterLayerInput>();
  late final $10 = list<RasterLayerInput>($9);
  late final $11 = value<PaintStrokeInput>();
  late final $12 = list<PaintStrokeInput>($11);
  late final $13 = value<String>();
  late final $14 = value<Object>();
  late final $15 = nmap<Object, Object>(kcast: $14, vcast: $14);
  late final $16 = list<TransferableTypedData>($1);
  late final $17 = nlist<int>($0);
  late final $18 = value<bool>();
  late final $19 = map<String, Object>(kcast: $13, vcast: $14);
  late final $20 = value<Uint8List>();
}
