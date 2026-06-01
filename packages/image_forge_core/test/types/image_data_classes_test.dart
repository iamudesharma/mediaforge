import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_forge_core/image_forge_core.dart';

void main() {
  group('BatchResizeItem', () {
    test('construction and equality', () {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final a = BatchResizeItem(bytes: bytes, width: 100, height: 200);
      final b = BatchResizeItem(bytes: bytes, width: 100, height: 200);
      final c = BatchResizeItem(bytes: bytes, width: 300, height: 400);

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('field access', () {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final item = BatchResizeItem(bytes: bytes, width: 640, height: 480);
      expect(item.width, 640);
      expect(item.height, 480);
      expect(item.bytes, bytes);
    });
  });

  group('DrawCircle', () {
    test('construction and equality', () {
      final a = const DrawCircle(
        centerX: 10,
        centerY: 20,
        radius: 5,
        colorR: 255,
        colorG: 0,
        colorB: 0,
        colorA: 255,
      );
      final b = const DrawCircle(
        centerX: 10,
        centerY: 20,
        radius: 5,
        colorR: 255,
        colorG: 0,
        colorB: 0,
        colorA: 255,
      );
      final c = const DrawCircle(
        centerX: 99,
        centerY: 20,
        radius: 5,
        colorR: 255,
        colorG: 0,
        colorB: 0,
        colorA: 255,
      );

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('field access', () {
      const circle = DrawCircle(
        centerX: 100,
        centerY: 200,
        radius: 50,
        colorR: 128,
        colorG: 64,
        colorB: 32,
        colorA: 200,
      );
      expect(circle.centerX, 100);
      expect(circle.centerY, 200);
      expect(circle.radius, 50);
      expect(circle.colorR, 128);
      expect(circle.colorG, 64);
      expect(circle.colorB, 32);
      expect(circle.colorA, 200);
    });
  });

  group('DrawLine', () {
    test('construction and equality', () {
      final a = const DrawLine(
        x0: 0,
        y0: 0,
        x1: 100,
        y1: 100,
        colorR: 255,
        colorG: 255,
        colorB: 255,
        colorA: 255,
      );
      final b = const DrawLine(
        x0: 0,
        y0: 0,
        x1: 100,
        y1: 100,
        colorR: 255,
        colorG: 255,
        colorB: 255,
        colorA: 255,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('different lines not equal', () {
      final a = const DrawLine(
        x0: 0, y0: 0, x1: 10, y1: 10,
        colorR: 255, colorG: 0, colorB: 0, colorA: 255,
      );
      final b = const DrawLine(
        x0: 0, y0: 0, x1: 20, y1: 20,
        colorR: 255, colorG: 0, colorB: 0, colorA: 255,
      );
      expect(a, isNot(equals(b)));
    });
  });

  group('GpuComputeInfo', () {
    test('construction and equality', () {
      final a = const GpuComputeInfo(
        available: true,
        api: 'Metal',
        device: 'Apple M1',
      );
      final b = const GpuComputeInfo(
        available: true,
        api: 'Metal',
        device: 'Apple M1',
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('field access', () {
      const info = GpuComputeInfo(
        available: false,
        api: 'None',
        device: 'CPU',
      );
      expect(info.available, isFalse);
      expect(info.api, 'None');
      expect(info.device, 'CPU');
    });
  });

  group('ImageInfo', () {
    test('construction with all fields', () {
      const info = ImageInfo(
        width: 1920,
        height: 1080,
        format: 'jpeg',
        exifOrientation: 1,
      );
      expect(info.width, 1920);
      expect(info.height, 1080);
      expect(info.format, 'jpeg');
      expect(info.exifOrientation, 1);
    });

    test('nullable fields can be null', () {
      const info = ImageInfo(width: 100, height: 100);
      expect(info.format, isNull);
      expect(info.exifOrientation, isNull);
    });

    test('equality', () {
      const a = ImageInfo(width: 10, height: 20, format: 'png', exifOrientation: 6);
      const b = ImageInfo(width: 10, height: 20, format: 'png', exifOrientation: 6);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });

  group('ProgressiveDecodeResult', () {
    test('construction and equality', () {
      final info = const ImageInfo(width: 100, height: 100);
      final preview = RgbaImageBuffer(
        width: 10,
        height: 10,
        pixels: Uint8List(400),
      );
      final buffer = RgbaImageBuffer(
        width: 100,
        height: 100,
        pixels: Uint8List(40000),
      );

      final a = ProgressiveDecodeResult(info: info, previewRgba: preview, buffer: buffer);
      final b = ProgressiveDecodeResult(info: info, previewRgba: preview, buffer: buffer);

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });

  group('RgbaImageBuffer', () {
    test('construction and equality', () {
      final pixels = Uint8List.fromList(List.filled(400, 128));
      final a = RgbaImageBuffer(width: 10, height: 10, pixels: pixels);
      final b = RgbaImageBuffer(width: 10, height: 10, pixels: pixels);
      final c = RgbaImageBuffer(width: 20, height: 20, pixels: pixels);

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
      expect(a.hashCode, equals(b.hashCode));
      expect(a.width, 10);
      expect(a.height, 10);
    });

    test('construction with empty pixels', () {
      final buf = RgbaImageBuffer(width: 1, height: 1, pixels: Uint8List(0));
      expect(buf, isA<RgbaImageBuffer>());
    });
  });

  group('SwipeLookExtrasDto', () {
    test('construction and equality', () {
      const a = SwipeLookExtrasDto(
        glow: 0.5,
        grain: 0.3,
        sharpen: 0.2,
        skinPreserveDetail: 0.8,
        halation: 0.1,
        rgbSplit: 0.0,
      );
      const b = SwipeLookExtrasDto(
        glow: 0.5,
        grain: 0.3,
        sharpen: 0.2,
        skinPreserveDetail: 0.8,
        halation: 0.1,
        rgbSplit: 0.0,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a.glow, 0.5);
      expect(a.grain, 0.3);
    });

    test('different values not equal', () {
      const a = SwipeLookExtrasDto(
        glow: 0.5, grain: 0.0, sharpen: 0.0,
        skinPreserveDetail: 0.0, halation: 0.0, rgbSplit: 0.0,
      );
      const b = SwipeLookExtrasDto(
        glow: 1.0, grain: 0.0, sharpen: 0.0,
        skinPreserveDetail: 0.0, halation: 0.0, rgbSplit: 0.0,
      );
      expect(a, isNot(equals(b)));
    });
  });

  group('TextOverlay', () {
    test('construction and equality', () {
      const a = TextOverlay(
        text: 'Hello',
        x: 10,
        y: 20,
        fontSize: 24,
        colorR: 255,
        colorG: 255,
        colorB: 255,
        colorA: 255,
      );
      const b = TextOverlay(
        text: 'Hello',
        x: 10,
        y: 20,
        fontSize: 24,
        colorR: 255,
        colorG: 255,
        colorB: 255,
        colorA: 255,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('field access', () {
      const overlay = TextOverlay(
        text: 'Test',
        x: 50,
        y: 100,
        fontSize: 32,
        colorR: 0,
        colorG: 0,
        colorB: 0,
        colorA: 128,
      );
      expect(overlay.text, 'Test');
      expect(overlay.x, 50);
      expect(overlay.y, 100);
      expect(overlay.fontSize, 32);
    });
  });
}
