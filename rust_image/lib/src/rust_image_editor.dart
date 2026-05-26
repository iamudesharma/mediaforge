import 'dart:io' show File, Platform;
import 'dart:typed_data';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:rust_image/src/rust/api/advanced.dart';
import 'package:rust_image/src/rust/api/image.dart';
import 'package:rust_image/src/rust/api/layers.dart';
import 'package:rust_image/src/rust/frb_generated.dart';

export 'package:rust_image/src/rust/api/advanced.dart';
export 'package:rust_image/src/rust/api/face.dart';
export 'package:rust_image/src/rust/api/image.dart';
export 'package:rust_image/src/rust/api/layers.dart';
export 'package:rust_image/src/rust/api/texture.dart';
export 'package:rust_image/src/rust/frb_generated.dart' show RustLib;

/// High-performance image editor powered by Rust.
///
/// Call [RustImageEditor.ensureInitialized] once before using any method.
class RustImageEditor {
  RustImageEditor._();

  static Future<void>? _initFuture;

  /// Safe to call multiple times (e.g. from `main` and [RustImageEditorWidget]).
  static Future<void> ensureInitialized() {
    return _initFuture ??= _initOnce();
  }

  static Future<void> _initOnce() async {
    try {
      final explicit = Platform.environment['RUST_IMAGE_DYLIB'];
      if (explicit != null && explicit.isNotEmpty) {
        final file = File(explicit);
        if (!file.existsSync()) {
          throw StateError('RUST_IMAGE_DYLIB not found: $explicit');
        }
        await RustLib.init(
          externalLibrary: ExternalLibrary.open(file.absolute.path),
        );
      } else if (Platform.isMacOS || Platform.isIOS) {
        // Cargokit static-links Rust into the plugin pod (rust_image.framework).
        await RustLib.init(
          externalLibrary: ExternalLibrary.process(iKnowHowToUseIt: true),
        );
      } else {
        await RustLib.init();
      }
    } on StateError catch (e) {
      // Already initialized in this isolate (e.g. main + widget both called init).
      if (!e.message.contains('twice')) rethrow;
    }
  }

  // --- Phase 1: encode path ---

  static Uint8List resize({
    required Uint8List bytes,
    required int width,
    required int height,
    ResizeAlgorithm algorithm = ResizeAlgorithm.lanczos3,
    OutputFormat format = OutputFormat.jpeg,
    int quality = 85,
    bool fixExif = true,
    ProcessingBackend backend = ProcessingBackend.auto,
  }) {
    return resizeImage(
      bytes: bytes,
      width: width,
      height: height,
      algorithm: algorithm,
      format: format,
      quality: quality,
      fixExif: fixExif,
      backend: backend,
    );
  }

  static Uint8List thumbnail({
    required Uint8List bytes,
    required int maxEdge,
    OutputFormat format = OutputFormat.jpeg,
    int quality = 80,
    ResizeAlgorithm algorithm = ResizeAlgorithm.lanczos3,
    bool fixExif = true,
    ProcessingBackend backend = ProcessingBackend.auto,
  }) {
    return createThumbnail(
      bytes: bytes,
      maxEdge: maxEdge,
      format: format,
      quality: quality,
      algorithm: algorithm,
      fixExif: fixExif,
      backend: backend,
    );
  }

  static Uint8List crop({
    required Uint8List bytes,
    required int x,
    required int y,
    required int width,
    required int height,
    OutputFormat format = OutputFormat.jpeg,
    int quality = 90,
    bool fixExif = true,
  }) {
    return cropImage(
      bytes: bytes,
      x: x,
      y: y,
      width: width,
      height: height,
      format: format,
      quality: quality,
      fixExif: fixExif,
    );
  }

  static Uint8List rotate({
    required Uint8List bytes,
    required Rotation rotation,
    OutputFormat format = OutputFormat.jpeg,
    int quality = 90,
    bool fixExif = false,
  }) {
    return rotateImage(
      bytes: bytes,
      rotation: rotation,
      format: format,
      quality: quality,
      fixExif: fixExif,
    );
  }

  static Uint8List fixExif({
    required Uint8List bytes,
    OutputFormat format = OutputFormat.jpeg,
    int quality = 90,
  }) {
    return fixExifOrientation(bytes: bytes, format: format, quality: quality);
  }

  static int? exifOrientation(Uint8List bytes) {
    return readExifOrientation(bytes: bytes);
  }

  static Uint8List compress({
    required Uint8List bytes,
    OutputFormat format = OutputFormat.jpeg,
    int quality = 85,
  }) {
    return compressImage(bytes: bytes, format: format, quality: quality);
  }

  static Uint8List filter({
    required Uint8List bytes,
    required ImageFilter filter,
    OutputFormat format = OutputFormat.jpeg,
    int quality = 90,
    bool fixExif = true,
  }) {
    return applyFilter(
      bytes: bytes,
      filter: filter,
      format: format,
      quality: quality,
      fixExif: fixExif,
    );
  }

  static Uint8List watermark({
    required Uint8List baseBytes,
    required Uint8List overlayBytes,
    required int x,
    required int y,
    OutputFormat format = OutputFormat.png,
    int quality = 90,
  }) {
    return addWatermark(
      baseBytes: baseBytes,
      overlayBytes: overlayBytes,
      x: x,
      y: y,
      format: format,
      quality: quality,
    );
  }

  static Uint8List text({
    required Uint8List bytes,
    required TextOverlay overlay,
    OutputFormat format = OutputFormat.png,
    int quality = 95,
    bool fixExif = true,
  }) {
    return drawTextOnImage(
      bytes: bytes,
      overlay: overlay,
      format: format,
      quality: quality,
      fixExif: fixExif,
    );
  }

  static Uint8List line({
    required Uint8List bytes,
    required DrawLine line,
    OutputFormat format = OutputFormat.png,
    int quality = 95,
    bool fixExif = true,
  }) {
    return drawLineOnImage(
      bytes: bytes,
      line: line,
      format: format,
      quality: quality,
      fixExif: fixExif,
    );
  }

  static Uint8List circle({
    required Uint8List bytes,
    required DrawCircle circle,
    OutputFormat format = OutputFormat.png,
    int quality = 95,
    bool fixExif = true,
  }) {
    return drawCircleOnImage(
      bytes: bytes,
      circle: circle,
      format: format,
      quality: quality,
      fixExif: fixExif,
    );
  }

  static List<Uint8List> batchResize({
    required List<BatchResizeItem> items,
    ResizeAlgorithm algorithm = ResizeAlgorithm.lanczos3,
    OutputFormat format = OutputFormat.jpeg,
    int quality = 85,
    ProcessingBackend backend = ProcessingBackend.auto,
  }) {
    return batchResizeImages(
      items: items,
      algorithm: algorithm,
      format: format,
      quality: quality,
      backend: backend,
    );
  }

  // --- Phase 2: BlurHash, AVIF, overlays, presets ---

  static String blurHashEncode(
    Uint8List bytes, {
    int componentsX = 4,
    int componentsY = 3,
  }) {
    return encodeBlurhash(
      bytes: bytes,
      componentsX: componentsX,
      componentsY: componentsY,
    );
  }

  static Uint8List blurHashDecode({
    required String hash,
    required int width,
    required int height,
    OutputFormat format = OutputFormat.jpeg,
    int quality = 85,
  }) {
    return decodeBlurhash(
      hash: hash,
      width: width,
      height: height,
      format: format,
      quality: quality,
    );
  }

  /// Composite [overlayBytes] onto [baseBytes] with blend mode (Phase 2).
  static Uint8List overlay({
    required Uint8List baseBytes,
    required Uint8List overlayBytes,
    required int x,
    required int y,
    BlendMode blendMode = BlendMode.normal,
    OutputFormat format = OutputFormat.png,
    int quality = 90,
  }) {
    return overlayImage(
      baseBytes: baseBytes,
      overlayBytes: overlayBytes,
      x: x,
      y: y,
      blendMode: blendMode,
      format: format,
      quality: quality,
    );
  }

  // --- Phase 3: RGBA pipeline, progressive decode, pooling ---

  /// Metal / Vulkan / DX12 compute via wgpu (when the `gpu` feature is enabled).
  static GpuComputeInfo gpuInfo() => gpuComputeInfo();

  static bool get isGpuAvailable => isGpuComputeAvailable();

  static ImageInfo probe(Uint8List bytes) => probeImage(bytes: bytes);

  /// Decode once into RGBA for chained edits without re-decoding JPEG/PNG.
  static RgbaImageBuffer decodeToRgba(
    Uint8List bytes, {
    bool fixExif = true,
    int? maxEdge,
  }) {
    return decodeToRgbaBuffer(bytes: bytes, fixExif: fixExif, maxEdge: maxEdge);
  }

  static Uint8List encodeRgba(
    RgbaImageBuffer buffer, {
    OutputFormat format = OutputFormat.jpeg,
    int quality = 85,
  }) {
    return encodeRgbaBuffer(buffer: buffer, format: format, quality: quality);
  }

  static RgbaImageBuffer resizeRgba(
    RgbaImageBuffer buffer, {
    required int width,
    required int height,
    ResizeAlgorithm algorithm = ResizeAlgorithm.lanczos3,
    ProcessingBackend backend = ProcessingBackend.auto,
  }) {
    return resizeRgbaBuffer(
      buffer: buffer,
      width: width,
      height: height,
      algorithm: algorithm,
      backend: backend,
    );
  }

  static RgbaImageBuffer cropRgba(
    RgbaImageBuffer buffer, {
    required int x,
    required int y,
    required int width,
    required int height,
  }) {
    return cropRgbaBuffer(
      buffer: buffer,
      x: x,
      y: y,
      width: width,
      height: height,
    );
  }

  static RgbaImageBuffer filterRgba(
    RgbaImageBuffer buffer,
    ImageFilter filter, {
    ProcessingBackend backend = ProcessingBackend.auto,
  }) {
    return filterRgbaBuffer(
      buffer: buffer,
      filter: filter,
      backend: backend,
    );
  }

  /// Replay a non-destructive op list (Sprint 3 export / preview).
  static RgbaImageBuffer applyEditGraph(
    RgbaImageBuffer buffer,
    List<EditOp> ops, {
    ProcessingBackend backend = ProcessingBackend.auto,
  }) {
    return applyEditPipeline(buffer: buffer, ops: ops, backend: backend);
  }

  static RgbaImageBuffer fitMaxEdgeRgba(
    RgbaImageBuffer buffer, {
    required int maxEdge,
    PreviewQuality previewQuality = PreviewQuality.fast,
  }) =>
      fitMaxEdgeRgbaBuffer(
        buffer: buffer,
        maxEdge: maxEdge,
        previewQuality: previewQuality,
      );

  /// `gpu_adjust` or `cpu_photon` — for status / metrics (Phase 0).
  static String filterExecutionPath(
    ImageFilter filter,
    ProcessingBackend backend,
  ) =>
      filterExecutionPathName(filter: filter, backend: backend);

  static RgbaImageBuffer overlayRgba(
    RgbaImageBuffer base,
    Uint8List overlayBytes, {
    required int x,
    required int y,
    BlendMode blendMode = BlendMode.normal,
    int overlayWidth = 0,
    int overlayHeight = 0,
  }) {
    return overlayOnRgbaBuffer(
      base: base,
      overlayBytes: overlayBytes,
      x: x,
      y: y,
      blendMode: blendMode,
      overlayWidth: overlayWidth,
      overlayHeight: overlayHeight,
    );
  }

  /// Low-res JPEG preview + full RGBA buffer for progressive UI (Phase 3).
  static ProgressiveDecodeResult decodeProgressive(
    Uint8List bytes, {
    int previewMaxEdge = 128,
    bool fixExif = true,
  }) {
    return decodeProgressiveImage(
      bytes: bytes,
      previewMaxEdge: previewMaxEdge,
      fixExif: fixExif,
    );
  }

  static void releaseBuffer(Uint8List buffer) => bufferPoolRelease(buf: buffer);

  static Uint8List acquireBuffer({int minCapacity = 0}) {
    return bufferPoolAcquire(minCapacity: minCapacity);
  }

  static (int count, int bytes) poolStats() {
    final stats = bufferPoolStats();
    return (stats.$1.toInt(), stats.$2.toInt());
  }

  static String backendName(ProcessingBackend backend) {
    return processingBackendName(backend: backend);
  }

  // --- RGBA draw (fast interactive path) ---

  static RgbaImageBuffer drawLineRgba(
    RgbaImageBuffer buffer, {
    required DrawLine line,
  }) =>
      drawLineRgbaBuffer(buffer: buffer, line: line);

  static RgbaImageBuffer drawCircleRgba(
    RgbaImageBuffer buffer, {
    required DrawCircle circle,
  }) =>
      drawCircleRgbaBuffer(buffer: buffer, circle: circle);

  static RgbaImageBuffer drawTextRgba(
    RgbaImageBuffer buffer, {
    required TextOverlay overlay,
  }) =>
      drawTextRgbaBuffer(buffer: buffer, overlay: overlay);

  static Uint8List encodeRgbaPreview(
    RgbaImageBuffer buffer, {
    int maxEdge = 1600,
    int quality = 82,
    PreviewQuality previewQuality = PreviewQuality.fast,
  }) =>
      encodeRgbaPreviewBuffer(
        buffer: buffer,
        maxEdge: maxEdge,
        quality: quality,
        previewQuality: previewQuality,
      );

  /// Bake raster layers + paint strokes onto RGBA (Sprint 6/7).
  static RgbaImageBuffer bakeLayers({
    required RgbaImageBuffer buffer,
    required List<RasterLayerInput> rasterLayers,
    required List<PaintStrokeInput> paintStrokes,
  }) =>
      bakeLayersOnRgba(
        buffer: buffer,
        rasterLayers: rasterLayers,
        paintStrokes: paintStrokes,
      );
}
