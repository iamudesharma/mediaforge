import 'dart:io' show File, Platform;
import 'dart:typed_data';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:rust_image_core/rust_image_core.dart';

import 'frb_loader.dart';

export 'package:rust_image_core/rust_image_core.dart';

/// High-performance image editor powered by Rust.
///
/// Call [RustImageEditor.ensureInitialized] once before using any method.
class RustImageEditor {
  RustImageEditor._();

  static Future<void>? _initFuture;

  /// Safe to call multiple times (e.g. from `main` and [RustImageEditorWidget]).
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
    try {
      final explicit = Platform.environment['RUST_IMAGE_DYLIB'];
      if (explicit != null && explicit.isNotEmpty) {
        final file = File(explicit);
        if (!file.existsSync()) {
          throw StateError('RUST_IMAGE_DYLIB not found: $explicit');
        }
        await _initRustLib(ExternalLibrary.open(file.absolute.path));
      } else if (Platform.isMacOS || Platform.isIOS) {
        // App: CargoKit static-links Rust into the plugin. Tests: fall back to dylib.
        try {
          await _initRustLib(
            ExternalLibrary.process(iKnowHowToUseIt: true),
          );
        } catch (processError, processSt) {
          final discovered = discoverRustImageCoreDylib();
          if (discovered == null) {
            Error.throwWithStackTrace(processError, processSt);
          }
          await _initRustLib(ExternalLibrary.open(discovered));
        }
      } else {
        final discovered = discoverRustImageCoreDylib();
        if (discovered != null) {
          await _initRustLib(ExternalLibrary.open(discovered));
        } else {
          await _initRustLib(null);
        }
      }
    } on StateError catch (e) {
      // Already initialized in this isolate (e.g. main + widget both called init).
      if (!e.message.contains('twice')) rethrow;
    } catch (e, st) {
      if (Platform.isIOS || Platform.isMacOS) {
        final msg = e.toString();
        if (msg.contains('frb_get_rust_content_hash') ||
            msg.contains('symbol not found') ||
            msg.contains('Failed to lookup symbol')) {
          Error.throwWithStackTrace(
            StateError(
              'Rust FFI failed to load on ${Platform.operatingSystem} (common on '
              'Release/Archive when Xcode strips Rust symbols). '
              'Clean rebuild: delete ios/Pods, ios/Podfile.lock, then '
              'flutter clean && flutter pub get && cd ios && pod install. '
              'In Xcode Runner target: Build Settings → Strip Style → '
              'Non-Global Symbols; Strip Linked Product → No. '
              'See rust_image/README.md § iOS Release / Rust FFI. '
              'Original: $msg',
            ),
            st,
          );
        }
      }
      rethrow;
    }
  }

  static Future<void> _initRustLib(ExternalLibrary? externalLibrary) async {
    if (externalLibrary != null) {
      await RustLib.init(externalLibrary: externalLibrary);
    } else {
      await RustLib.init();
    }
  }

  // --- Phase 1: encode path ---

  /// Resizes an image file bytes to the specified width and height.
  ///
  /// Choose an appropriate [ResizeAlgorithm] (default is `lanczos3`) and
  /// [OutputFormat] (default is `jpeg`). [fixExif] will rotate the image
  /// according to EXIF metadata before resizing, clearing the EXIF tag.
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

  /// Creates a thumbnail representation of the image bytes.
  ///
  /// Fits the image within a bounding box of size [maxEdge].
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

  /// Crops a rectangular area of an image.
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

  /// Rotates or flips the image.
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

  /// Fixes the EXIF orientation by physically rotating/flipping pixels and clearing the tag.
  static Uint8List fixExif({
    required Uint8List bytes,
    OutputFormat format = OutputFormat.jpeg,
    int quality = 90,
  }) {
    return fixExifOrientation(bytes: bytes, format: format, quality: quality);
  }

  /// Reads the raw EXIF orientation value from metadata (returns 1 to 8, or null if missing).
  static int? exifOrientation(Uint8List bytes) {
    return readExifOrientation(bytes: bytes);
  }

  /// Compresses the image bytes to the specified format and quality.
  static Uint8List compress({
    required Uint8List bytes,
    OutputFormat format = OutputFormat.jpeg,
    int quality = 85,
  }) {
    return compressImage(bytes: bytes, format: format, quality: quality);
  }

  /// Applies a specified filter preset or adjustment (brightness/blur etc.) to the image.
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

  /// Overlays a watermark image onto the base image at coordinates [x, y].
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

  /// Draws a text overlay directly on the image.
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

  /// Draws a vector line directly on the image.
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

  /// Draws a vector circle directly on the image.
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

  /// Performs concurrent resize on a list of images (parallelized on CPU).
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

  /// Encodes image bytes to a BlurHash representation.
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

  /// Decodes a BlurHash string back into compressed image bytes.
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

  /// Returns true if GPU acceleration is supported on the current device.
  static bool get isGpuAvailable => isGpuComputeAvailable();

  /// Probes image format and orientation metadata without decoding full pixel arrays.
  static ImageInfo probe(Uint8List bytes) => probeImage(bytes: bytes);

  /// Decode once into RGBA for chained edits without re-decoding JPEG/PNG.
  static RgbaImageBuffer decodeToRgba(
    Uint8List bytes, {
    bool fixExif = true,
    int? maxEdge,
  }) {
    return decodeToRgbaBuffer(bytes: bytes, fixExif: fixExif, maxEdge: maxEdge);
  }

  /// Encodes a raw RGBA buffer into compressed image bytes (such as JPEG/PNG).
  static Uint8List encodeRgba(
    RgbaImageBuffer buffer, {
    OutputFormat format = OutputFormat.jpeg,
    int quality = 85,
  }) {
    return encodeRgbaBuffer(buffer: buffer, format: format, quality: quality);
  }

  /// Resizes a raw RGBA buffer (GPU-accelerated when backend is `.gpu` or `.auto`).
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

  /// Crops a rectangular area of an RGBA buffer.
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

  /// Applies a specified filter preset or adjustment (brightness/blur etc.) to an RGBA buffer.
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

  /// Downscales an RGBA buffer so its longest side fits within [maxEdge].
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

  /// Composites raw overlay pixels onto a base RGBA buffer at the specified position.
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

  /// Releases a buffer (such as a rented `Vec<u8>`) back to the buffer pool (Phase 3).
  static void releaseBuffer(Uint8List buffer) => bufferPoolRelease(buf: buffer);

  /// Rents or acquires a `Vec<u8>` from the pool with at least `minCapacity` to prevent allocations (Phase 3).
  static Uint8List acquireBuffer({int minCapacity = 0}) {
    return bufferPoolAcquire(minCapacity: minCapacity);
  }

  /// Returns the current statistics of the buffer pool `(count of buffers, total size in bytes)`.
  static (int count, int bytes) poolStats() {
    final stats = bufferPoolStats();
    return (stats.$1.toInt(), stats.$2.toInt());
  }

  /// Returns a string representation of the active processing backend.
  static String backendName(ProcessingBackend backend) {
    return processingBackendName(backend: backend);
  }

  // --- RGBA draw (fast interactive path) ---

  /// Draws a vector line onto an RGBA buffer.
  static RgbaImageBuffer drawLineRgba(
    RgbaImageBuffer buffer, {
    required DrawLine line,
  }) =>
      drawLineRgbaBuffer(buffer: buffer, line: line);

  /// Draws a vector circle onto an RGBA buffer.
  static RgbaImageBuffer drawCircleRgba(
    RgbaImageBuffer buffer, {
    required DrawCircle circle,
  }) =>
      drawCircleRgbaBuffer(buffer: buffer, circle: circle);

  /// Draws text onto an RGBA buffer.
  static RgbaImageBuffer drawTextRgba(
    RgbaImageBuffer buffer, {
    required TextOverlay overlay,
  }) =>
      drawTextRgbaBuffer(buffer: buffer, overlay: overlay);

  /// Encodes an RGBA buffer to preview JPEG bytes, optimized for performance over visual quality.
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
