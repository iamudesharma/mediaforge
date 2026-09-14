## Unreleased

- New `enhance` module (feature `gpu`, Apple): GPU video enhancement /
  upscaling between hardware decode and presentation.
  - `EnhancementMode` (`off` / `sharp` / `enhanced` / `highQuality`),
    `EnhancementBackend` trait, `create_backend()` (never fails — reports
    `supported == false` instead), `EnhancementCapabilities`, `FrameHandle`.
  - `enhance::plan` — resolution-aware target planning: preserves aspect ratio,
    never downscales, caps output per mode, and bypasses 4K-class sources that
    are shown smaller than they are.
  - `enhance::policy` — deadline-aware quality ladder with anti-oscillation
    hysteresis (steps down under load, back up only after a long clean window).
  - `enhance::metal` — wgpu-over-Metal backend: up to three compute passes
    (separable Catmull-Rom or Lanczos-3 upscale, then contrast-adaptive sharpen
    plus dither) writing straight into an IOSurface-backed `CVPixelBuffer`.
    Output surfaces are pooled in a 3-deep ring; the shader works in logical
    RGBA on `bgra8unorm` textures, so there is no CPU copy and no channel
    swizzle round-trip.
  - `metal_iosurface::metal_texture_view_for_pixel_buffer` — Metal view of an
    existing BGRA `CVPixelBuffer` (the decode IOSurface) without taking over
    the caller's retain.
  - `metal_iosurface::create_bgra_iosurface_pixel_buffer_metal` — output
    surface with explicit IOSurface + `kCVPixelBufferMetalCompatibilityKey`
    attributes so Flutter adopts it without a CPU copy.
  - `metal_iosurface::with_bgra_pixels` / `with_bgra_pixels_mut` — diagnostic
    locked access to a BGRA surface.
  - New bin `enhance_bench` (`cargo run --release --features gpu --bin
    enhance_bench`) measuring the stage across the resolution matrix.
- Fixed: `CVMetalTextureCacheCreateTextureFromImage` was passed a CoreVideo
  pixel format (`'BGRA'`) where an `MTLPixelFormat` is required, which aborted
  inside `MTLDebugValidateMTLPixelFormat`. Now uses
  `MTLPixelFormatBGRA8Unorm` (both call sites).
- Fixed: `CvMetalTexture::clone_metal_texture` built a `metal::Texture` with
  `from_ptr` (which does **not** retain) while its `Drop` releases, producing a
  dangling `MTLTexture` and a double release. It now uses the clone the
  `foreign_obj_type!` macro generates (`retain` on clone).
- iOS deployment target lowered 16.0 → 15.0 (audited: no iOS 16+ API used;
  see `IOS15_COMPATIBILITY.md`). PeerStream (iOS 15) consumes without changes.

## 1.1.0-dev.1

- Pre-release aligned with **Flutter 3.47.0** (Dart 3.13.0) verification.
- Document minimum Flutter **3.27.0** (`TextureRegistry.SurfaceProducer` + `scheduleFrame()`).

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
