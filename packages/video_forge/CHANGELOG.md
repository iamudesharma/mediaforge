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
