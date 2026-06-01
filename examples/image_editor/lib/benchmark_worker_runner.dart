import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:image_forge_editor/image_forge_editor.dart';
import 'package:rust_image_benchmark_runner/benchmark_frb_init.dart';
import 'package:rust_image_benchmark_runner/benchmark_runner.dart';
import 'package:rust_image_benchmark_runner/media_forge_benchmark.dart';

/// Headless entry for worker-isolate benchmarks only.
///
/// ```bash
/// cd rust_image/example
/// flutter run -d macos -t lib/benchmark_worker_runner.dart --release
/// ```
///
/// For CPU + GPU + worker together, use [benchmark_main.dart] instead.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await BenchmarkRunner.runFromEnvironment(
    runWorker: ({required imageBytes, required iterations, required previewMaxEdge}) =>
        runWorkerPipelineBenchmark(imageBytes: imageBytes, iterations: iterations, previewMaxEdge: previewMaxEdge),
  );
  exit(0);
}

/// Benchmarks the **editor pipeline**: Rust calls from a background isolate
/// via [RustWorker] (same as live filters / preview in the app).
Future<BenchmarkReport> runWorkerPipelineBenchmark({
  required Uint8List imageBytes,
  int iterations = 10,
  int previewMaxEdge = 1280,
}) async {
  await ensureBenchmarkFfi();
  await RustWorker.ensureStarted();

  final info = RustImageEditor.probe(imageBytes);
  final gpuAvailable = RustImageEditor.gpuInfo().available;
  final rows = <BenchmarkRow>[];

  Future<void> op(String name, String backend, Future<void> Function() fn, {String path = 'cpu'}) async {
    rows.add(await _runTimed(name: name, backend: backend, iterations: iterations, run: fn, path: path));
  }

  await op('worker_decode_rgba', 'n/a', () async {
    await RustWorker.decodeRgba(imageBytes);
  });

  for (final backend in [ProcessingBackend.cpu, ProcessingBackend.gpu]) {
    if (backend == ProcessingBackend.gpu && !gpuAvailable) continue;
    final label = backend.name;
    final filter = FilterDescriptor.blur(radius: 4);

    await op('worker_filter_rgba_blur', label, () async {
      final decoded = await RustWorker.decodeRgba(Uint8List.fromList(imageBytes));
      await RustWorker.filterRgba(
        buffer: decoded,
        filter: filter,
        backend: backend,
        previewMaxEdge: previewMaxEdge,
        previewQuality: 85,
      );
    }, path: label);

    await op('worker_filter_rgba_brightness', label, () async {
      final decoded = await RustWorker.decodeRgba(Uint8List.fromList(imageBytes));
      await RustWorker.filterRgba(
        buffer: decoded,
        filter: FilterDescriptor.brightness(amount: 25),
        backend: backend,
        previewMaxEdge: previewMaxEdge,
        previewQuality: 85,
      );
    }, path: label);
  }

  await op('worker_encode_preview', 'n/a', () async {
    final decoded = await RustWorker.decodeRgba(Uint8List.fromList(imageBytes));
    await RustWorker.encodePreview(buffer: decoded, previewMaxEdge: previewMaxEdge, quality: 85);
  });

  await op('worker_filter_bytes_blur', 'n/a', () async {
    await RustWorker.filterBytes(
      bytes: Uint8List.fromList(imageBytes),
      filter: FilterDescriptor.blur(radius: 4),
      format: OutputFormat.jpeg,
      quality: 90,
    );
  });

  return BenchmarkReport(
    width: info.width,
    height: info.height,
    iterations: iterations,
    gpuAvailable: gpuAvailable,
    rows: rows,
  );
}

Future<BenchmarkRow> _runTimed({
  required String name,
  required String backend,
  required int iterations,
  required Future<void> Function() run,
  required String path,
}) async {
  final samples = <int>[];
  for (var i = 0; i < iterations; i++) {
    final sw = Stopwatch()..start();
    await run();
    samples.add(sw.elapsedMilliseconds);
  }
  final mean = samples.reduce((a, b) => a + b) / samples.length;
  final min = samples.reduce((a, b) => a < b ? a : b).toDouble();
  final max = samples.reduce((a, b) => a > b ? a : b).toDouble();
  return BenchmarkRow(
    name: name,
    backend: backend,
    iterations: iterations,
    meanMs: mean,
    minMs: min,
    maxMs: max,
    path: path,
  );
}
