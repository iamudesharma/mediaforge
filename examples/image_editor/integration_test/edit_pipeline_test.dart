// `applyEditGraph` (non-destructive op replay) on CPU vs Auto backends, plus
// brightness sanity check (mean R-channel shifts upward).

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:image_forge_editor/image_forge_editor.dart';

import 'test_fixtures.dart';

double _meanRedChannel(RgbaImageBuffer buffer) {
  final pixels = buffer.pixels;
  if (pixels.isEmpty) return 0;
  var sum = 0;
  var count = 0;
  for (var i = 0; i < pixels.length; i += 4) {
    sum += pixels[i];
    count++;
  }
  return count == 0 ? 0 : sum / count;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late RgbaImageBuffer baseRgba;

  setUpAll(() async {
    await RustImageEditor.ensureInitialized();
    final basePng = await tinyPng(width: 64, height: 48);
    baseRgba = RustImageEditor.decodeToRgba(basePng);
  });

  group('applyEditGraph', () {
    const ops = [
      EditOp.filter(filter: ImageFilter.brightness(amount: 50)),
      EditOp.resize(
        width: 32,
        height: 24,
        algorithm: ResizeAlgorithm.lanczos3,
      ),
      EditOp.crop(x: 4, y: 4, width: 16, height: 16),
      EditOp.rotate(rotation: Rotation.rotate90),
    ];

    test('CPU backend: final dims are 16×16 after rotate90 (square stays)',
        () {
      final out = RustImageEditor.applyEditGraph(
        baseRgba,
        ops,
        backend: ProcessingBackend.cpu,
      );
      expect(out.width, 16);
      expect(out.height, 16);
    });

    test('Auto backend matches CPU dims', () {
      final out = RustImageEditor.applyEditGraph(
        baseRgba,
        ops,
        backend: ProcessingBackend.auto,
      );
      expect(out.width, 16);
      expect(out.height, 16);
    });

    test('brightness alone shifts mean R channel upward', () {
      final before = _meanRedChannel(baseRgba);
      final after = RustImageEditor.applyEditGraph(
        baseRgba,
        const [
          EditOp.filter(filter: ImageFilter.brightness(amount: 50)),
        ],
        backend: ProcessingBackend.cpu,
      );
      final afterMean = _meanRedChannel(after);
      expect(
        afterMean,
        greaterThan(before),
        reason:
            'brightness(+50) should raise mean red (before=$before after=$afterMean)',
      );
    });
  });
}
