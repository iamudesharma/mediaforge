import 'dart:typed_data';
import 'dart:ui' as ui;

/// Decoded [ui.Image] cache for user sticker bytes (probe + preview + rasterize).
abstract final class StickerImageCache {
  static final _cache = <int, ui.Image>{};
  static final _pending = <int, Future<ui.Image>>{};

  static int _key(Uint8List bytes) =>
      Object.hash(bytes.length, bytes.first, bytes.last);

  static Future<ui.Image> imageFor(Uint8List bytes) {
    final key = _key(bytes);
    final hit = _cache[key];
    if (hit != null) return Future.value(hit);
    return _pending.putIfAbsent(key, () async {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      _cache[key] = image;
      _pending.remove(key);
      return image;
    });
  }

  static Future<({double width, double height})> dimensionsFor(
    Uint8List bytes,
  ) async {
    final img = await imageFor(bytes);
    return (width: img.width.toDouble(), height: img.height.toDouble());
  }

  static void evict(Uint8List bytes) {
    final key = _key(bytes);
    _cache.remove(key)?.dispose();
    _pending.remove(key);
  }

  static void clear() {
    for (final img in _cache.values) {
      img.dispose();
    }
    _cache.clear();
    _pending.clear();
  }
}
