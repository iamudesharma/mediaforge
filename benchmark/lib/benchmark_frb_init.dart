import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:image_forge_editor/image_forge_editor.dart';

bool _benchmarkFfiReady = false;

/// Initialize FRB for benchmarks (`flutter test` / integration), not plain `dart run`.
Future<void> ensureBenchmarkFfi() async {
  if (_benchmarkFfiReady) return;

  Future<void> initWith(ExternalLibrary lib) async {
    try {
      await RustLib.init(externalLibrary: lib);
    } on StateError catch (e) {
      if (!e.message.contains('twice')) rethrow;
    }
    _benchmarkFfiReady = true;
  }

  final explicit = Platform.environment['RUST_IMAGE_DYLIB'];
  if (explicit != null && explicit.isNotEmpty) {
    final file = File(explicit);
    if (file.existsSync()) {
      await initWith(ExternalLibrary.open(file.absolute.path));
      return;
    }
    throw StateError('RUST_IMAGE_DYLIB not found: $explicit');
  }

  final discovered = _discoverDylibPath();
  if (discovered != null) {
    await initWith(ExternalLibrary.open(discovered));
    return;
  }

  await RustImageEditor.ensureInitialized();
  _benchmarkFfiReady = true;
}

String? _discoverDylibPath() {
  const relDirs = [
    'packages/image_forge/rust/target/release',
    'packages/image_forge/rust/target/release/deps',
    '../image_forge/rust/target/release',
    '../image_forge/rust/target/release/deps',
    '../../packages/image_forge/rust/target/release',
    '../../packages/image_forge/rust/target/release/deps',
  ];
  const libNames = ['libimage_forge.dylib', 'libimage_forge.so'];

  for (final dir in relDirs) {
    for (final name in libNames) {
      final file = File('$dir/$name');
      if (file.existsSync()) return file.absolute.path;
    }
  }

  return null;
}
