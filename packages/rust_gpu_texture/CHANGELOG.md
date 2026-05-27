## 0.1.1

- `GpuTextureRegistry.presentPixelBuffer` — blit VT decode buffer into IOSurface/Metal-compatible texture backing (fixes Flutter `CVReturn -6660`).
- **V1.6 (video):** `GpuTextureRegistry.decodePreviewToSurface` — Android MediaCodec → Flutter `SurfaceTexture` (`AndroidPreviewDecoder.kt`).
- Android: migrate to `TextureRegistry.SurfaceProducer` + `scheduleFrame()` (Flutter 3.27+; `markTextureFrameAvailable` removed).
- `kCVPixelBufferMetalCompatibilityKey` on texture allocation.

## 0.1.0

- Initial release: Flutter `Texture` bridge (macOS, iOS, Android).
- `GpuTextureRegistry` + `GpuTextureView`; method channel `rust_gpu_texture/texture`.
- Example app: animated RGBA gradient without `rust_image_core` (P0.2 / P0.6).
