import 'dart:io' show File, Platform;

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:rust_image_core/rust_image_core.dart';

/// Initializes FRB for the core-only example (mirrors editor test loader paths).
Future<void> ensureRustImageCoreInitialized() async {
  final explicit = Platform.environment['RUST_IMAGE_DYLIB'];
  if (explicit != null && explicit.isNotEmpty) {
    final file = File(explicit);
    if (!file.existsSync()) {
      throw StateError('RUST_IMAGE_DYLIB not found: $explicit');
    }
    await RustLib.init(externalLibrary: ExternalLibrary.open(file.absolute.path));
    return;
  }

  if (Platform.isMacOS || Platform.isIOS) {
    try {
      await RustLib.init(
        externalLibrary: ExternalLibrary.process(iKnowHowToUseIt: true),
      );
      return;
    } catch (_) {
      final discovered = _discoverDylib();
      if (discovered != null) {
        await RustLib.init(externalLibrary: ExternalLibrary.open(discovered));
        return;
      }
      rethrow;
    }
  }

  final discovered = _discoverDylib();
  if (discovered != null) {
    await RustLib.init(externalLibrary: ExternalLibrary.open(discovered));
  } else {
    await RustLib.init();
  }
}

String? _discoverDylib() {
  const dirs = [
    'rust/target/debug',
    'rust/target/release',
    '../rust/target/debug',
    '../rust/target/release',
    'packages/rust_image_core/rust/target/debug',
    'packages/rust_image_core/rust/target/release',
  ];
  final name = Platform.isMacOS
      ? 'librust_image_core.dylib'
      : Platform.isLinux
          ? 'librust_image_core.so'
          : 'rust_image_core.dll';
  for (final dir in dirs) {
    final path = '$dir/$name';
    if (File(path).existsSync()) return File(path).absolute.path;
  }
  return null;
}
