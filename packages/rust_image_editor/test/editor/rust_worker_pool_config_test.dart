import 'package:flutter_test/flutter_test.dart';
import 'package:rust_image_editor/src/editor/services/rust_worker_pool_config.dart';

void main() {
  test('auto config keeps workers within bounds', () {
    final config = RustWorkerPoolConfig.auto();
    expect(config.minWorkers, inInclusiveRange(1, 2));
    expect(config.maxWorkers, inInclusiveRange(2, 4));
    expect(config.maxWorkers, greaterThanOrEqualTo(config.minWorkers));
  });

  test('custom config preserves values', () {
    const config = RustWorkerPoolConfig(
      minWorkers: 1,
      maxWorkers: 2,
      maxIdleTimeMs: 5000,
    );
    expect(config.minWorkers, 1);
    expect(config.maxWorkers, 2);
    expect(config.maxIdleTimeMs, 5000);
  });
}
