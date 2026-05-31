// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// **************************************************************************
// Generator: WorkerGenerator 9.3.0 (Squadron 7.4.3)
// **************************************************************************

import 'package:squadron/squadron.dart';

import 'rust_worker_service.dart';

void _start$RustWorkerService(WorkerRequest command) {
  /// VM entry point for RustWorkerService
  run($RustWorkerServiceInitializer, command);
}

EntryPoint $getRustWorkerServiceActivator(SquadronPlatformType platform) {
  if (platform.isVm) {
    return _start$RustWorkerService;
  } else {
    throw UnsupportedError('${platform.label} not supported.');
  }
}
