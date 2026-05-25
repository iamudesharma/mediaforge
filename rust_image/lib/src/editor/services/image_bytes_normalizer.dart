import 'dart:typed_data';
import 'dart:ui' as ui;

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
    // Compatible brands list (bytes 16+); scan first few 4-cc codes.
    for (var i = 16; i + 4 <= bytes.length && i < 32; i += 4) {
      final b = String.fromCharCodes(bytes.sublist(i, i + 4));
      if (brands.contains(b)) return true;
    }
    return false;
  }

  /// Returns PNG/JPEG-ready bytes. HEIC/HEIF is transcoded when the platform supports it.
  static Future<Uint8List> prepareForEditor(Uint8List bytes) async {
    if (!isHeicOrHeif(bytes)) return bytes;
    return _transcodeHeicToPng(bytes);
  }

  static Future<Uint8List> _transcodeHeicToPng(Uint8List bytes) async {
    ui.Image? image;
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      image = frame.image;
      final bd = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bd == null) {
        throw StateError('Could not encode HEIC preview as PNG');
      }
      return bd.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes);
    } catch (e) {
      throw FormatException(
        'HEIC/HEIF could not be decoded on this device. '
        'On desktop, export the photo as JPEG from Photos, or use an iPhone/macOS build. ($e)',
      );
    } finally {
      image?.dispose();
    }
  }
}
