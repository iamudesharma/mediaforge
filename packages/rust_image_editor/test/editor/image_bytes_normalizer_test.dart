import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rust_image_editor/src/editor/services/image_bytes_normalizer.dart';

void main() {
  test('isHeicOrHeif detects ftyp heic brand', () {
    final bytes = Uint8List.fromList([
      0, 0, 0, 24, // size
      0x66, 0x74, 0x79, 0x70, // ftyp
      0x68, 0x65, 0x69, 0x63, // heic
      0, 0, 0, 0,
      0x6d, 0x69, 0x66, 0x31,
      0x68, 0x65, 0x69, 0x63,
    ]);
    expect(ImageBytesNormalizer.isHeicOrHeif(bytes), isTrue);
  });

  test('isHeicOrHeif returns false for JPEG magic', () {
    final bytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0]);
    expect(ImageBytesNormalizer.isHeicOrHeif(bytes), isFalse);
  });
}
