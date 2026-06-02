import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pixel_surface/pixel_surface.dart';

void main() => runApp(const GpuTextureDemoApp());

/// Animated gradient in [GpuTextureView] — no image_forge.
///
/// Exercises the zero-swap `updateTextureBgra` path (1.1.0+): the bytes
/// produced by [_buildGradientBgra] are already in the native order of
/// the Apple `CVPixelBuffer` backing the Flutter texture, so the plugin
/// performs a single `memcpy` per frame and skips `vImage` entirely.
class GpuTextureDemoApp extends StatefulWidget {
  const GpuTextureDemoApp({super.key});

  @override
  State<GpuTextureDemoApp> createState() => _GpuTextureDemoAppState();
}

class _GpuTextureDemoAppState extends State<GpuTextureDemoApp> {
  static const _handle = 42;
  static const _w = 480;
  static const _h = 320;

  int? _textureId;
  Timer? _timer;
  double _phase = 0;

  @override
  void initState() {
    super.initState();
    if (!gpuTextureSupported()) return;
    unawaited(_initTexture());
  }

  Future<void> _initTexture() async {
    final id = await GpuTextureRegistry.createTexture(
      handle: _handle,
      width: _w,
      height: _h,
    );
    if (!mounted || id == null) return;
    setState(() => _textureId = id);
    _timer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      _phase += 0.04;
      unawaited(_pushFrame());
    });
  }

  Future<void> _pushFrame() async {
    final pixels = _buildGradientBgra(_w, _h, _phase);
    await GpuTextureRegistry.updateTextureBgra(handle: _handle, pixels: pixels);
  }

  /// Pixels emitted directly in BGRA8888 byte order — the natural order of
  /// `CVPixelBuffer` on Apple and of the Android `RGBA_8888` `Bitmap`
  /// memory layout (after the platform plugin's 32-bit word swap).
  Uint8List _buildGradientBgra(int w, int h, double phase) {
    final out = Uint8List(w * h * 4);
    var i = 0;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final t = (x / w + y / h) * 0.5 + phase;
        final r = (128 + 127 * math.sin(t)).round().clamp(0, 255);
        final g = (64 + 64 * math.sin(t * 1.3)).round().clamp(0, 255);
        final b = (200 + 55 * math.cos(t * 0.7)).round().clamp(0, 255);
        out[i++] = b;
        out[i++] = g;
        out[i++] = r;
        out[i++] = 255;
      }
    }
    return out;
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(GpuTextureRegistry.disposeTexture(_handle));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('pixel_surface demo')),
        body: Center(
          child: gpuTextureSupported() && _textureId != null
              ? GpuTextureView(
                  textureId: _textureId!,
                  width: _w,
                  height: _h,
                )
              : Text(
                  gpuTextureSupported()
                      ? 'Initializing texture…'
                      : 'GPU texture not supported on this platform.',
                  textAlign: TextAlign.center,
                ),
        ),
      ),
    );
  }
}
