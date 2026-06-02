import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:path/path.dart' as p;

/// Bundles `libvideo_forge` for the active Flutter build target.
///
/// Android: prefer jniLibs when `VFP_USE_PREBUILT_JNI=1` (see `scripts/run-android.sh`).
/// Hook cargo-build needs NDK linkers; use `scripts/package-video-android.sh` for device runs.
void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) {
      return;
    }

    final code = input.config.code;
    final os = code.targetOS;
    final arch = code.targetArchitecture;
    final triple = _rustTriple(os, arch);
    if (triple == null) {
      return;
    }

    final packageRoot = input.packageRoot;

    // iOS: CocoaPods vendored_frameworks — do not also bundle a CodeAsset dylib.
    if (os == OS.iOS) {
      final frameworkBin = p.join(
        packageRoot.toFilePath(),
        'ios/Frameworks/video_forge.framework/video_forge',
      );
      if (await File(frameworkBin).exists()) {
        output.dependencies.add(Uri.file(frameworkBin));
        return;
      }
    }

    const assetName = 'video_forge';
    final libFileName = _libFileName(os);
    final workspaceRoot = packageRoot.resolve('../../');
    final outDir = input.outputDirectoryShared.resolve('rust_hook');

    final libPath = await _findExistingLibrary(
      packageRoot: packageRoot,
      workspaceRoot: workspaceRoot,
      triple: triple,
      os: os,
      arch: arch,
      libFileName: libFileName,
    ) ??
        await _cargoBuild(
          packageRoot: packageRoot,
          workspaceRoot: workspaceRoot,
          outDir: outDir,
          triple: triple,
          os: os,
          arch: arch,
          libFileName: libFileName,
          ndkApi: os == OS.android ? code.android.targetNdkApi : 24,
        );

    if (libPath == null) {
      // Fail loud: on macOS, a missing cdylib at this stage used to mean the
      // app would build but crash at runtime with a generic
      // "library not found" error. Surface the failure as a build error so
      // devs and CI see it immediately. Android still tolerates a missing
      // asset because the recommended path is to prebuild jniLibs with
      // scripts/package-video-android.sh, then the hook only runs on hosts
      // with the NDK toolchain.
      final message =
          'video_forge: failed to produce $libFileName for $triple.\n'
          'Either install the matching Rust target with `rustup target add $triple`,\n'
          'point FFMPEG_DIR at a compatible FFmpeg build (see tools/ffmpeg/),\n'
          'or run the platform prebuild script:\n'
          '  macOS: ./scripts/run-video-macos.sh\n'
          '  iOS:   ./scripts/run-ios.sh\n'
          '  Android: ./scripts/package-video-android.sh (or run-android.sh)';
      stderr.writeln(message);
      if (os == OS.macOS || os == OS.iOS) {
        throw StateError(message);
      }
      return;
    }

    if (os == OS.iOS || os == OS.macOS) {
      await _fixDarwinInstallName(libPath, os: os);
    }

    final libUri = Uri.file(libPath);
    // Bundle via CodeAsset only. Do not copy into android/src/main/jniLibs here —
    // that directory is merged by AGP and must not be an output of compileFlutterBuild
    // (Gradle 9 implicit-dependency error). Pre-build with package-android.sh instead.
    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: assetName,
        linkMode: DynamicLoadingBundled(),
        file: libUri,
      ),
    );

    output.dependencies.add(libUri);
  });
}

Future<void> _fixDarwinInstallName(String libPath, {required OS os}) async {
  if (!Platform.isMacOS) {
    return;
  }
  final id = os == OS.iOS
      ? '@rpath/video_forge.framework/video_forge'
      : '@rpath/libvideo_forge.dylib';
  final result = await Process.run('install_name_tool', ['-id', id, libPath]);
  if (result.exitCode != 0) {
    stderr.writeln(
      'install_name_tool warning: ${result.stderr}',
    );
  }
}

Future<String?> _findExistingLibrary({
  required Uri packageRoot,
  required Uri workspaceRoot,
  required String triple,
  required OS os,
  required Architecture arch,
  required String libFileName,
}) async {
  final abi = _androidAbiFolder(arch);
  final hookOut = p.join(
    packageRoot.toFilePath(),
    'rust',
    'target',
    'rust_hook',
    triple,
    'release',
    libFileName,
  );
  // Do not use android/src/main/jniLibs here — stale copies cause FRB content-hash
  // mismatches (Dart regenerated, .so not rebuilt). Prebuild with package-android.sh
  // only when you intentionally refresh jniLibs; Flutter hook always cargo-builds.
  final candidates = <String>[
    hookOut,
    if (os == OS.macOS) ...[
      p.join(
        packageRoot.toFilePath(),
        'target',
        triple,
        'release',
        libFileName,
      ),
      p.join(
        packageRoot.toFilePath(),
        'macos/Frameworks/video_forge.framework/Versions/A/video_forge',
      ),
    ],
    if (os == OS.iOS)
      p.join(
        packageRoot.toFilePath(),
        'ios/Frameworks/video_forge.framework/video_forge',
      ),
    p.join(
      workspaceRoot.toFilePath(),
      'target',
      triple,
      'release',
      libFileName,
    ),
    if (abi != null && Platform.environment['VFP_USE_PREBUILT_JNI'] == '1')
      p.join(
        packageRoot.toFilePath(),
        'android/src/main/jniLibs',
        abi,
        libFileName,
      ),
  ];

  // Pick the newest artifact so stale rust_hook / jniLibs copies cannot win after
  // `flutter_rust_bridge_codegen` (FRB content-hash mismatch vs Dart).
  String? newestPath;
  DateTime? newestModified;
  for (final path in candidates) {
    final file = File(path);
    if (!await file.exists()) {
      continue;
    }
    final modified = await file.lastModified();
    if (newestModified == null || modified.isAfter(newestModified)) {
      newestModified = modified;
      newestPath = path;
    }
  }
  return newestPath;
}

Future<String?> _cargoBuild({
  required Uri packageRoot,
  required Uri workspaceRoot,
  required Uri outDir,
  required String triple,
  required OS os,
  required Architecture arch,
  required String libFileName,
  required int ndkApi,
}) async {
  final manifest = p.join(packageRoot.toFilePath(), 'rust', 'Cargo.toml');
  if (!await File(manifest).exists()) {
    return null;
  }
  final cargoWorkspace = p.join(
    packageRoot.toFilePath(),
  );

  await Directory(outDir.toFilePath()).create(recursive: true);
  final env = _cargoEnvironment();

  if (os == OS.android) {
    final abi = _androidAbiFolder(arch)!;
    final ffmpegCandidates = [
      env['FFMPEG_DIR'],
      p.join(workspaceRoot.toFilePath(), 'tools/ffmpeg/dist/android', abi),
    ];
    String? ffmpegDir;
    for (final c in ffmpegCandidates) {
      if (c != null && await Directory(c).exists()) {
        ffmpegDir = c;
        break;
      }
    }
    if (ffmpegDir != null) {
      env['FFMPEG_DIR'] = ffmpegDir;
      env['PKG_CONFIG_PATH'] = p.join(ffmpegDir, 'lib/pkgconfig');
    }
  }

  final result = await Process.run(
    'cargo',
    [
      'build',
      '--release',
      '--manifest-path',
      manifest,
      '-p',
      'video_forge',
      '--target',
      triple,
      '--target-dir',
      outDir.toFilePath(),
    ],
    workingDirectory: cargoWorkspace,
    environment: env,
  );

  if (result.exitCode != 0) {
    final err = result.stderr;
    if (err is String) {
      stderr.write(err);
    } else if (err is List<int>) {
      stderr.write(String.fromCharCodes(err));
    }
    return null;
  }

  final built = p.join(outDir.toFilePath(), triple, 'release', libFileName);
  return await File(built).exists() ? built : null;
}

/// Prefer rustup over Homebrew rustc (breaks macOS cross-target / FRB builds).
Map<String, String> _cargoEnvironment() {
  final env = Map<String, String>.from(Platform.environment);
  final home = Platform.environment['HOME'];
  if (home == null) {
    return env;
  }
  final cargoBin = p.join(home, '.cargo', 'bin');
  if (!Directory(cargoBin).existsSync()) {
    return env;
  }
  final sep = Platform.isWindows ? ';' : ':';
  final path = env['PATH'] ?? '';
  if (!path.split(sep).contains(cargoBin)) {
    env['PATH'] = '$cargoBin$sep$path';
  }
  if (Platform.isMacOS) {
    final sdk = env['SDKROOT'];
    if (sdk == null || sdk.isEmpty) {
      final sdkResult = Process.runSync('xcrun', ['--sdk', 'macosx', '--show-sdk-path']);
      if (sdkResult.exitCode == 0) {
        env['SDKROOT'] = (sdkResult.stdout as String).trim();
      }
    }
    env['MACOSX_DEPLOYMENT_TARGET'] ??= '12.0';
    if (env['CC'] == null || env['CC']!.isEmpty) {
      final ccResult = Process.runSync('xcrun', ['--sdk', 'macosx', '--find', 'clang']);
      if (ccResult.exitCode == 0) {
        env['CC'] = (ccResult.stdout as String).trim();
      }
    }
    if (env['CXX'] == null || env['CXX']!.isEmpty) {
      final cxxResult = Process.runSync('xcrun', ['--sdk', 'macosx', '--find', 'clang++']);
      if (cxxResult.exitCode == 0) {
        env['CXX'] = (cxxResult.stdout as String).trim();
      }
    }
  }
  return env;
}

String? _rustTriple(OS os, Architecture arch) {
  return switch ((os, arch)) {
    (OS.android, Architecture.arm64) => 'aarch64-linux-android',
    (OS.android, Architecture.arm) => 'armv7-linux-androideabi',
    (OS.android, Architecture.x64) => 'x86_64-linux-android',
    (OS.android, Architecture.ia32) => 'i686-linux-android',
    (OS.iOS, Architecture.arm64) => 'aarch64-apple-ios',
    (OS.iOS, Architecture.x64) => 'x86_64-apple-ios',
    (OS.macOS, Architecture.arm64) => 'aarch64-apple-darwin',
    (OS.macOS, Architecture.x64) => 'x86_64-apple-darwin',
    (OS.linux, Architecture.arm64) => 'aarch64-unknown-linux-gnu',
    (OS.linux, Architecture.x64) => 'x86_64-unknown-linux-gnu',
    (OS.windows, Architecture.x64) => 'x86_64-pc-windows-msvc',
    (OS.windows, Architecture.ia32) => 'i686-pc-windows-msvc',
    _ => null,
  };
}

String? _androidAbiFolder(Architecture arch) {
  return switch (arch) {
    Architecture.arm64 => 'arm64-v8a',
    Architecture.arm => 'armeabi-v7a',
    Architecture.x64 => 'x86_64',
    Architecture.ia32 => 'x86',
    _ => null,
  };
}

String _libFileName(OS os) {
  return switch (os) {
    OS.windows => 'video_forge.dll',
    OS.macOS || OS.iOS => 'libvideo_forge.dylib',
    _ => 'libvideo_forge.so',
  };
}
