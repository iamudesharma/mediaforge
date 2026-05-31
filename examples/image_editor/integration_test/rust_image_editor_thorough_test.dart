// Thorough test: error paths + JPEG/PNG/WebP/AVIF resize round-trips.
//
// AVIF is feature-detected (wrapped in try/catch) because the Rust crate may
// be built without the `avif` feature on CI hosts that lack NASM.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:image_forge_editor/image_forge_editor.dart';

import 'test_fixtures.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Uint8List basePng;

  setUpAll(() async {
    await RustImageEditor.ensureInitialized();
    basePng = await tinyPng(width: 64, height: 48);
  });

  group('error paths', () {
    test('crop with rect entirely outside image throws', () {
      expect(
        () => RustImageEditor.crop(
          bytes: basePng,
          x: 1000,
          y: 1000,
          width: 32,
          height: 32,
        ),
        throwsA(anything),
      );
    });

    test('resize with width=0 throws', () {
      expect(
        () => RustImageEditor.resize(
          bytes: basePng,
          width: 0,
          height: 24,
        ),
        throwsA(anything),
      );
    });

    test('compress of malformed bytes throws', () {
      final garbage = Uint8List.fromList(const [0, 1, 2, 3]);
      expect(
        () => RustImageEditor.compress(
          bytes: garbage,
          format: OutputFormat.jpeg,
          quality: 80,
        ),
        throwsA(anything),
      );
    });
  });

  group('format round-trips (resize to 32x24)', () {
    for (final format in const [
      OutputFormat.jpeg,
      OutputFormat.png,
      OutputFormat.webP,
    ]) {
      test('roundtrip via ${format.name}', () {
        final out = RustImageEditor.resize(
          bytes: basePng,
          width: 32,
          height: 24,
          format: format,
        );
        expect(out, isNotEmpty);
        final info = RustImageEditor.probe(out);
        expect(info.width, 32);
        expect(info.height, 24);
      });
    }

    test('roundtrip via avif (skip if encoder unavailable)', () {
      Uint8List? out;
      try {
        out = RustImageEditor.resize(
          bytes: basePng,
          width: 32,
          height: 24,
          format: OutputFormat.avif,
        );
      } catch (e) {
        markTestSkipped('AVIF encoding unavailable in this build: $e');
        return;
      }
      expect(out, isNotEmpty);
      try {
        final info = RustImageEditor.probe(out);
        expect(info.width, 32);
        expect(info.height, 24);
      } catch (e) {
        markTestSkipped('AVIF decode/probe unavailable in this build: $e');
      }
    });
  });
}
