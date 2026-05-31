import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_forge/video_forge.dart';

void main() {
  group('PlaybackFrame', () {
    group('rgba variant', () {
      test('construction', () {
        final rgbaFrame = PreviewFrameRgba(
          ptsMs: BigInt.from(1000),
          width: 1920,
          height: 1080,
          rgba: Uint8List(1920 * 1080 * 4),
        );
        final frame = PlaybackFrame.rgba(rgbaFrame);

        expect(frame, isA<PlaybackFrame_Rgba>());
        final rgba = frame as PlaybackFrame_Rgba;
        expect(rgba.field0.ptsMs, BigInt.from(1000));
        expect(rgba.field0.width, 1920);
      });

      test('equality', () {
        final samePixels = Uint8List(40000);
        final r1 = PreviewFrameRgba(
          ptsMs: BigInt.from(0), width: 100, height: 100,
          rgba: samePixels,
        );
        final r2 = PreviewFrameRgba(
          ptsMs: BigInt.from(0), width: 100, height: 100,
          rgba: samePixels,
        );
        final a = PlaybackFrame.rgba(r1);
        final b = PlaybackFrame.rgba(r2);

        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });
    });

    group('pixelBuffer variant', () {
      test('construction', () {
        final pbFrame = PreviewFramePixelBuffer(
          ptsMs: BigInt.from(500),
          width: 1280,
          height: 720,
          pixelBufferPtr: BigInt.from(0xDEAD_BEEF),
        );
        final frame = PlaybackFrame.pixelBuffer(pbFrame);

        expect(frame, isA<PlaybackFrame_PixelBuffer>());
        final pb = frame as PlaybackFrame_PixelBuffer;
        expect(pb.field0.pixelBufferPtr, BigInt.from(0xDEAD_BEEF));
      });

      test('equality', () {
        final p1 = PreviewFramePixelBuffer(
          ptsMs: BigInt.from(100), width: 640, height: 480,
          pixelBufferPtr: BigInt.from(0xABCD),
        );
        final p2 = PreviewFramePixelBuffer(
          ptsMs: BigInt.from(100), width: 640, height: 480,
          pixelBufferPtr: BigInt.from(0xABCD),
        );
        final a = PlaybackFrame.pixelBuffer(p1);
        final b = PlaybackFrame.pixelBuffer(p2);

        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });
    });

    test('different variants not equal', () {
      final rgba = PlaybackFrame.rgba(PreviewFrameRgba(
        ptsMs: BigInt.from(0), width: 10, height: 10,
        rgba: Uint8List(400),
      ));
      final pb = PlaybackFrame.pixelBuffer(PreviewFramePixelBuffer(
        ptsMs: BigInt.from(0), width: 10, height: 10,
        pixelBufferPtr: BigInt.from(0xFF),
      ));
      expect(rgba, isNot(equals(pb)));
    });

    test('when pattern matching', () {
      final frame = PlaybackFrame.rgba(PreviewFrameRgba(
        ptsMs: BigInt.from(0), width: 100, height: 100,
        rgba: Uint8List(40000),
      ));
      final result = frame.when(
        rgba: (_) => 'RGBA',
        pixelBuffer: (_) => 'PIXEL',
      );
      expect(result, 'RGBA');
    });

    test('map pattern matching', () {
      final frame = PlaybackFrame.pixelBuffer(PreviewFramePixelBuffer(
        ptsMs: BigInt.from(0), width: 100, height: 100,
        pixelBufferPtr: BigInt.zero,
      ));
      final result = frame.map(
        rgba: (_) => 'R',
        pixelBuffer: (_) => 'P',
      );
      expect(result, 'P');
    });

    test('maybeWhen with orElse', () {
      final frame = PlaybackFrame.pixelBuffer(PreviewFramePixelBuffer(
        ptsMs: BigInt.from(0), width: 1, height: 1,
        pixelBufferPtr: BigInt.zero,
      ));
      final result = frame.maybeWhen(
        pixelBuffer: (_) => 'pb',
        orElse: () => 'other',
      );
      expect(result, 'pb');
    });

    test('maybeMap with orElse', () {
      final frame = PlaybackFrame.rgba(PreviewFrameRgba(
        ptsMs: BigInt.from(0), width: 1, height: 1,
        rgba: Uint8List(4),
      ));
      final result = frame.maybeMap(
        rgba: (_) => 'r',
        orElse: () => 'o',
      );
      expect(result, 'r');
    });
  });
}
