## 1.0.0

- **Renamed from `rust_gpu_texture` to `pixel_surface`** — a proper pub.dev package name.
- Initial pub.dev release: Flutter GPU texture bridge.
- `GpuTextureRegistry.createTexture`, `updateTexture`, `presentPixelBuffer`, `decodePreviewToSurface`.
- `GpuTextureView` widget for GPU-resident frame display.
- Android (API 21+) via `SurfaceTexture`, iOS 12+ / macOS 12+ via `CVPixelBuffer`.
- Breaking change: package import path changed from `package:rust_gpu_texture` to `package:pixel_surface`.

## 0.1.1

- `GpuTextureRegistry.presentPixelBuffer` — blit VT decode buffer into IOSurface/Metal-compatible texture backing (fixes Flutter `CVReturn -6660`).
- **V1.6 (video):** `GpuTextureRegistry.decodePreviewToSurface` — Android MediaCodec → Flutter `SurfaceTexture` (`AndroidPreviewDecoder.kt`).
- Android: migrate to `TextureRegistry.SurfaceProducer` + `scheduleFrame()` (Flutter 3.27+; `markTextureFrameAvailable` removed).
- `kCVPixelBufferMetalCompatibilityKey` on texture allocation.

## 0.1.0

- Initial release: Flutter `Texture` bridge (macOS, iOS, Android).
- `GpuTextureRegistry` + `GpuTextureView`; method channel `pixel_surface/texture`.
- Example app: animated RGBA gradient without `rust_image_core` (P0.2 / P0.6).
