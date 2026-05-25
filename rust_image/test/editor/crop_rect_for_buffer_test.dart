import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rust_image/src/editor/crop_controller.dart';
import 'package:rust_image/src/editor/editor_session.dart';
import 'package:rust_image/src/rust_image_editor.dart';

void main() {
  test('cropRectForBuffer scales preview-space rect to full buffer', () {
    final crop = CropController()..syncImageSize(1000, 1000);
    crop.setCropRect(100, 200, 400, 500);

    final buffer = RgbaImageBuffer(
      width: 2000,
      height: 2000,
      pixels: Uint8List(2000 * 2000 * 4),
    );

    final rect = EditorSession.cropRectForBuffer(crop: crop, buffer: buffer);
    expect(rect.x, 200);
    expect(rect.y, 400);
    expect(rect.width, 800);
    expect(rect.height, 1000);
  });
}
