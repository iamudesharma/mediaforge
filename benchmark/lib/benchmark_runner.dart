import 'dart:io';
import 'dart:typed_data';

import 'package:rust_image_benchmark_runner/rust_image_benchmark.dart';

/// How Dart reaches Rust — mirrors what you measure in production.
enum BenchmarkPipeline {
  /// [RustImageEditor] on the main isolate (FRB only, no worker).
  direct,

  /// Same APIs but via [RustWorker] isolate (what the editor uses).
  worker,
}

/// Env-driven benchmark run (used by `flutter run`, `flutter test`, scripts).
class BenchmarkRunner {
  static BenchmarkCli cliFromEnvironment() {
    final imagePath = Platform.environment['BENCH_IMAGE'];
    final synthetic = _envBool('BENCH_SYNTHETIC', imagePath == null);
    return BenchmarkCli(
      help: false,
      imagePath: imagePath,
      synthetic: synthetic,
      iterations: _envInt('BENCH_ITERATIONS', 10),
      previewMaxEdge: _envInt('BENCH_PREVIEW_MAX_EDGE', 1280),
      csvPath: Platform.environment['BENCH_CSV'],
    );
  }

  static BenchmarkPipeline pipelineFromEnvironment() {
    final raw =
        Platform.environment['BENCH_PIPELINE']?.toLowerCase() ?? 'direct';
    return switch (raw) {
      'worker' => BenchmarkPipeline.worker,
      'both' => BenchmarkPipeline.worker, // caller runs both
      _ => BenchmarkPipeline.direct,
    };
  }

  static Future<void> runFromEnvironment({
    void Function(String line)? sink,
    Future<BenchmarkReport> Function({
      required Uint8List imageBytes,
      required int iterations,
      required int previewMaxEdge,
    })? runWorker,
  }) async {
    void out(String text) {
      if (sink != null) {
        sink(text);
      } else {
        stdout.writeln(text);
      }
    }
    final cli = cliFromEnvironment();
    final pipeline = pipelineFromEnvironment();
    final bytes = await BenchmarkCli.loadImageBytes(cli);

    if (pipeline == BenchmarkPipeline.direct ||
        Platform.environment['BENCH_PIPELINE']?.toLowerCase() == 'both') {
      await _printReport(
        out,
        'direct (RustImageEditor on main isolate — FRB)',
        await RustImageBenchmark.runAll(
          imageBytes: bytes,
          iterations: cli.iterations,
          previewMaxEdge: cli.previewMaxEdge,
        ),
        cli.csvPath,
        suffix: '_direct',
      );
    }

    if (pipeline == BenchmarkPipeline.worker ||
        Platform.environment['BENCH_PIPELINE']?.toLowerCase() == 'both') {
      if (runWorker == null) {
        stderr.writeln(
          'BENCH_PIPELINE=worker requires Flutter example (RustWorker). '
          'Use ./run_dart_benchmark.sh from benchmark/',
        );
        exit(1);
      }
      await _printReport(
        out,
        'worker (RustWorker isolate — editor hot path)',
        await runWorker(
          imageBytes: bytes,
          iterations: cli.iterations,
          previewMaxEdge: cli.previewMaxEdge,
        ),
        cli.csvPath,
        suffix: '_worker',
      );
    }
  }

  static Future<void> _printReport(
    void Function(String) out,
    String label,
    BenchmarkReport report,
    String? csvPath, {
    String suffix = '',
  }) async {
    out('\n=== $label ===\n');
    out(report.formatTable());
    if (csvPath != null) {
      final path = csvPath.replaceAll(RegExp(r'\.csv$'), '$suffix.csv');
      await File(path).writeAsString(report.formatCsv());
      out('Wrote $path');
    }
  }
}

int _envInt(String key, int defaultValue) {
  final raw = Platform.environment[key];
  if (raw == null || raw.isEmpty) return defaultValue;
  return int.parse(raw);
}

bool _envBool(String key, bool defaultValue) {
  final raw = Platform.environment[key];
  if (raw == null || raw.isEmpty) return defaultValue;
  return raw == '1' || raw.toLowerCase() == 'true';
}
