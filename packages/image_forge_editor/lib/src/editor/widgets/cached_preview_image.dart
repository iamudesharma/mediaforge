import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Decodes JPEG/PNG bytes once and reuses [ui.Image] until bytes change (Phase 1b).
class CachedPreviewImage extends StatefulWidget {
  const CachedPreviewImage({
    super.key,
    required this.bytes,
    this.fit = BoxFit.contain,
    this.filterQuality = FilterQuality.medium,
  });

  final Uint8List bytes;
  final BoxFit fit;
  final FilterQuality filterQuality;

  @override
  State<CachedPreviewImage> createState() => _CachedPreviewImageState();
}

class _CachedPreviewImageState extends State<CachedPreviewImage> {
  ui.Image? _image;
  Object? _cacheKey;
  Uint8List? _pendingBytes;

  @override
  void initState() {
    super.initState();
    _scheduleDecode(widget.bytes);
  }

  @override
  void didUpdateWidget(CachedPreviewImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final key = _bytesKey(widget.bytes);
    if (key != _cacheKey) {
      _scheduleDecode(widget.bytes);
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  Object _bytesKey(Uint8List bytes) {
    final mid = bytes.length ~/ 2;
    return Object.hash(
      bytes.length,
      bytes.first,
      bytes.last,
      bytes[mid],
      identityHashCode(bytes),
    );
  }

  void _scheduleDecode(Uint8List bytes) {
    _pendingBytes = bytes;
    final key = _bytesKey(bytes);
    _cacheKey = key;
    _decode(bytes, key);
  }

  Future<void> _decode(Uint8List bytes, Object key) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      if (!mounted || _pendingBytes != bytes || _cacheKey != key) {
        frame.image.dispose();
        return;
      }
      final old = _image;
      setState(() => _image = frame.image);
      old?.dispose();
    } catch (_) {
      if (mounted) setState(() => _image = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null) {
      return const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)));
    }
    return RawImage(
      image: image,
      fit: widget.fit,
      filterQuality: widget.filterQuality,
    );
  }
}
