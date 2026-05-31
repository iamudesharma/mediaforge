import 'dart:io';

import 'package:flutter/material.dart';
import 'package:rust_image_benchmark_runner/benchmark_runner.dart';

import 'benchmark_worker_runner.dart';

/// Flutter benchmark entry — same engine + native plugin as the real app.
///
/// Run (from repo):
///   cd rust_image/benchmark && ./run_dart_benchmark.sh
///
/// Or:
///   cd rust_image/example
///   flutter run -d macos -t lib/benchmark_main.dart --release
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final headless = Platform.environment['BENCH_HEADLESS'] != '0';

  if (headless && (Platform.isMacOS || Platform.isLinux || Platform.isWindows)) {
    await BenchmarkRunner.runFromEnvironment(
      runWorker: ({
        required imageBytes,
        required iterations,
        required previewMaxEdge,
      }) =>
          runWorkerPipelineBenchmark(
        imageBytes: imageBytes,
        iterations: iterations,
        previewMaxEdge: previewMaxEdge,
      ),
    );
    exit(0);
  }

  runApp(const _BenchmarkFlutterApp());
}

class _BenchmarkFlutterApp extends StatefulWidget {
  const _BenchmarkFlutterApp();

  @override
  State<_BenchmarkFlutterApp> createState() => _BenchmarkFlutterAppState();
}

class _BenchmarkFlutterAppState extends State<_BenchmarkFlutterApp> {
  String _log = 'Running benchmarks…\n';

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    final buffer = StringBuffer(_log);
    void capture(String line) {
      buffer.writeln(line);
      if (mounted) setState(() => _log = buffer.toString());
    }

    try {
      await BenchmarkRunner.runFromEnvironment(
        sink: capture,
        runWorker: runWorkerPipelineBenchmark,
      );
    } catch (e, st) {
      capture('Error: $e\n$st');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('rust_image benchmark')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: SelectableText(
            _log,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
      ),
    );
  }
}
