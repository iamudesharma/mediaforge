import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_forge_core/image_forge_core.dart';

import 'rust_core_init.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CoreDemoApp());
}

class CoreDemoApp extends StatefulWidget {
  const CoreDemoApp({super.key});

  @override
  State<CoreDemoApp> createState() => _CoreDemoAppState();
}

class _CoreDemoAppState extends State<CoreDemoApp> {
  String _status = 'Ready';
  Uint8List? _outputBytes;
  String? _pathLabel;
  GpuComputeInfo? _gpuInfo;
  String? _blurhash;
  String? _imageInfo;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('image_forge_core demo')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_status),
              if (_pathLabel != null) ...[
                const SizedBox(height: 4),
                Text('Path: $_pathLabel',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
              if (_gpuInfo != null) ...[
                const SizedBox(height: 4),
                Text(
                    'GPU: ${_gpuInfo!.device} (${_gpuInfo!.api})'),
              ],
              if (_imageInfo != null) ...[
                const SizedBox(height: 4),
                Text('Image: $_imageInfo',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
              if (_blurhash != null) ...[
                const SizedBox(height: 4),
                Text('BlurHash: $_blurhash',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _runPipeline,
                child: const Text('Run full pipeline'),
              ),
              FilledButton(
                onPressed: _runSingleOps,
                child: const Text('Run single operations'),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _outputBytes == null
                    ? const Center(child: Text('Output preview appears here'))
                    : Image.memory(_outputBytes!, fit: BoxFit.contain),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _runPipeline() async {
    setState(() {
      _status = 'Initializing Rust...';
      _outputBytes = null;
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

      final gpu = gpuComputeInfo();
      _gpuInfo = gpu;

      final jpeg = encodeRgbaBuffer(
        buffer: filtered,
        format: OutputFormat.jpeg,
        quality: 90,
      );

      if (!mounted) return;
      setState(() {
        _outputBytes = jpeg;
        _status = 'Pipeline done — ${filtered.width}\xd7${filtered.height} '
            'RGBA \u2192 JPEG (${jpeg.length} bytes)';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Error: $e');
    }
  }

  Future<void> _runSingleOps() async {
    setState(() {
      _status = 'Running single ops...';
      _outputBytes = null;
    });

    try {
      await ensureRustImageCoreInitialized();

      // Create a synthetic JPEG
      const w = 128;
      const h = 128;
      final raw = _syntheticGradientRgba(w, h);
      final buf = RgbaImageBuffer(width: w, height: h, pixels: raw);
      var jpeg = encodeRgbaBuffer(
          buffer: buf, format: OutputFormat.jpeg, quality: 92);

      // Probe
      final info = probeImage(bytes: jpeg);
      _imageInfo = '${info.width}\xd7${info.height} ${info.format} '
          'orient=${info.exifOrientation}';

      // BlurHash
      _blurhash = encodeBlurhash(bytes: jpeg, componentsX: 4, componentsY: 3);

      // Resize
      final resized = resizeImage(
        bytes: jpeg,
        width: 64,
        height: 64,
        algorithm: ResizeAlgorithm.lanczos3,
        format: OutputFormat.jpeg,
        quality: 85,
        fixExif: true,
        backend: ProcessingBackend.auto,
      );

      // Compress
      final compressed = compressImage(
          bytes: resized, format: OutputFormat.jpeg, quality: 40);

      // Crop
      final cropped = cropImage(
        bytes: compressed,
        x: 8,
        y: 8,
        width: 48,
        height: 48,
        format: OutputFormat.png,
        quality: 100,
        fixExif: false,
      );

      final gpu = gpuComputeInfo();
      _gpuInfo = gpu;

      if (!mounted) return;
      setState(() {
        _outputBytes = cropped;
        _status = 'Single ops done — cropped PNG (${cropped.length} bytes)';
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
