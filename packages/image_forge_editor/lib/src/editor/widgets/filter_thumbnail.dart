import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/lumina_tokens.dart';

/// LRU cache of decoded filter thumbnails, keyed by (filterId, sourceHash,
/// canvasW). The thumbnails are stored as [ui.Image] objects so the editor
/// strip can render them at native speed.
class FilterThumbnailCache {
  FilterThumbnailCache({this.maxEntries = 32});

  final int maxEntries;
  final LinkedHashMap<String, ui.Image> _cache = LinkedHashMap<String, ui.Image>();

  String _key(String filterId, String sourceHash, int canvasW) =>
      '$filterId|$sourceHash|$canvasW';

  ui.Image? get(String filterId, String sourceHash, int canvasW) {
    final k = _key(filterId, sourceHash, canvasW);
    final v = _cache.remove(k);
    if (v == null) return null;
    _cache[k] = v; // re-insert to mark as most-recently used
    return v;
  }

  void put(String filterId, String sourceHash, int canvasW, ui.Image image) {
    final k = _key(filterId, sourceHash, canvasW);
    if (_cache.containsKey(k)) {
      _cache.remove(k);
    }
    _cache[k] = image;
    while (_cache.length > maxEntries) {
      final oldestKey = _cache.keys.first;
      final oldest = _cache.remove(oldestKey);
      oldest?.dispose();
    }
  }

  Future<void> clear() async {
    for (final img in _cache.values) {
      img.dispose();
    }
    _cache.clear();
  }

  int get length => _cache.length;
}

/// Pending or completed thumbnail job.
class ThumbnailRequest {
  ThumbnailRequest({
    required this.filterId,
    required this.sourceHash,
    required this.canvasW,
    required this.completer,
  });

  final String filterId;
  final String sourceHash;
  final int canvasW;
  final Completer<ui.Image> completer;
}

/// Compute a stable hash of the source image bytes for cache keying. Uses
/// a 64-bit FNV-1a over a stride sample of the byte array — fast enough to
/// run on the UI thread for typical inputs.
String thumbnailSourceHash(Uint8List bytes) {
  const fnvOffset = 0xcbf29ce484222325;
  const fnvPrime = 0x100000001b3;
  var hash = fnvOffset;
  final step = bytes.length > 4096 ? (bytes.length ~/ 4096) : 1;
  for (var i = 0; i < bytes.length; i += step) {
    hash ^= bytes[i];
    hash = (hash * fnvPrime) & 0xFFFFFFFFFFFFFFFF;
  }
  return hash.toRadixString(16);
}

/// A small box that resolves a [ThumbnailRequest] into a filter thumbnail
/// widget. While the request is pending, shows a shimmer placeholder.
class FilterThumbnail extends StatefulWidget {
  const FilterThumbnail({
    super.key,
    required this.request,
    required this.cache,
    this.size = 80,
  });

  final ThumbnailRequest? request;
  final FilterThumbnailCache cache;
  final double size;

  @override
  State<FilterThumbnail> createState() => _FilterThumbnailState();
}

class _FilterThumbnailState extends State<FilterThumbnail> {
  ui.Image? _image;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant FilterThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.request != widget.request) {
      _resolve();
    }
  }

  void _resolve() {
    final r = widget.request;
    if (r == null) {
      setState(() => _image = null);
      return;
    }
    final cached = widget.cache.get(r.filterId, r.sourceHash, r.canvasW);
    if (cached != null) {
      setState(() => _image = cached);
      return;
    }
    setState(() => _image = null);
    r.completer.future.then((img) {
      if (!mounted) return;
      setState(() => _image = img);
    }).catchError((_) {
      // ignore — fallback placeholder will remain
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_image == null) {
      return Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              LuminaTokens.surfaceContainerHigh,
              LuminaTokens.surfaceContainer,
            ],
          ),
        ),
        child: const Center(
          child: SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: LuminaTokens.onSurfaceMuted,
            ),
          ),
        ),
      );
    }
    return RawImage(
      image: _image,
      fit: BoxFit.cover,
      width: widget.size,
      height: widget.size,
      filterQuality: FilterQuality.medium,
    );
  }
}
