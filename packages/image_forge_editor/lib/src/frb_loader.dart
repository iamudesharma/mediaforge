import 'dart:io';

/// Locates a built `image_forge` dynamic library for `flutter test` / CLI.
///
/// App builds link Rust via CargoKit (pods / Gradle). The test runner does not,
/// so pass [RUST_IMAGE_DYLIB] or build release and rely on these search paths.
String? discoverRustImageCoreDylib() {
  if (Platform.isWindows) {
    return _firstExisting([
      for (final dir in _dylibSearchDirs)
        '$dir/image_forge.dll',
      for (final dir in _dylibSearchDirs)
        '$dir/libimage_forge.dll',
    ]);
  }

  if (Platform.isMacOS) {
    return _firstExisting([
      for (final dir in _dylibSearchDirs) '$dir/libimage_forge.dylib',
    ]);
  }
  if (Platform.isLinux) {
    return _firstExisting([
      for (final dir in _dylibSearchDirs) '$dir/libimage_forge.so',
    ]);
  }

  return null;
}

const _dylibSearchDirs = [
  'packages/image_forge/rust/target/debug',
  'packages/image_forge/rust/target/debug/deps',
  'packages/image_forge/rust/target/release',
  'packages/image_forge/rust/target/release/deps',
  '../image_forge/rust/target/debug',
  '../image_forge/rust/target/debug/deps',
  '../image_forge/rust/target/release',
  '../image_forge/rust/target/release/deps',
  '../../image_forge/rust/target/debug',
  '../../image_forge/rust/target/debug/deps',
  '../../image_forge/rust/target/release',
  '../../image_forge/rust/target/release/deps',
  '../../../image_forge/rust/target/debug',
  '../../../image_forge/rust/target/debug/deps',
  '../../../image_forge/rust/target/release',
  '../../../image_forge/rust/target/release/deps',
  // Example app build products (macOS).
  'rust_image/example/build/macos/Build/Products/Release/image_forge',
  '../rust_image/example/build/macos/Build/Products/Release/image_forge',
  '../../rust_image/example/build/macos/Build/Products/Release/image_forge',
];

String? _firstExisting(List<String> paths) {
  for (final path in paths) {
    final file = File(path);
    if (file.existsSync()) return file.absolute.path;
  }
  return null;
}
