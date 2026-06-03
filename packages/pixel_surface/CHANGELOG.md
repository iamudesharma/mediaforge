## 1.0.0

- Initial pub.dev release of `pixel_surface` — Flutter GPU texture bridge for native Rust pipelines and custom renderers. Renamed from `rust_gpu_texture` to a proper pub.dev package name.
- `GpuTextureRegistry` static API: `createTexture`, `updateTexture` (RGBA), `updateTextureBgra` (BGRA — single `memcpy` on Apple, `Bitmap.copyPixelsFromBuffer` on Android), `presentPixelBuffer` (zero-copy blit of VT decode buffer into IOSurface/Metal-compatible texture backing), `decodePreviewToSurface` (Android MediaCodec → Flutter `SurfaceTexture`).
- `GpuTextureView` widget for GPU-resident frame display.
- Texture recycling: `PixelBufferPool` on Apple keyed by `(width, height, pixelFormat)` with 3 warm buffers per bucket (1 s age limit). `GpuTextureRegistry.resizeTexture` and `flushPools` for cross-platform memory pressure handling. `CVMetalTextureCache` flushed with the pool.
- Memory-pressure hooks: Apple `UIApplication.didReceiveMemoryWarningNotification` (iOS), `ProcessInfo.thermalStateDidChangeNotification` + `NSApplication.didResignActiveNotification` (macOS) call `pool.flushAll()`. Android `ComponentCallbacks2.onTrimMemory` (`RUNNING_MODERATE` / `RUNNING_LOW` / `RUNNING_CRITICAL` / `UI_HIDDEN` / `BACKGROUND` / `MODERATE` / `COMPLETE`) recycles the backing `Bitmap`. Backing bitmaps re-created on the next `updateTexture`.
- New Dart API: `GpuTextureRegistry.resizeTexture`, `GpuTextureRegistry.flushPools`, `GpuTextureRegistry.debugStats()` → `PixelSurfaceStats` (`handleCount`, `poolCount`, `createCount`, `lastFlushMs`, `lastMemoryWarningMs`, `trimEventCount`, `recycledBitmapCount`, `lastTrimLevel`).
- `PixelLayout` enum (`rgba8888` / `bgra8888`) with safe `BGRA8Unorm` + 2D assertions in debug builds.
- `BeautyOutputTarget` typed wrapper for safely adopting a Flutter-side `CVPixelBuffer` + `MTLTexture` pointer pair into a wgpu pipeline (`unsafe fn BeautyOutputTarget::from_adopted`, validates non-null + dimension match, takes exactly one `+1` retain, imports via `wrap_metal_texture_as_wgpu_bgra`).
- RAII `CvMetalTexture` wrapper (closes a one-time `CVMetalTexture` leak per allocation) and `MetalTextureCacheEntry` with `Drop` (flushes + releases the cache on device change).
- iOS uses `vImagePermuteChannels_ARGB8888` for the RGBA path; `Accelerate.framework` declared in both podspecs.
- Android plugin (API 26+, Android 8.0+) uses `Bitmap.copyPixelsFromBuffer` for RGBA + BGRA; the API 21-25 fallback keeps the legacy path. `kCVPixelBufferMetalCompatibilityKey` set on texture allocation.
- Method channel: `pixel_surface/texture`. Migrated to `TextureRegistry.SurfaceProducer` + `scheduleFrame()` (Flutter 3.27+; `markTextureFrameAvailable` removed).

### Platform support
- Android (API 21+, `SurfaceTexture`)
- iOS (12+, `CVPixelBuffer`)
- macOS (12+, `CVPixelBuffer`)
- Linux / Windows / Web: not supported — use an RGBA widget fallback in your app
