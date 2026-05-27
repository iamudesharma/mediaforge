import 'dart:io';

/// Locates a built `rust_image_core` dynamic library for `flutter test` / CLI.
///
/// App builds link Rust via CargoKit (pods / Gradle). The test runner does not,
/// so pass [RUST_IMAGE_DYLIB] or build release and rely on these search paths.
String? discoverRustImageCoreDylib() {
  if (Platform.isWindows) {
    return _firstExisting([
      for (final dir in _dylibSearchDirs)
        '$dir/rust_image_core.dll',
      for (final dir in _dylibSearchDirs)
        '$dir/librust_image_core.dll',
    ]);
  }

  if (Platform.isMacOS) {
    return _firstExisting([
      for (final dir in _dylibSearchDirs) '$dir/librust_image_core.dylib',
    ]);
  }
  if (Platform.isLinux) {
    return _firstExisting([
      for (final dir in _dylibSearchDirs) '$dir/librust_image_core.so',
    ]);
  }

  return null;
}

const _dylibSearchDirs = [
  'packages/rust_image_core/rust/target/debug',
  'packages/rust_image_core/rust/target/debug/deps',
  'packages/rust_image_core/rust/target/release',
  'packages/rust_image_core/rust/target/release/deps',
  '../rust_image_core/rust/target/debug',
  '../rust_image_core/rust/target/debug/deps',
  '../rust_image_core/rust/target/release',
  '../rust_image_core/rust/target/release/deps',
  '../../rust_image_core/rust/target/debug',
  '../../rust_image_core/rust/target/debug/deps',
  '../../rust_image_core/rust/target/release',
  '../../rust_image_core/rust/target/release/deps',
  '../../../rust_image_core/rust/target/debug',
  '../../../rust_image_core/rust/target/debug/deps',
  '../../../rust_image_core/rust/target/release',
  '../../../rust_image_core/rust/target/release/deps',
  // Example app build products (macOS).
  'rust_image/example/build/macos/Build/Products/Release/rust_image_core',
  '../rust_image/example/build/macos/Build/Products/Release/rust_image_core',
  '../../rust_image/example/build/macos/Build/Products/Release/rust_image_core',
];

String? _firstExisting(List<String> paths) {
  for (final path in paths) {
    final file = File(path);
    if (file.existsSync()) return file.absolute.path;
  }
  return null;
}
