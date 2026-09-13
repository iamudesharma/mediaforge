# Native toolchain (media_forge)

Expected toolchain for reproducible native builds. A local Homebrew
installation is never a required build input (§17).

## Pinned versions

| Component | Pinned version | Where |
| --- | --- | --- |
| FFmpeg bundle | 8.0 (VideoToolbox, static default) | `scripts/build-ffmpeg-macos-vt.sh` (`FFMPEG_VERSION`) |
| Rust `ffmpeg-next` | 8.1.0 (`static` feature) | `packages/media_forge/rust/Cargo.toml` |
| Rust `flutter_rust_bridge` | =2.13.0 (codegen + runtime + Dart) | `rust/Cargo.toml`, `flutter_rust_bridge.yaml`, `pubspec.yaml` |
| Dart/Flutter | SDK ^3.12.0, Flutter >=3.3.0 | package `pubspec.yaml` files |
| Xcode clang | via `xcrun` (SDKROOT/CC auto-detected) | `hook/build.dart` `_cargoEnvironment` |
| macOS deployment | 12.0 (native lib) | `hook/build.dart` `MACOSX_DEPLOYMENT_TARGET` |
| iOS deployment (pixel_surface) | 15.0 | `pixel_surface/ios/pixel_surface.podspec` |
| Android | minSdk 21, compileSdk 35, Kotlin 2.1.0, AGP 8.7.3 | `pixel_surface/android/build.gradle` |

`Cargo.lock` (`packages/media_forge/rust/Cargo.lock` is git-ignored by
default in this workspace — the `Cargo.toml` pins above are the source of
truth) and `pubspec.lock` at the workspace root lock the remainder. FRB
codegen, Rust crates and the Dart runtime must stay on the same FRB
version (see commit `c034d1b`).

## The only FFmpeg source

The intended bundled/static FFmpeg is the only FFmpeg source:

* macOS/iOS: `~/.cache/rust_image/ffmpeg-macos-vt-static`
  (symlinked from `tools/ffmpeg/dist/macos-vt-static`), built by
  `scripts/build-ffmpeg-macos-vt.sh` (static default, `--disable-xlib`,
  Homebrew isolated via empty `PKG_CONFIG_PATH` during configure).
* `hook/build.dart` sets `FFMPEG_DIR` to the static prefix first and
  **strips every Homebrew entry** from `PKG_CONFIG_PATH` / `LIBRARY_PATH`
  (`_sanitizeAppleBuildEnv`). Stale Homebrew search paths previously leaked
  a foreign FFmpeg 7.x whose `.pc` files request unavailable `libstdc++`
  (macOS uses `libc++`) — that link failure is now impossible when the
  static prefix is selected.
* `cargo test` / manual Rust builds must export the same env:
  ```bash
  export FFMPEG_DIR="$HOME/.cache/rust_image/ffmpeg-macos-vt-static"
  export PKG_CONFIG_PATH="$FFMPEG_DIR/lib/pkgconfig"
  cargo test -p media_forge
  ```

## Verify hermeticity

```bash
# No Homebrew references may remain in the static prefix:
grep -r '/opt/homebrew' ~/.cache/rust_image/ffmpeg-macos-vt-static/lib/pkgconfig/ || echo "hermetic"
# No libstdc++ request (unavailable on macOS):
grep -r 'lstdc++' ~/.cache/rust_image/ffmpeg-macos-vt-static/lib/pkgconfig/ && echo "FAIL" || echo "ok"
# Bundled binary has no absolute-path dylib deps (sandbox-safe):
otool -L <libmedia_forge.dylib> | grep -v '/usr/lib' | grep -v '/System'
```

## Rebuilding FFmpeg

```bash
bash scripts/build-ffmpeg-macos-vt.sh            # static (default, shippable)
FFMPEG_SHARED=1 bash scripts/build-ffmpeg-macos-vt.sh   # shared (dev only)
```

The script now isolates `PKG_CONFIG_PATH` from Homebrew by default
(`FFMPEG_KEEP_HOMEBREW=1` opts back in), passes `--disable-xlib
--disable-sdl2 --disable-libxcb*`, bumps the configure stamp to force a
clean rebuild, and verifies `.pc` hermeticity after install.
