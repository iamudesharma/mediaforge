import 'dart:io';
import 'dart:typed_data';

import 'package:rust_image_editor/rust_image_editor.dart';
import 'package:rust_image_benchmark_runner/benchmark_frb_init.dart';

/// Cold-run benchmark of public [RustImageEditor] APIs (Dart + FRB).
///
/// Each iteration clones input bytes and re-decodes RGBA where needed — no
/// cross-iteration result caching.
class RustImageBenchmark {
  RustImageBenchmark._();

  static Future<BenchmarkReport> runAll({
    required Uint8List imageBytes,
    int iterations = 10,
    int previewMaxEdge = 1280,
    int jpegQuality = 85,
  }) async {
    await ensureBenchmarkFfi();
    final info = RustImageEditor.probe(imageBytes);
    final gpuAvailable = RustImageEditor.gpuInfo().available;
    final w = info.width;
    final h = info.height;

    final rows = <BenchmarkRow>[];

    Future<void> bytesOp(
      String name,
      String backend,
      void Function(Uint8List fresh) op, {
      String path = 'cpu',
    }) async {
      rows.add(_runBytes(
        name: name,
        backend: backend,
        iterations: iterations,
        imageBytes: imageBytes,
        op: op,
        path: path,
      ));
    }

    Future<void> rgbaOp(
      String name,
      String backend,
      void Function(RgbaImageBuffer buf) op, {
      String? path,
      ProcessingBackend? pb,
    }) async {
      rows.add(_runRgba(
        name: name,
        backend: backend,
        iterations: iterations,
        imageBytes: imageBytes,
        op: op,
        path: path ??
            (pb != null
                ? RustImageEditor.filterExecutionPath(
                    _filterForName(name),
                    pb,
                  )
                : 'cpu'),
      ));
    }

    await bytesOp('probe_image', 'n/a', (b) {
      RustImageEditor.probe(b);
    });

    await bytesOp('decode_jpeg', 'n/a', (b) {
      RustImageEditor.decodeToRgba(b, fixExif: true);
    });

    await bytesOp('compress_jpeg', 'n/a', (b) {
      RustImageEditor.compress(
        bytes: b,
        format: OutputFormat.jpeg,
        quality: jpegQuality,
      );
    });

    await bytesOp('decode_progressive', 'n/a', (b) {
      RustImageEditor.decodeProgressive(
        b,
        previewMaxEdge: previewMaxEdge,
        fixExif: true,
      );
    });

    await bytesOp('apply_filter_blur_bytes', 'n/a', (b) {
      RustImageEditor.filter(
        bytes: b,
        filter: const ImageFilter.blur(radius: 4),
      );
    });

    await bytesOp('crop_image', 'n/a', (b) {
      final i = RustImageEditor.probe(b);
      final iw = i.width;
      final ih = i.height;
      final cw = iw ~/ 2;
      final ch = ih ~/ 2;
      RustImageEditor.crop(
        bytes: b,
        x: cw ~/ 4,
        y: ch ~/ 4,
        width: cw,
        height: ch,
      );
    });

    await bytesOp('rotate_image_90', 'n/a', (b) {
      RustImageEditor.rotate(
        bytes: b,
        rotation: Rotation.rotate90,
      );
    });

    for (final backend in [ProcessingBackend.cpu, ProcessingBackend.gpu]) {
      if (backend == ProcessingBackend.gpu && !gpuAvailable) continue;
      final label = backend.name;

      await bytesOp('resize_image_50pct', label, (b) {
        final i = RustImageEditor.probe(b);
        final iw = i.width;
        final ih = i.height;
        RustImageEditor.resize(
          bytes: b,
          width: iw ~/ 2,
          height: ih ~/ 2,
          backend: backend,
        );
      }, path: label);

      await bytesOp('thumbnail_512', label, (b) {
        RustImageEditor.thumbnail(
          bytes: b,
          maxEdge: 512,
          backend: backend,
        );
      }, path: label);
    }

    for (final backend in [ProcessingBackend.cpu, ProcessingBackend.gpu]) {
      if (backend == ProcessingBackend.gpu && !gpuAvailable) continue;
      final label = backend.name;

      await rgbaOp('resize_rgba_50pct', label, (buf) {
        RustImageEditor.resizeRgba(
          buf,
          width: buf.width ~/ 2,
          height: buf.height ~/ 2,
          backend: backend,
        );
      }, pb: backend);

      await rgbaOp('filter_rgba_blur', label, (buf) {
        RustImageEditor.filterRgba(
          buf,
          const ImageFilter.blur(radius: 4),
          backend: backend,
        );
      }, pb: backend);

      await rgbaOp('filter_rgba_sharpen', label, (buf) {
        RustImageEditor.filterRgba(
          buf,
          const ImageFilter.sharpen(),
          backend: backend,
        );
      }, pb: backend);

      await rgbaOp('filter_rgba_brightness', label, (buf) {
        RustImageEditor.filterRgba(
          buf,
          const ImageFilter.brightness(amount: 25),
          backend: backend,
        );
      }, pb: backend);

      await rgbaOp('filter_rgba_contrast', label, (buf) {
        RustImageEditor.filterRgba(
          buf,
          const ImageFilter.contrast(amount: 1.2),
          backend: backend,
        );
      }, pb: backend);

      await rgbaOp('filter_rgba_saturation', label, (buf) {
        RustImageEditor.filterRgba(
          buf,
          const ImageFilter.saturation(amount: 1.3),
          backend: backend,
        );
      }, pb: backend);

      await rgbaOp('filter_rgba_preset_dramatic', label, (buf) {
        RustImageEditor.filterRgba(
          buf,
          const ImageFilter.preset(
            preset: FilterPreset.dramatic,
            strength: 1.0,
          ),
          backend: backend,
        );
      }, pb: backend);
    }

    await rgbaOp('encode_rgba_preview', 'n/a', (buf) {
      RustImageEditor.encodeRgbaPreview(
        buf,
        maxEdge: previewMaxEdge,
        quality: jpegQuality,
      );
    });

    await rgbaOp('encode_rgba_jpeg', 'n/a', (buf) {
      RustImageEditor.encodeRgba(
        buf,
        format: OutputFormat.jpeg,
        quality: jpegQuality,
      );
    });

    await rgbaOp('fit_max_edge_rgba', 'n/a', (buf) {
      RustImageEditor.fitMaxEdgeRgba(buf, maxEdge: previewMaxEdge);
    });

    await rgbaOp('crop_rgba', 'n/a', (buf) {
      final cw = buf.width ~/ 2;
      final ch = buf.height ~/ 2;
      RustImageEditor.cropRgba(
        buf,
        x: cw ~/ 4,
        y: ch ~/ 4,
        width: cw,
        height: ch,
      );
    });

    await rgbaOp('draw_line_rgba', 'n/a', (buf) {
      RustImageEditor.drawLineRgba(
        buf,
        line: DrawLine(
          x0: 0,
          y0: 0,
          x1: buf.width > 400 ? 400 : buf.width,
          y1: buf.height > 400 ? 400 : buf.height,
          colorR: 255,
          colorG: 0,
          colorB: 0,
          colorA: 255,
        ),
      );
    });

    await rgbaOp('draw_text_rgba', 'n/a', (buf) {
      RustImageEditor.drawTextRgba(
        buf,
        overlay: const TextOverlay(
          text: 'Bench',
          x: 40,
          y: 40,
          fontSize: 32,
          colorR: 255,
          colorG: 255,
          colorB: 255,
          colorA: 255,
        ),
      );
    });

    return BenchmarkReport(
      width: w,
      height: h,
      iterations: iterations,
      gpuAvailable: gpuAvailable,
      rows: rows,
    );
  }

  static BenchmarkRow _runBytes({
    required String name,
    required String backend,
    required int iterations,
    required Uint8List imageBytes,
    required void Function(Uint8List fresh) op,
    required String path,
  }) {
    final samples = <int>[];
    for (var i = 0; i < iterations; i++) {
      final fresh = Uint8List.fromList(imageBytes);
      final sw = Stopwatch()..start();
      op(fresh);
      samples.add(sw.elapsedMilliseconds);
    }
    return _stats(name, backend, iterations, samples, path);
  }

  static BenchmarkRow _runRgba({
    required String name,
    required String backend,
    required int iterations,
    required Uint8List imageBytes,
    required void Function(RgbaImageBuffer buf) op,
    required String path,
  }) {
    final samples = <int>[];
    for (var i = 0; i < iterations; i++) {
      final fresh = Uint8List.fromList(imageBytes);
      final decoded = RustImageEditor.decodeToRgba(fresh, fixExif: true);
      final buf = RgbaImageBuffer(
        width: decoded.width,
        height: decoded.height,
        pixels: Uint8List.fromList(decoded.pixels),
      );
      final sw = Stopwatch()..start();
      op(buf);
      samples.add(sw.elapsedMilliseconds);
    }
    return _stats(name, backend, iterations, samples, path);
  }

  static BenchmarkRow _stats(
    String name,
    String backend,
    int iterations,
    List<int> samplesMs,
    String path,
  ) {
    final mean = samplesMs.reduce((a, b) => a + b) / samplesMs.length;
    final min = samplesMs.reduce((a, b) => a < b ? a : b);
    final max = samplesMs.reduce((a, b) => a > b ? a : b);
    return BenchmarkRow(
      name: name,
      backend: backend,
      iterations: iterations,
      meanMs: mean,
      minMs: min.toDouble(),
      maxMs: max.toDouble(),
      path: path,
    );
  }

  static ImageFilter _filterForName(String name) {
    if (name.contains('blur')) return const ImageFilter.blur(radius: 4);
    if (name.contains('sharpen')) return const ImageFilter.sharpen();
    if (name.contains('brightness')) {
      return const ImageFilter.brightness(amount: 25);
    }
    if (name.contains('contrast')) {
      return const ImageFilter.contrast(amount: 1.2);
    }
    if (name.contains('saturation')) {
      return const ImageFilter.saturation(amount: 1.3);
    }
    if (name.contains('dramatic')) {
      return const ImageFilter.preset(
        preset: FilterPreset.dramatic,
        strength: 1.0,
      );
    }
    return const ImageFilter.blur(radius: 4);
  }
}

class BenchmarkReport {
  BenchmarkReport({
    required this.width,
    required this.height,
    required this.iterations,
    required this.gpuAvailable,
    required this.rows,
  });

  final int width;
  final int height;
  final int iterations;
  final bool gpuAvailable;
  final List<BenchmarkRow> rows;

  String formatTable() {
    final b = StringBuffer()
      ..writeln(
        'rust_image Dart/FRB benchmark — ${width}x$height — $iterations iterations — GPU: $gpuAvailable',
      )
      ..writeln()
      ..writeln(
        '${'operation'.padRight(32)} ${'backend'.padRight(6)} ${'mean_ms'.padLeft(8)} ${'min_ms'.padLeft(8)} ${'max_ms'.padLeft(8)} path',
      )
      ..writeln('-' * 80);
    for (final r in rows) {
      b.writeln(
        '${r.name.padRight(32)} ${r.backend.padRight(6)} ${r.meanMs.toStringAsFixed(2).padLeft(8)} ${r.minMs.toStringAsFixed(2).padLeft(8)} ${r.maxMs.toStringAsFixed(2).padLeft(8)} ${r.path}',
      );
    }
    return b.toString();
  }

  String formatCsv() {
    final b = StringBuffer()
      ..writeln(
        'operation,backend,iterations,mean_ms,min_ms,max_ms,path,width,height,gpu_available',
      );
    for (final r in rows) {
      b.writeln(
        '${r.name},${r.backend},${r.iterations},${r.meanMs.toStringAsFixed(3)},${r.minMs},${r.maxMs},${r.path},$width,$height,$gpuAvailable',
      );
    }
    return b.toString();
  }
}

class BenchmarkRow {
  const BenchmarkRow({
    required this.name,
    required this.backend,
    required this.iterations,
    required this.meanMs,
    required this.minMs,
    required this.maxMs,
    required this.path,
  });

  final String name;
  final String backend;
  final int iterations;
  final double meanMs;
  final double minMs;
  final double maxMs;
  final String path;
}

class BenchmarkCli {
  BenchmarkCli({
    required this.help,
    this.imagePath,
    required this.synthetic,
    required this.iterations,
    required this.previewMaxEdge,
    this.csvPath,
  });

  final bool help;
  final String? imagePath;
  final bool synthetic;
  final int iterations;
  final int previewMaxEdge;
  final String? csvPath;

  static const helpText = '''
rust_image Dart/FRB benchmark — use Flutter, not plain dart run

  cd rust_image/benchmark && ./run_dart_benchmark.sh
  cd rust_image/example && BENCH_ITERATIONS=10 flutter test test/api_benchmark_test.dart

Env: BENCH_IMAGE, BENCH_SYNTHETIC=1, BENCH_ITERATIONS, BENCH_PREVIEW_MAX_EDGE, BENCH_CSV
Optional: RUST_IMAGE_DYLIB=/path/to/librust_image_core.dylib
''';

  static BenchmarkCli parse(List<String> args) {
    String? imagePath;
    var synthetic = false;
    var iterations = 10;
    var previewMaxEdge = 1280;
    String? csvPath;
    var help = false;

    for (var i = 0; i < args.length; i++) {
      switch (args[i]) {
        case '-h':
        case '--help':
          help = true;
        case '-i':
        case '--image':
          if (i + 1 >= args.length) {
            throw ArgumentError('missing value for ${args[i]}');
          }
          imagePath = args[++i];
        case '--synthetic':
          synthetic = true;
        case '-n':
        case '--iterations':
          if (i + 1 >= args.length) {
            throw ArgumentError('missing value for ${args[i]}');
          }
          iterations = int.parse(args[++i]);
        case '--preview-max-edge':
          if (i + 1 >= args.length) {
            throw ArgumentError('missing value for ${args[i]}');
          }
          previewMaxEdge = int.parse(args[++i]);
        case '--csv':
          if (i + 1 >= args.length) {
            throw ArgumentError('missing value for ${args[i]}');
          }
          csvPath = args[++i];
      }
    }

    return BenchmarkCli(
      help: help,
      imagePath: imagePath,
      synthetic: synthetic,
      iterations: iterations,
      previewMaxEdge: previewMaxEdge,
      csvPath: csvPath,
    );
  }

  static Future<Uint8List> loadImageBytes(BenchmarkCli cli) async {
    if (cli.imagePath != null) {
      return File(cli.imagePath!).readAsBytes();
    }
    if (cli.synthetic) {
      return _syntheticJpeg(1280, 720);
    }
    throw ArgumentError('Provide --image or --synthetic');
  }

  static Future<Uint8List> _syntheticJpeg(int width, int height) async {
    await ensureBenchmarkFfi();
    final pixels = Uint8List(width * height * 4);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final i = (y * width + x) * 4;
        pixels[i] = x % 256;
        pixels[i + 1] = y % 256;
        pixels[i + 2] = 128;
        pixels[i + 3] = 255;
      }
    }
    return RustImageEditor.encodeRgba(
      RgbaImageBuffer(width: width, height: height, pixels: pixels),
      format: OutputFormat.jpeg,
      quality: 85,
    );
  }
}
