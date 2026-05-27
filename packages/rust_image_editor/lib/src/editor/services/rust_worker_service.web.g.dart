// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// **************************************************************************
// Generator: WorkerGenerator 9.3.0 (Squadron 7.4.3)
// **************************************************************************

import 'package:squadron/squadron.dart';

import 'rust_worker_service.dart';

void main() {
  /// Web entry point for RustWorkerService
  run($RustWorkerServiceInitializer);
}

EntryPoint $getRustWorkerServiceActivator(SquadronPlatformType platform) {
  if (platform.isJs) {
    return Squadron.uri(
      'lib/src/editor/services/rust_worker_service.web.g.dart.js',
    );
  } else if (platform.isWasm) {
    return Squadron.uri(
      'lib/src/editor/services/rust_worker_service.web.g.dart.wasm',
    );
  } else {
    throw UnsupportedError('${platform.label} not supported.');
  }
}
