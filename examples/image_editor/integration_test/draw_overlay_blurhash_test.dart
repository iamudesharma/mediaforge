// BlendMode matrix for `overlay` / `overlayRgba`, plus BlurHash encode/decode.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
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

  group('overlay (encoded) BlendMode matrix', () {
    for (final mode in BlendMode.values) {
      test('blendMode=${mode.name}', () {
        final out = RustImageEditor.overlay(
          baseBytes: basePng,
          overlayBytes: overlayPng,
          x: 0,
          y: 0,
          blendMode: mode,
        );
        expect(out, isNotEmpty);
        final info = RustImageEditor.probe(out);
        expect(info.width, 64);
        expect(info.height, 48);
      });
    }
  });

  group('overlayRgba BlendMode matrix', () {
    for (final mode in BlendMode.values) {
      test('blendMode=${mode.name}', () {
        final out = RustImageEditor.overlayRgba(
          baseRgba,
          overlayPng,
          x: 0,
          y: 0,
          blendMode: mode,
        );
        expect(out.width, 64);
        expect(out.height, 48);
        expect(out.pixels.length, 64 * 48 * 4);
      });
    }
  });

  group('BlurHash', () {
    test('encode returns a hash of length ≥ 6', () {
      expect(
        RustImageEditor.blurHashEncode(baseJpeg).length,
        greaterThanOrEqualTo(6),
      );
    });

    test('decode returns a non-empty 16×16 image', () {
      final hash = RustImageEditor.blurHashEncode(baseJpeg);
      final out = RustImageEditor.blurHashDecode(
        hash: hash,
        width: 16,
        height: 16,
      );
      expect(out, isNotEmpty);
      final info = RustImageEditor.probe(out);
      expect(info.width, 16);
      expect(info.height, 16);
    });
  });
}
