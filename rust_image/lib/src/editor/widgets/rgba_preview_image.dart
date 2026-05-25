import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:rust_image/src/rust_image_editor.dart';

/// Sprint 4 — display RGBA pixels without JPEG encode/decode on the hot path.
class RgbaPreviewImage extends StatefulWidget {
  const RgbaPreviewImage({
    super.key,
    required this.buffer,
    this.fit = BoxFit.contain,
    this.filterQuality = FilterQuality.medium,
  });

  final RgbaImageBuffer buffer;
  final BoxFit fit;
  final FilterQuality filterQuality;

  @override
  State<RgbaPreviewImage> createState() => _RgbaPreviewImageState();
}

class _RgbaPreviewImageState extends State<RgbaPreviewImage> {
  ui.Image? _image;
  Object? _cacheKey;

  @override
  void initState() {
    super.initState();
    _scheduleDecode();
  }

  @override
  void didUpdateWidget(RgbaPreviewImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bufferChanged = !identical(oldWidget.buffer.pixels, widget.buffer.pixels) ||
        oldWidget.buffer.width != widget.buffer.width ||
        oldWidget.buffer.height != widget.buffer.height;
    if (bufferChanged) {
      _scheduleDecode();
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  void _scheduleDecode() {
    final buffer = widget.buffer;
    final key = identityHashCode(buffer.pixels);
    _cacheKey = key;
    _decode(buffer, key);
  }

  Future<void> _decode(RgbaImageBuffer buffer, Object key) async {
    try {
      final rowBytes = buffer.width * 4;
      final immutable = await ui.ImmutableBuffer.fromUint8List(buffer.pixels);
      final descriptor = ui.ImageDescriptor.raw(
        immutable,
        width: buffer.width,
        height: buffer.height,
        pixelFormat: ui.PixelFormat.rgba8888,
        rowBytes: rowBytes,
      );
      final codec = await descriptor.instantiateCodec();
      final frame = await codec.getNextFrame();
      if (!mounted || _cacheKey != key) {
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
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return RawImage(
      image: image,
      fit: widget.fit,
      filterQuality: widget.filterQuality,
    );
  }
}
