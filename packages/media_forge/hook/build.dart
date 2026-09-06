import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:path/path.dart' as p;

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
    const assetName = 'media_forge';
    final libFileName = _libFileName(os);
    final workspaceRoot = packageRoot.resolve('../../');
    final outDir = input.outputDirectoryShared.resolve('rust_hook');

    var libPath = await _findExistingLibrary(
      packageRoot: packageRoot,
      workspaceRoot: workspaceRoot,
      triple: triple,
      os: os,
      libFileName: libFileName,
    );
    if (libPath != null &&
        await _isRustLibraryStale(libPath, packageRoot: packageRoot)) {
      stderr.writeln(
        'media_forge: $libFileName is older than Rust sources — rebuilding',
      );
      libPath = null;
    }
    libPath ??= await _cargoBuild(
      packageRoot: packageRoot,
      workspaceRoot: workspaceRoot,
      outDir: outDir,
      triple: triple,
      os: os,
      libFileName: libFileName,
    );

    if (libPath == null) {
      stderr.writeln(
        'media_forge: no $libFileName for $triple — skipped.'
      );
      return;
    }

    if (os == OS.iOS || os == OS.macOS) {
      await _fixDarwinInstallName(libPath, os: os);
    }

    final libUri = Uri.file(libPath);
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
      ? '@rpath/media_forge.framework/media_forge'
      : '@rpath/libmedia_forge.dylib';
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
  required String libFileName,
}) async {
  final hookOut = p.join(
    packageRoot.toFilePath(),
    'rust',
    'target',
    'rust_hook',
    triple,
    'release',
    libFileName,
  );
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
    ],
    p.join(
      workspaceRoot.toFilePath(),
      'target',
      triple,
      'release',
      libFileName,
    ),
  ];

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

/// True when any `rust/src/**/*.rs` or `rust/Cargo.toml` is newer than [libPath].
/// Prevents bundling a stale dylib after FRB codegen or API edits (content-hash mismatch).
Future<bool> _isRustLibraryStale(
  String libPath, {
  required Uri packageRoot,
}) async {
  final libFile = File(libPath);
  if (!await libFile.exists()) {
    return false;
  }
  final libModified = await libFile.lastModified();
  final rustDir = Directory(p.join(packageRoot.toFilePath(), 'rust'));
  if (!await rustDir.exists()) {
    return false;
  }

  DateTime? newestSource;
  final manifest = File(p.join(rustDir.path, 'Cargo.toml'));
  if (await manifest.exists()) {
    newestSource = await manifest.lastModified();
  }
  await for (final entity in rustDir.list(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.rs')) {
      continue;
    }
    final modified = await entity.lastModified();
    if (newestSource == null || modified.isAfter(newestSource)) {
      newestSource = modified;
    }
  }
  if (newestSource == null) {
    return false;
  }
  return newestSource.isAfter(libModified);
}

void _applyFfmpegDistEnv(
  Map<String, String> env,
  Uri workspaceRoot,
  String triple,
) {
  if (env.containsKey('FFMPEG_DIR') && env['FFMPEG_DIR']!.isNotEmpty) {
    return;
  }
  final home = Platform.environment['HOME'];
  // Static prefixes FIRST: archives link into the cdylib, leaving no
  // runtime dylib dependency (required for sandboxed/distributed apps —
  // absolute-path .dylib loads are sandbox-blocked). Shared prefixes are
  // a fast-iteration fallback for local dev only.
  final candidates = <String>[
    if (home != null && home.isNotEmpty)
      p.join(home, '.cache', 'rust_image', 'ffmpeg-macos-vt-static'),
    p.join(
      workspaceRoot.toFilePath(),
      'tools',
      'ffmpeg',
      'dist',
      'macos-vt-static',
    ),
    if (home != null && home.isNotEmpty)
      p.join(home, '.cache', 'rust_image', 'ffmpeg-macos-vt'),
    p.join(
      workspaceRoot.toFilePath(),
      'tools',
      'ffmpeg',
      'dist',
      'macos-vt',
    ),
    p.join(
      workspaceRoot.toFilePath(),
      'tools',
      'ffmpeg',
      'dist',
      'apple',
      triple,
    ),
    p.join(
      workspaceRoot.toFilePath(),
      'tools',
      'ffmpeg',
      'dist',
      'macos',
      triple,
    ),
  ];
  for (final dir in candidates) {
    final libDir = Directory(p.join(dir, 'lib'));
    if (!libDir.existsSync()) {
      continue;
    }
    env['FFMPEG_DIR'] = dir;
    final pkgConfig = p.join(dir, 'lib', 'pkgconfig');
    if (Directory(pkgConfig).existsSync()) {
      final existing = env['PKG_CONFIG_PATH'];
      env['PKG_CONFIG_PATH'] = existing == null || existing.isEmpty
          ? pkgConfig
          : '$pkgConfig:$existing';
    }
    final staticLibs = _isStaticFfmpegDir(dir);
    if (staticLibs) {
      // Static archives don't carry their system deps (shared dylibs do
      // via LC_LOAD_DYLIB). avformat/avcodec need these; all /usr/lib
      // system libs, safe under App Sandbox.
      const args = ' -C link-arg=-lbz2 -C link-arg=-lz -C link-arg=-liconv';
      final existing = env['RUSTFLAGS'] ?? '';
      if (!existing.contains('link-arg=-lz')) {
        env['RUSTFLAGS'] = '$existing$args';
      }
    }
    stderr.writeln(
        'media_forge: using FFMPEG_DIR=$dir (static=$staticLibs)');
    if (!staticLibs) {
      stderr.writeln(
        'media_forge: WARNING: shared FFmpeg dylibs load by absolute path '
        'and fail dlopen() in sandboxed/distributed apps. For a shippable '
        'build, run scripts/build-ffmpeg-macos-vt.sh (static default).',
      );
    }
    return;
  }
}

/// True when [dir]/lib holds static archives without shared dylibs.
bool _isStaticFfmpegDir(String dir) {
  final libDir = Directory(p.join(dir, 'lib'));
  if (!libDir.existsSync()) return false;
  var hasArchive = false;
  var hasDylib = false;
  for (final entity in libDir.listSync()) {
    final name = p.basename(entity.path);
    if (name.startsWith('libavcodec.') || name.startsWith('libavutil.')) {
      if (name.endsWith('.a')) hasArchive = true;
      if (name.endsWith('.dylib') || name.contains('.dylib.')) {
        hasDylib = true;
      }
    }
  }
  return hasArchive && !hasDylib;
}

Future<String?> _cargoBuild({
  required Uri packageRoot,
  required Uri workspaceRoot,
  required Uri outDir,
  required String triple,
  required OS os,
  required String libFileName,
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
  if (os == OS.macOS || os == OS.iOS) {
    _applyFfmpegDistEnv(env, workspaceRoot, triple);
    // Explicit FFMPEG_DIR pointing at static archives needs the same
    // system link args (the auto-detect path above already added them).
    final explicit = env['FFMPEG_DIR'];
    if (explicit != null &&
        explicit.isNotEmpty &&
        _isStaticFfmpegDir(explicit)) {
      const args = ' -C link-arg=-lbz2 -C link-arg=-lz -C link-arg=-liconv';
      final existing = env['RUSTFLAGS'] ?? '';
      if (!existing.contains('link-arg=-lz')) {
        env['RUSTFLAGS'] = '$existing$args';
      }
      stderr.writeln(
          'media_forge: static FFMPEG_DIR detected, added system link args');
    } else if (explicit != null && explicit.isNotEmpty) {
      stderr.writeln(
        'media_forge: WARNING: explicit FFMPEG_DIR=$explicit is shared; '
        'the bundled binary will fail dlopen() in sandboxed apps. '
        'Use a static prefix (scripts/build-ffmpeg-macos-vt.sh).',
      );
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
      'media_forge',
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
  if (Platform.isMacOS || Platform.isIOS) {
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

String _libFileName(OS os) {
  return switch (os) {
    OS.windows => 'media_forge.dll',
    OS.macOS || OS.iOS => 'libmedia_forge.dylib',
    _ => 'libmedia_forge.so',
  };
}
