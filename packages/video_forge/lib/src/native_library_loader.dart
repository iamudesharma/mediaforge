import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';

/// Resolves and opens `libvideo_forge` for the current platform.
abstract final class NativeLibraryLoader {
  static const String stem = 'video_forge';

  static Future<ExternalLibrary> load() async {
    final loaderLog = _LoaderLog();

    // iOS: linked via CocoaPods vendored_frameworks — not a loose CodeAsset dylib.
    if (Platform.isIOS) {
      for (final name in <String>[
        'video_forge.framework/video_forge',
        _bundledLibName(),
      ]) {
        try {
          final lib = ExternalLibrary.open(name, debugInfo: 'ios framework');
          loaderLog.logMatch('ios framework: $name');
          return lib;
        } catch (e) {
          loaderLog.logCandidate('ios framework: $name', e);
        }
      }
    }

    // Android: .so in jniLibs / APK.
    if (Platform.isAndroid) {
      try {
        final lib = ExternalLibrary.open(_bundledLibName());
        loaderLog.logMatch('android bundled: ${_bundledLibName()}');
        return lib;
      } catch (e) {
        loaderLog.logCandidate('android bundled: ${_bundledLibName()}', e);
      }
    }

    // Three ordered tiers: env override → packaged → workspace target.
    for (final tier in _candidateTiers()) {
      for (final path in tier.paths) {
        if (!File(path).existsSync()) {
          loaderLog.logMiss('${tier.label}: $path (not found)');
          continue;
        }
        try {
          final lib = ExternalLibrary.open(path);
          loaderLog.logMatch('${tier.label}: $path');
          return lib;
        } catch (e) {
          loaderLog.logCandidate('${tier.label}: $path', e);
        }
      }
    }

    // Last resort: FRB's default loader (looks under the active executable).
    try {
      final lib = await loadExternalLibrary(
        const ExternalLibraryLoaderConfig(
          stem: stem,
          ioDirectory: null,
          webPrefix: 'pkg/',
          wasmBindgenName: 'wasm_bindgen',
        ),
      );
      loaderLog.logMatch('frb default loader');
      return lib;
    } catch (e) {
      loaderLog.logCandidate('frb default loader', e);
    }

    throw StateError(
      'Could not load native library "$stem".\n'
      '${_platformHint()}\n\n'
      'Loader log:\n${loaderLog.snapshot()}',
    );
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

  static List<_LoaderTier> _candidateTiers() {
    final envDir = Platform.environment[
        'FRB_DART_LOAD_EXTERNAL_LIBRARY_NATIVE_LIB_DIR'];
    final cwd = Directory.current.path;
    final executable = Platform.resolvedExecutable;
    final execDir = File(executable).parent.path;
    final macosFramework = Platform.isMacOS
        ? '$execDir/../Frameworks/$stem.framework/$stem'
        : null;
    final macosDylib = Platform.isMacOS
        ? '$execDir/../Frameworks/${_bundledLibName()}'
        : null;

    return [
      _LoaderTier('tier1:env', () {
        if (envDir == null || envDir.isEmpty) return const <String>[];
        return [_pathInDir(envDir, _bundledLibName())];
      }()),
      _LoaderTier('tier2:packaged', () {
        if (macosFramework != null && macosDylib != null) {
          return [macosFramework, macosDylib];
        }
        if (Platform.isAndroid) {
          return const ['lib/lib$stem.so', '../lib/lib$stem.so'];
        }
        return const <String>[];
      }()),
      _LoaderTier('tier3:workspace', () {
        return [
          '$cwd/../target/release/${_bundledLibName()}',
          '$cwd/../../target/release/${_bundledLibName()}',
          '$cwd/../../../target/release/${_bundledLibName()}',
          '$cwd/../../../../target/release/${_bundledLibName()}',
          '$cwd/../../packages/video_forge/rust/target/release/${_bundledLibName()}',
          '$cwd/../packages/video_forge/rust/target/release/${_bundledLibName()}',
          '$cwd/../packages/video_forge/macos/Frameworks/$stem.framework/$stem',
          '$cwd/../../packages/video_forge/macos/Frameworks/$stem.framework/$stem',
          '$cwd/packages/video_forge/macos/Frameworks/$stem.framework/$stem',
          ..._androidAppDataCandidates(execDir),
          ..._macosSystemCandidates(),
        ];
      }()),
    ];
  }

  static List<String> _androidAppDataCandidates(String execDir) {
    if (!Platform.isAndroid) return const [];
    return [
      '$execDir/lib/${_bundledLibName()}',
      '$execDir/../lib/${_bundledLibName()}',
    ];
  }

  static List<String> _macosSystemCandidates() {
    if (!Platform.isMacOS && !Platform.isIOS) return const [];
    return [
      '/usr/local/lib/${_bundledLibName()}',
      '${Platform.environment['HOME']}/.video_forge/${_bundledLibName()}',
    ];
  }

  static String _pathInDir(String dir, String name) {
    final normalized = dir.endsWith('/') ? dir : '$dir/';
    return '$normalized$name';
  }
}

class _LoaderTier {
  _LoaderTier(this.label, this.paths);
  final String label;
  final List<String> paths;
}

class _LoaderLog {
  final List<String> _entries = [];

  void logMatch(String path) {
    _entries.add('  + $path');
  }

  void logMiss(String path) {
    if (kDebugMode) {
      _entries.add('  - $path');
    }
  }

  void logCandidate(String path, Object error) {
    _entries.add('  ! $path → ${_shortError(error)}');
  }

  String snapshot() => _entries.join('\n');

  String _shortError(Object e) {
    final s = e.toString();
    return s.length > 200 ? '${s.substring(0, 200)}…' : s;
  }
}
