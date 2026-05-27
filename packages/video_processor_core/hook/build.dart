import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:path/path.dart' as p;

/// Bundles `libvideo_processor_core` for the active Flutter build target.
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
        'ios/Frameworks/video_processor_core.framework/video_processor_core',
      );
      if (await File(frameworkBin).exists()) {
        output.dependencies.add(Uri.file(frameworkBin));
        return;
      }
    }

    const assetName = 'video_processor_core';
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
      stderr.writeln(
        'video_processor_core: no $libFileName for $triple — skipped.\n'
        'Android: scripts/package-video-android.sh (or run-android.sh)\n'
        'iOS: ./scripts/run-ios.sh',
      );
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
      ? '@rpath/video_processor_core.framework/video_processor_core'
      : '@rpath/libvideo_processor_core.dylib';
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
    if (os == OS.macOS)
      p.join(
        packageRoot.toFilePath(),
        'rust/target/release/libvideo_processor_core.dylib',
      ),
    if (os == OS.iOS)
      p.join(
        packageRoot.toFilePath(),
        'ios/Frameworks/video_processor_core.framework/video_processor_core',
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

  for (final path in candidates) {
    if (await File(path).exists()) {
      return path;
    }
  }
  return null;
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
  final env = Map<String, String>.from(Platform.environment);

  if (os == OS.android) {
    final abi = _androidAbiFolder(arch)!;
    final ffmpegCandidates = [
      env['FFMPEG_DIR'],
      p.join(workspaceRoot.toFilePath(), 'rust video/tools/ffmpeg/dist/android', abi),
      p.join(workspaceRoot.toFilePath(), 'tools/video/ffmpeg/dist/android', abi),
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
      'video_processor_core',
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
    OS.windows => 'video_processor_core.dll',
    OS.macOS || OS.iOS => 'libvideo_processor_core.dylib',
    _ => 'libvideo_processor_core.so',
  };
}
