import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:rust_image_core/rust_image_core.dart';

import 'rust_core_init.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CoreFilterDemoApp());
}

/// Synthetic RGBA → brightness filter → JPEG export (no editor / no Texture).
class CoreFilterDemoApp extends StatefulWidget {
  const CoreFilterDemoApp({super.key});

  @override
  State<CoreFilterDemoApp> createState() => _CoreFilterDemoAppState();
}

class _CoreFilterDemoAppState extends State<CoreFilterDemoApp> {
  String _status = 'Tap Run pipeline';
  Uint8List? _jpegBytes;
  String? _pathLabel;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('rust_image_core demo')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_status),
              if (_pathLabel != null) ...[
                const SizedBox(height: 8),
                Text('Path: $_pathLabel', style: Theme.of(context).textTheme.bodySmall),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _runPipeline,
                child: const Text('Run RGBA filter + export'),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _jpegBytes == null
                    ? const Center(child: Text('JPEG preview appears here'))
                    : Image.memory(_jpegBytes!, fit: BoxFit.contain),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _runPipeline() async {
    setState(() {
      _status = 'Initializing Rust…';
      _jpegBytes = null;
      _pathLabel = null;
    });

    try {
      await ensureRustImageCoreInitialized();

      const w = 256;
      const h = 256;
      final base = RgbaImageBuffer(
        width: w,
        height: h,
        pixels: _syntheticGradientRgba(w, h),
      );

      final filtered = filterRgbaBuffer(
        buffer: base,
        filter: const ImageFilter.brightness(amount: 40),
        backend: ProcessingBackend.auto,
      );

      _pathLabel = filterExecutionPathName(
        filter: const ImageFilter.brightness(amount: 40),
        backend: ProcessingBackend.auto,
      );

      final jpeg = encodeRgbaBuffer(
        buffer: filtered,
        format: OutputFormat.jpeg,
        quality: 90,
      );

      if (!mounted) return;
      setState(() {
        _jpegBytes = jpeg;
        _status = 'Done — ${filtered.width}×${filtered.height} RGBA → JPEG '
            '(${jpeg.length} bytes)';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Error: $e');
    }
  }
}

Uint8List _syntheticGradientRgba(int width, int height) {
  final out = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 4;
      out[i] = (x * 255 ~/ width);
      out[i + 1] = (y * 255 ~/ height);
      out[i + 2] = 128;
      out[i + 3] = 255;
    }
  }
  return out;
}
