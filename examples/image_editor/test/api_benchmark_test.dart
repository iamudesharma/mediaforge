// Headless CI only. For real Flutter perf use:
//   cd benchmark && ./run_dart_benchmark.sh

import 'package:flutter_test/flutter_test.dart';
import 'package:rust_image_benchmark_runner/benchmark_runner.dart';
import 'package:rust_image_benchmark_runner/media_forge_benchmark.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('rust_image API benchmark (direct / FRB)', () async {
    final cli = BenchmarkRunner.cliFromEnvironment();
    final bytes = await BenchmarkCli.loadImageBytes(cli);
    final report = await RustImageBenchmark.runAll(
      imageBytes: bytes,
      iterations: cli.iterations,
      previewMaxEdge: cli.previewMaxEdge,
    );
    // ignore: avoid_print
    print(report.formatTable());
  }, timeout: const Timeout(Duration(minutes: 30)));
}
