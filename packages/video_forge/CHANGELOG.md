## 2.0.0

### Breaking
- **Renamed `VideoProcessorError` → `VideoForgeError`** to match the package name.
  Affected classes (also renamed): `VideoProcessorError_*` → `VideoForgeError_*`.
  One-release shim: a `pub type VideoProcessorError = VideoForgeError;` is kept
  in Rust and a `typedef VideoProcessorError = VideoForgeError;` in Dart
  (imported via `package:video_forge/video_forge.dart`); both emit
  deprecation warnings and will be removed in 2.1.0.

### Cleanup / packaging
- Removed stale `android/src/main/jniLibs/arm64-v8a/libvideo_processor_core.so`
  (leftover from the pre-1.0 `video_processor_core` package).
- Removed stale IDE module files (`flutter_video_processor_android.iml`,
  `melos_video_processor_core_example.iml`).
- Added `target/` and `build/` to the package `.gitignore`.
- iOS framework `CFBundleIdentifier` switched to reverse-DNS
  `dev.iamudesharma.video_forge` (was `dev.video_forge`, which clashed with
  the macOS framework when both were linked into the same app).
- macOS Flutter `CodeAsset` hook now **fails the build** when `cargo build`
  cannot produce the cdylib, instead of silently producing no asset and
  leaving the user to discover the failure at runtime.
- `NativeLibraryLoader` collapses the 13 candidate search paths into 3
  ordered tiers and logs which one matched (`[NativeLibraryLoader] matched=`).
  Final error message now includes the last concrete exception per tier.

### CI / tests
- Added a `flutter test test/` step for `video_forge` in both
  `test_all.sh` and `.github/workflows/ci.yml` (was previously
  covered only for `video_forge_kit`).

## 1.0.0

- **Renamed from `video_processor_core` to `video_forge`** — a proper pub.dev package name.
- Initial pub.dev release: Rust video processing engine for Flutter.
- FFmpeg-based compress, transcode, thumbnails, audio mixing.
- FRB bindings for all Rust APIs. Zero Flutter-package dependencies.
- Breaking change: package import path changed from `package:video_processor_core` to `package:video_forge`.

## 0.2.0

- Split from monolithic `video_forge_kit` as engine-only package (FRB + FFmpeg hook).
- Android hook: stop preferring stale `android/src/main/jniLibs` (fixes FRB content-hash mismatch vs Dart).
- `decodePreviewFrameRgba` — single-frame RGBA preview decode for texture upload (Sprint V1.1).
- `decodePreviewFramePixelBuffer` / `releasePreviewPixelBuffer` — Apple VideoToolbox → BGRA `CVPixelBuffer` (Sprint V1.4).

## 0.1.0

- Initial release as part of `video_forge_kit` monolith.
