## 0.2.0

- Split from monolithic `flutter_video_processor` as engine-only package (FRB + FFmpeg hook).
- Android hook: stop preferring stale `android/src/main/jniLibs` (fixes FRB content-hash mismatch vs Dart).
- `decodePreviewFrameRgba` — single-frame RGBA preview decode for texture upload (Sprint V1.1).
- `decodePreviewFramePixelBuffer` / `releasePreviewPixelBuffer` — Apple VideoToolbox → BGRA `CVPixelBuffer` (Sprint V1.4).

## 0.1.0

- Initial release as part of `flutter_video_processor` monolith.
