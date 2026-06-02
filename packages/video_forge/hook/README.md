# Native build hook (optional)

For Flutter native assets / `native_toolchain_rust`, restore `hook/build.dart` using the template in [docs/setup.md](../../docs/setup.md).

Default builds use:

- **Desktop:** Corrosion via `src/CMakeLists.txt`
- **Mobile CI:** `tools/release/package-*.sh`
- **Local dev:** `cargo build --release -p video_forge`

## Framework identity (iOS / macOS)

The vendored iOS framework uses reverse-DNS bundle identifier
`dev.iamudesharma.video_forge` (was `dev.video_forge` in `1.x`). When the
hook builds a fresh cdylib, `_fixDarwinInstallName` rewrites the binary's
`LC_ID_DYLIB` to `@rpath/video_forge.framework/video_forge` so the dynamic
loader resolves it correctly. If you ship a prebuilt framework from
`ios/Frameworks/video_forge.framework/`, run the same `install_name_tool`
step yourself (see `scripts/run-ios.sh`) — otherwise the binary's stored
install name will not match the linker expectations and the loader will
fail with "image not found".

## Failure semantics (macOS / iOS)

Since `2.0.0`, the hook **throws** (i.e. fails the Flutter build) when it
cannot produce the cdylib for macOS or iOS. On Android it still tolerates
a missing asset because the recommended Android path is
`scripts/package-video-android.sh` which prebuilds jniLibs before the
Flutter hook runs.
