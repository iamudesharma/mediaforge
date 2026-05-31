import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Displays raw RGBA8888 preview bytes (not JPEG/PNG — do not use [Image.memory]).
class RgbaPreviewImage extends StatefulWidget {
  const RgbaPreviewImage({
    super.key,
    required this.pixels,
    required this.width,
    required this.height,
    this.fit = BoxFit.contain,
    this.filterQuality = FilterQuality.medium,
  });

  final Uint8List pixels;
  final int width;
  final int height;
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
    final changed = !identical(oldWidget.pixels, widget.pixels) ||
        oldWidget.width != widget.width ||
        oldWidget.height != widget.height;
    if (changed) {
      _scheduleDecode();
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  void _scheduleDecode() {
    final key = identityHashCode(widget.pixels);
    _cacheKey = key;
    _decode(key);
  }

  Future<void> _decode(Object key) async {
    final w = widget.width;
    final h = widget.height;
    if (w <= 0 || h <= 0 || widget.pixels.length < w * h * 4) {
      if (mounted) setState(() => _image = null);
      return;
    }
    try {
      final rowBytes = w * 4;
      final immutable = await ui.ImmutableBuffer.fromUint8List(widget.pixels);
      final descriptor = ui.ImageDescriptor.raw(
        immutable,
        width: w,
        height: h,
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
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
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
