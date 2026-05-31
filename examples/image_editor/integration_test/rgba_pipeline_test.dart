// End-to-end RGBA pipeline: decode → crop → resize → filter → draw →
// overlay → fit → encode (+ encodeRgbaPreview / decodeProgressive / pool).

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:image_forge_editor/image_forge_editor.dart';

import 'test_fixtures.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Uint8List basePng;
  late Uint8List overlayPng;

  setUpAll(() async {
    await RustImageEditor.ensureInitialized();
    basePng = await tinyPng(width: 64, height: 48);
    overlayPng = await tinyOverlayPng(size: 8);
  });

  group('rgba pipeline', () {
    test('decodeToRgba produces width*height*4 pixels', () {
      final rgba = RustImageEditor.decodeToRgba(basePng);
      expect(rgba.width, 64);
      expect(rgba.height, 48);
      expect(rgba.pixels.length, 64 * 48 * 4);
    });

    test('full chain: crop → resize → filter → draw → overlay → fit → encode',
        () {
      RgbaImageBuffer rgba = RustImageEditor.decodeToRgba(basePng);

      rgba = RustImageEditor.cropRgba(
        rgba,
        x: 0,
        y: 0,
        width: 48,
        height: 32,
      );
      expect(rgba.width, 48);
      expect(rgba.height, 32);

      rgba = RustImageEditor.resizeRgba(
        rgba,
        width: 40,
        height: 28,
        algorithm: ResizeAlgorithm.lanczos3,
        backend: ProcessingBackend.cpu,
      );
      expect(rgba.width, 40);
      expect(rgba.height, 28);

      rgba = RustImageEditor.filterRgba(
        rgba,
        const ImageFilter.brightness(amount: 30),
        backend: ProcessingBackend.cpu,
      );
      expect(rgba.width, 40);
      expect(rgba.height, 28);

      rgba = RustImageEditor.drawLineRgba(
        rgba,
        line: const DrawLine(
          x0: 0,
          y0: 0,
          x1: 30,
          y1: 20,
          colorR: 255,
          colorG: 255,
          colorB: 255,
          colorA: 255,
        ),
      );

      rgba = RustImageEditor.drawCircleRgba(
        rgba,
        circle: const DrawCircle(
          centerX: 20,
          centerY: 14,
          radius: 4,
          colorR: 0,
          colorG: 0,
          colorB: 255,
          colorA: 255,
        ),
      );

      rgba = RustImageEditor.drawTextRgba(
        rgba,
        overlay: const TextOverlay(
          text: 'X',
          x: 2,
          y: 12,
          fontSize: 10.0,
          colorR: 255,
          colorG: 255,
          colorB: 0,
          colorA: 255,
        ),
      );

      rgba = RustImageEditor.overlayRgba(
        rgba,
        overlayPng,
        x: 0,
        y: 0,
      );

      rgba = RustImageEditor.fitMaxEdgeRgba(rgba, maxEdge: 32);
      final maxEdge = rgba.width > rgba.height ? rgba.width : rgba.height;
      expect(maxEdge, lessThanOrEqualTo(32));

      final encoded = RustImageEditor.encodeRgba(
        rgba,
        format: OutputFormat.jpeg,
        quality: 80,
      );
      expect(encoded, isNotEmpty);
      final info = RustImageEditor.probe(encoded);
      expect(info.width, rgba.width);
      expect(info.height, rgba.height);
    });

    test('encodeRgbaPreview supports both PreviewQuality variants', () {
      final rgba = RustImageEditor.decodeToRgba(basePng);
      for (final quality in PreviewQuality.values) {
        final out = RustImageEditor.encodeRgbaPreview(
          rgba,
          maxEdge: 32,
          previewQuality: quality,
        );
        expect(out, isNotEmpty, reason: 'preview quality=$quality');
        final info = RustImageEditor.probe(out);
        final maxEdge = info.width > info.height ? info.width : info.height;
        expect(maxEdge, lessThanOrEqualTo(32));
      }
    });

    test('decodeProgressive preview ≤ previewMaxEdge', () {
      final result = RustImageEditor.decodeProgressive(
        basePng,
        previewMaxEdge: 24,
      );
      final maxEdge = result.previewRgba.width > result.previewRgba.height
          ? result.previewRgba.width
          : result.previewRgba.height;
      expect(maxEdge, lessThanOrEqualTo(24));
      expect(result.buffer.width, 64);
      expect(result.buffer.height, 48);
    });

    test('buffer pool acquire / release leaves counts non-negative', () {
      final (c0, b0) = RustImageEditor.poolStats();
      expect(c0, greaterThanOrEqualTo(0));
      expect(b0, greaterThanOrEqualTo(0));

      for (var i = 0; i < 3; i++) {
        final buf = RustImageEditor.acquireBuffer(minCapacity: 1024);
        expect(buf, isA<Uint8List>());
        RustImageEditor.releaseBuffer(buf);
      }

      final (c1, b1) = RustImageEditor.poolStats();
      expect(c1, greaterThanOrEqualTo(0));
      expect(b1, greaterThanOrEqualTo(0));
      expect(c1, lessThan(1 << 16));
    });
  });
}
