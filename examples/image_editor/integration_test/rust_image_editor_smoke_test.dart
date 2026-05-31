// Smoke test: a single happy-path call per public static on
// [RustImageEditor]. Each call must return non-empty bytes / a sane buffer,
// and (where applicable) `probe(out)` must report sensible dimensions.
//
// See `image_forge_editor_thorough_test.dart` for error paths and format

import 'package:image_forge_editor/image_forge_editor.dart';

import 'test_fixtures.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Uint8List basePng;
  late Uint8List baseJpeg;
  late Uint8List overlayPng;
  late RgbaImageBuffer baseRgba;

  setUpAll(() async {
    await RustImageEditor.ensureInitialized();
    basePng = await tinyPng(width: 64, height: 48);
    baseJpeg = await tinyJpeg(width: 64, height: 48);
    overlayPng = await tinyOverlayPng(size: 16);
    baseRgba = RustImageEditor.decodeToRgba(basePng);
  });

  void expectProbe(Uint8List bytes, {int? width, int? height}) {
    expect(bytes, isNotEmpty);
    final info = RustImageEditor.probe(bytes);
    expect(info.width, greaterThan(0));
    expect(info.height, greaterThan(0));
    if (width != null) expect(info.width, width);
    if (height != null) expect(info.height, height);
  }

  group('smoke', () {
    test('ensureInitialized is idempotent', () async {
      await RustImageEditor.ensureInitialized();
      await RustImageEditor.ensureInitialized();
    });

    test('resize', () {
      final out = RustImageEditor.resize(
        bytes: basePng,
        width: 32,
        height: 24,
      );
      expectProbe(out, width: 32, height: 24);
    });

    test('thumbnail', () {
      final out = RustImageEditor.thumbnail(bytes: basePng, maxEdge: 24);
      expect(out, isNotEmpty);
      final info = RustImageEditor.probe(out);
      expect(info.width <= 24 && info.height <= 24, isTrue);
      expect(info.width == 24 || info.height == 24, isTrue);
    });

    test('crop', () {
      final out = RustImageEditor.crop(
        bytes: basePng,
        x: 0,
        y: 0,
        width: 16,
        height: 16,
      );
      expectProbe(out, width: 16, height: 16);
    });

    test('rotate', () {
      final out = RustImageEditor.rotate(
        bytes: basePng,
        rotation: Rotation.rotate90,
      );
      expectProbe(out, width: 48, height: 64);
    });

    test('fixExif', () {
      final out = RustImageEditor.fixExif(bytes: baseJpeg);
      expectProbe(out);
    });

    test('exifOrientation returns null for non-EXIF PNG', () {
      expect(RustImageEditor.exifOrientation(basePng), isNull);
    });

    test('compress', () {
      final out = RustImageEditor.compress(
        bytes: basePng,
        format: OutputFormat.jpeg,
        quality: 80,
      );
      expectProbe(out, width: 64, height: 48);
    });

    test('filter (brightness)', () {
      final out = RustImageEditor.filter(
        bytes: basePng,
        filter: const ImageFilter.brightness(amount: 20),
      );
      expectProbe(out, width: 64, height: 48);
    });

    test('watermark', () {
      final out = RustImageEditor.watermark(
        baseBytes: basePng,
        overlayBytes: overlayPng,
        x: 4,
        y: 4,
      );
      expectProbe(out, width: 64, height: 48);
    });

    test('text', () {
      final out = RustImageEditor.text(
        bytes: basePng,
        overlay: const TextOverlay(
          text: 'OK',
          x: 4,
          y: 12,
          fontSize: 12.0,
          colorR: 255,
          colorG: 255,
          colorB: 255,
          colorA: 255,
        ),
      );
      expectProbe(out, width: 64, height: 48);
    });

    test('line', () {
      final out = RustImageEditor.line(
        bytes: basePng,
        line: const DrawLine(
          x0: 0,
          y0: 0,
          x1: 30,
          y1: 20,
          colorR: 255,
          colorG: 0,
          colorB: 0,
          colorA: 255,
        ),
      );
      expectProbe(out, width: 64, height: 48);
    });

    test('circle', () {
      final out = RustImageEditor.circle(
        bytes: basePng,
        circle: const DrawCircle(
          centerX: 32,
          centerY: 24,
          radius: 8,
          colorR: 0,
          colorG: 255,
          colorB: 0,
          colorA: 255,
        ),
      );
      expectProbe(out, width: 64, height: 48);
    });

    test('batchResize', () {
      final outs = RustImageEditor.batchResize(
        items: [
          BatchResizeItem(bytes: basePng, width: 32, height: 24),
          BatchResizeItem(bytes: basePng, width: 16, height: 12),
        ],
      );
      expect(outs, hasLength(2));
      expectProbe(outs[0], width: 32, height: 24);
      expectProbe(outs[1], width: 16, height: 12);
    });

    test('blurHashEncode returns ≥6 chars', () {
      expect(
        RustImageEditor.blurHashEncode(baseJpeg).length,
        greaterThanOrEqualTo(6),
      );
    });

    test('blurHashDecode round-trips to a valid PNG', () {
      final hash = RustImageEditor.blurHashEncode(baseJpeg);
      final out = RustImageEditor.blurHashDecode(
        hash: hash,
        width: 16,
        height: 16,
      );
      expectProbe(out, width: 16, height: 16);
    });

    test('overlay', () {
      final out = RustImageEditor.overlay(
        baseBytes: basePng,
        overlayBytes: overlayPng,
        x: 8,
        y: 8,
      );
      expectProbe(out, width: 64, height: 48);
    });

    test('gpuInfo returns a populated struct', () {
      final info = RustImageEditor.gpuInfo();
      expect(info.api, isNotEmpty);
      expect(info.device, isNotEmpty);
    });

    test('isGpuAvailable returns a bool', () {
      expect(RustImageEditor.isGpuAvailable, isA<bool>());
    });

    test('probe', () {
      final info = RustImageEditor.probe(basePng);
      expect(info.width, 64);
      expect(info.height, 48);
    });

    test('decodeToRgba', () {
      expect(baseRgba.width, 64);
      expect(baseRgba.height, 48);
      expect(baseRgba.pixels.length, 64 * 48 * 4);
    });

    test('encodeRgba', () {
      final out = RustImageEditor.encodeRgba(baseRgba);
      expectProbe(out, width: 64, height: 48);
    });

    test('resizeRgba', () {
      final out = RustImageEditor.resizeRgba(
        baseRgba,
        width: 32,
        height: 24,
      );
      expect(out.width, 32);
      expect(out.height, 24);
      expect(out.pixels.length, 32 * 24 * 4);
    });

    test('cropRgba', () {
      final out = RustImageEditor.cropRgba(
        baseRgba,
        x: 0,
        y: 0,
        width: 16,
        height: 16,
      );
      expect(out.width, 16);
      expect(out.height, 16);
    });

    test('filterRgba', () {
      final out = RustImageEditor.filterRgba(
        baseRgba,
        const ImageFilter.brightness(amount: 10),
      );
      expect(out.width, 64);
      expect(out.height, 48);
    });

    test('applyEditGraph', () {
      final out = RustImageEditor.applyEditGraph(
        baseRgba,
        const [
          EditOp.filter(filter: ImageFilter.brightness(amount: 10)),
          EditOp.resize(
            width: 32,
            height: 24,
            algorithm: ResizeAlgorithm.lanczos3,
          ),
        ],
        backend: ProcessingBackend.cpu,
      );
      expect(out.width, 32);
      expect(out.height, 24);
    });

    test('fitMaxEdgeRgba', () {
      final out = RustImageEditor.fitMaxEdgeRgba(baseRgba, maxEdge: 24);
      expect(out.width <= 24 && out.height <= 24, isTrue);
      expect(out.width == 24 || out.height == 24, isTrue);
    });

    test('filterExecutionPath returns a known label', () {
      final path = RustImageEditor.filterExecutionPath(
        const ImageFilter.brightness(amount: 10),
        ProcessingBackend.cpu,
      );
      expect(path, isNotEmpty);
    });

    test('overlayRgba', () {
      final out = RustImageEditor.overlayRgba(
        baseRgba,
        overlayPng,
        x: 4,
        y: 4,
      );
      expect(out.width, 64);
      expect(out.height, 48);
    });

    test('decodeProgressive', () {
      final result = RustImageEditor.decodeProgressive(
        basePng,
        previewMaxEdge: 24,
      );
      expect(result.info.width, 64);
      expect(result.info.height, 48);
      expect(result.buffer.width, 64);
      expect(result.buffer.height, 48);
      final previewMax =
          result.previewRgba.width > result.previewRgba.height
              ? result.previewRgba.width
              : result.previewRgba.height;
      expect(previewMax, lessThanOrEqualTo(24));
    });

    test('acquireBuffer / releaseBuffer / poolStats', () {
      final before = RustImageEditor.poolStats();
      expect(before.$1, greaterThanOrEqualTo(0));
      expect(before.$2, greaterThanOrEqualTo(0));
      final buf = RustImageEditor.acquireBuffer(minCapacity: 1024);
      expect(buf, isA<Uint8List>());
      RustImageEditor.releaseBuffer(buf);
      final after = RustImageEditor.poolStats();
      expect(after.$1, greaterThanOrEqualTo(0));
      expect(after.$2, greaterThanOrEqualTo(0));
    });

    test('backendName', () {
      expect(
        RustImageEditor.backendName(ProcessingBackend.cpu),
        isNotEmpty,
      );
    });

    test('drawLineRgba', () {
      final out = RustImageEditor.drawLineRgba(
        baseRgba,
        line: const DrawLine(
          x0: 0,
          y0: 0,
          x1: 30,
          y1: 20,
          colorR: 255,
          colorG: 0,
          colorB: 0,
          colorA: 255,
        ),
      );
      expect(out.width, 64);
      expect(out.height, 48);
    });

    test('drawCircleRgba', () {
      final out = RustImageEditor.drawCircleRgba(
        baseRgba,
        circle: const DrawCircle(
          centerX: 16,
          centerY: 16,
          radius: 6,
          colorR: 0,
          colorG: 0,
          colorB: 255,
          colorA: 255,
        ),
      );
      expect(out.width, 64);
      expect(out.height, 48);
    });

    test('drawTextRgba', () {
      final out = RustImageEditor.drawTextRgba(
        baseRgba,
        overlay: const TextOverlay(
          text: 'X',
          x: 4,
          y: 12,
          fontSize: 12.0,
          colorR: 255,
          colorG: 255,
          colorB: 0,
          colorA: 255,
        ),
      );
      expect(out.width, 64);
      expect(out.height, 48);
    });

    test('encodeRgbaPreview', () {
      final out = RustImageEditor.encodeRgbaPreview(baseRgba, maxEdge: 32);
      expect(out, isNotEmpty);
      final info = RustImageEditor.probe(out);
      expect(info.width <= 32 && info.height <= 32, isTrue);
    });

    test('bakeLayers (empty layers passes through)', () {
      final out = RustImageEditor.bakeLayers(
        buffer: baseRgba,
        rasterLayers: const [],
        paintStrokes: const [],
      );
      expect(out.width, 64);
      expect(out.height, 48);
    });
  });
}
