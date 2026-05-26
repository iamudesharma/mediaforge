import 'dart:io';

import 'package:flutter/foundation.dart';

class RustWorkerPoolConfig {
  final int minWorkers;
  final int maxWorkers;
  final int maxIdleTimeMs;
  
  const RustWorkerPoolConfig({
    this.minWorkers = 2,
    this.maxWorkers = 4,
    this.maxIdleTimeMs = 30000,
  });
  
  /// Auto-detect based on platform capabilities (VM / mobile / desktop).
  factory RustWorkerPoolConfig.auto() {
    final cores = kIsWeb ? 2 : Platform.numberOfProcessors;
    return RustWorkerPoolConfig(
      minWorkers: (cores ~/ 2).clamp(1, 2),
      maxWorkers: (cores - 1).clamp(2, 4),
    );
  }
}
