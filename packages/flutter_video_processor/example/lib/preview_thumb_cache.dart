import 'dart:collection';
import 'dart:io';

/// Bounded in-memory paths for scrub preview thumbnails (avoids many [Uint8List]s).
class PreviewThumbCache {
  PreviewThumbCache({this.maxEntries = 3});

  final int maxEntries;
  final LinkedHashMap<String, String> _paths = LinkedHashMap();

  String _key(String input, int positionMs, int? width) {
    return '$input|$positionMs|${width ?? 0}';
  }

  String? get(String input, int positionMs, int? width) {
    final path = _paths[_key(input, positionMs, width)];
    if (path == null) return null;
    if (!File(path).existsSync()) {
      _paths.remove(_key(input, positionMs, width));
      return null;
    }
    return path;
  }

  void put(String input, int positionMs, int? width, String path) {
    final k = _key(input, positionMs, width);
    _paths.remove(k);
    _paths[k] = path;
    while (_paths.length > maxEntries) {
      _paths.remove(_paths.keys.first);
    }
  }

  void clear() => _paths.clear();
}
