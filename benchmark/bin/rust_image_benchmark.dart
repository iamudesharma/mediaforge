import 'dart:io';

import 'package:rust_image_benchmark_runner/rust_image_benchmark.dart'
    show BenchmarkCli, RustImageBenchmark;

Future<void> main(List<String> args) async {
  final parsed = BenchmarkCli.parse(args);
  if (parsed.help) {
    stdout.writeln(BenchmarkCli.helpText);
    exit(0);
  }

  final bytes = await BenchmarkCli.loadImageBytes(parsed);
  final report = await RustImageBenchmark.runAll(
    imageBytes: bytes,
    iterations: parsed.iterations,
    previewMaxEdge: parsed.previewMaxEdge,
  );

  stdout.writeln(report.formatTable());

  if (parsed.csvPath != null) {
    await File(parsed.csvPath!).writeAsString(report.formatCsv());
    stdout.writeln('Wrote ${parsed.csvPath}');
  }
}
