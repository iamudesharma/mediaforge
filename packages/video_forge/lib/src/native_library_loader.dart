import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';

/// Resolves and opens `libvideo_forge` for the current platform.
abstract final class NativeLibraryLoader {
  static const String stem = 'video_forge';

  static Future<ExternalLibrary> load() async {
    // iOS: linked via CocoaPods vendored_frameworks — not a loose CodeAsset dylib.
    if (Platform.isIOS) {
      // Linked via CocoaPods vendored_frameworks (see ios/video_forge_kit.podspec).
      for (final name in [
        'video_forge.framework/video_forge',
        _bundledLibName(),
      ]) {
        try {
          return ExternalLibrary.open(name, debugInfo: 'ios framework');
        } catch (_) {
          // try next
        }
      }
    }

    // Android: .so in jniLibs / APK.
    if (Platform.isAndroid) {
      try {
        return ExternalLibrary.open(_bundledLibName());
      } catch (_) {
        // Fall through to path search / FRB default.
      }
    }

    final candidates = _candidatePaths();
    for (final path in candidates) {
      if (File(path).existsSync()) {
        return ExternalLibrary.open(path);
      }
    }

    try {
      return await loadExternalLibrary(
        const ExternalLibraryLoaderConfig(
          stem: stem,
          ioDirectory: null,
          webPrefix: 'pkg/',
          wasmBindgenName: 'wasm_bindgen',
        ),
      );
    } catch (_) {
      throw StateError(
        'Could not load native library "$stem".\n'
        '${_platformHint()}\n'
        'Tried:\n${candidates.map((p) => '  - $p').join('\n')}',
      );
    }
  }

  static String _bundledLibName() {
    if (Platform.isIOS || Platform.isMacOS) {
      return 'lib$stem.dylib';
    }
    if (Platform.isWindows) {
      return '$stem.dll';
    }
    return 'lib$stem.so';
  }

  static String _platformHint() {
    if (Platform.isAndroid) {
      return 'Android: from repo root run:\n'
          '  ./scripts/run-android.sh\n'
          '  (package-video-android.sh → jniLibs, then flutter run)\n'
          'Requires NDK + FFmpeg: ./tools/ffmpeg/android.sh';
    }
    if (Platform.isIOS) {
      return 'iOS: from repo root run:\n'
          '  ./scripts/run-ios.sh\n'
          '  (builds FFmpeg + video_forge.framework)';
    }
    if (Platform.isMacOS) {
      return 'macOS: from repo root run:\n'
          '  ./scripts/run-video-macos.sh\n'
          '  (cargo build --release; Flutter hook bundles libvideo_forge.dylib)';
    }
    return 'Build it first:\n'
        '  cargo build --release -p video_forge';
  }

  static List<String> _candidatePaths() {
    final envDir = Platform.environment[
        'FRB_DART_LOAD_EXTERNAL_LIBRARY_NATIVE_LIB_DIR'];
    if (envDir != null && envDir.isNotEmpty) {
      return [_libNameInDir(envDir)];
    }

    final cwd = Directory.current.path;
    final executable = Platform.resolvedExecutable;
    final execDir = File(executable).parent.path;

    final paths = <String>[
      '$cwd/../target/release/${_dylibFileName()}',
      '$cwd/../../target/release/${_dylibFileName()}',
      '$cwd/../../../target/release/${_dylibFileName()}',
      '$cwd/../../../../target/release/${_dylibFileName()}',
      '$cwd/../../packages/video_forge/rust/target/release/${_dylibFileName()}',
      '$cwd/../packages/video_forge/rust/target/release/${_dylibFileName()}',
      '$execDir/../Frameworks/${_dylibFileName()}',
      '$execDir/../Frameworks/$stem.framework/$stem',
      '$execDir/Frameworks/${_dylibFileName()}',
      '$execDir/Frameworks/$stem.framework/$stem',
      '$cwd/../packages/video_forge/macos/Frameworks/$stem.framework/$stem',
      '$cwd/../../packages/video_forge/macos/Frameworks/$stem.framework/$stem',
      '$cwd/packages/video_forge/macos/Frameworks/$stem.framework/$stem',
    ];

    if (Platform.isAndroid) {
      // Flutter may extract native assets under app data (dev / hook builds).
      paths.addAll([
        '$execDir/lib/${_dylibFileName()}',
        '$execDir/../lib/${_dylibFileName()}',
      ]);
    }

    if (Platform.isMacOS || Platform.isIOS) {
      paths.addAll([
        '/usr/local/lib/${_dylibFileName()}',
        '${Platform.environment['HOME']}/.video_forge_kit/${_dylibFileName()}',
      ]);
    }

    return paths;
  }

  static String _libNameInDir(String dir) {
    final normalized = dir.endsWith('/') ? dir : '$dir/';
    return '$normalized${_dylibFileName()}';
  }

  static String _dylibFileName() => _bundledLibName();
}
