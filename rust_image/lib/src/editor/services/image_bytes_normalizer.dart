import 'dart:typed_data';

/// Prepares picked image bytes for the Rust decoder (JPEG/PNG/WebP, etc.).
abstract final class ImageBytesNormalizer {
  /// ISO BMFF brands used by iPhone / camera HEIC files.
  static bool isHeicOrHeif(Uint8List bytes) {
    if (bytes.length < 12) return false;
    final box = String.fromCharCodes(bytes.sublist(4, 8));
    if (box != 'ftyp') return false;
    final major = String.fromCharCodes(bytes.sublist(8, 12));
    const brands = [
      'heic',
      'heix',
      'hevc',
      'hevx',
      'heim',
      'heis',
      'hevm',
      'hevs',
      'mif1',
      'msf1',
    ];
    if (brands.contains(major)) return true;
    for (var i = 16; i + 4 <= bytes.length && i < 32; i += 4) {
      final b = String.fromCharCodes(bytes.sublist(i, i + 4));
      if (brands.contains(b)) return true;
    }
    return false;
  }

  /// Returns bytes unchanged. HEIC/HEIF is transcoded via [RustWorker.transcribeHeicToPng].
  static Future<Uint8List> prepareForEditor(Uint8List bytes) async => bytes;
}
