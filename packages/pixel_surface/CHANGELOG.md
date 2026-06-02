## 1.1.0

- **Rust crate `Cargo.toml` hardened.**
  - Single unified `wgpu` dependency gated on `target_vendor = "apple"` with the `metal` backend feature. The previous dual-declaration (`[dependencies.wgpu]` + `[target.apple.dependencies.wgpu]`) is gone, removing a class of cargo feature-merging surprises.
  - `gpu` feature now hard-fails on non-Apple targets via `compile_error!` instead of silently producing a no-op build.
  - `pub use wgpu;` and `pub use metal;` re-exports under `apple + gpu` so downstream crates (e.g. `image_forge`) can depend on the same pinned wgpu version as `pixel_surface`, eliminating version-skew across crate boundaries.
- **CPU pixel swizzle removed on the fast path.**
  - New `PixelLayout` enum + `GpuTextureRegistry.updateTextureBgra` (Dart) and matching `updateTexture` `layout` argument. The BGRA path does a single row-wise `memcpy` on Apple (no vImage call) and a direct `Bitmap.copyPixelsFromBuffer` on Android — no channel swap.
  - iOS plugin now uses `vImagePermuteChannels_ARGB8888` for the RGBA path with the same parity as macOS (the previous iOS-only scalar `for x in 0..<width` loop is gone). `Accelerate.framework` is now declared in both podspecs.
  - iOS/macOS `darwin/Classes/RustGpuTexturePlugin.swift` is now the single source of truth; the drifted duplicates under `macos/Classes/Darwin/` and `ios/Classes/Darwin/` have been removed (the podspec `prepare_command` already rsyncs them at pod-install time).
  - Android plugin (API 26+, Android 8.0+) replaces `IntArray` + `Bitmap.setPixels` + `Canvas.drawBitmap` round-trips with `Bitmap.copyPixelsFromBuffer` (a native `memcpy`) for RGBA and a 32-bit word swap + `copyPixelsFromBuffer` for BGRA. The API 21–25 fallback keeps the legacy path (the only path available pre-O).
  - `updateTexture` is now a back-compat alias for `updateTextureRgba`; downstream callers keep working unchanged.
- **Metal texture ownership / lifetime hardening (Apple).**
  - New `CvMetalTexture` RAII wrapper owns the `+1` retain on the `CVMetalTextureRef` returned by `CVMetalTextureCacheCreateTextureFromImage`. The previous code created the `metal::Texture` from the unretained `MTLTexture*` and **leaked the `CVMetalTextureRef`** — every allocation was a one-time `CVMetalTexture` leak, and dropping the `IosurfacePixelBuffer` could under-release the underlying `MTLTexture`. The leak is now closed.
  - `MetalTextureCacheEntry` gains a `Drop` that calls `CVMetalTextureCacheFlush` (releasing any pending texture references) followed by `CFRelease(cache)`. The previous struct had no `Drop`, so on device change the previous `CVMetalTextureCache` was leaked.
  - Module-level **retain discipline** comment block enumerates the four ownership rules (factory / reader / adopt_ / RAII). Every entry point and function name has a single, named owner for its `+1`.
  - Safety contracts on `adopt_metal_texture` and `wrap_metal_texture_as_wgpu_bgra` split into five concrete bullets (pointer validity, retain accounting, format match, usage match, device match, borrow lifetime). `wrap_metal_texture_as_wgpu_bgra` adds a `#[cfg(debug_assertions)]` check that the input `MTLTexture` is `BGRA8Unorm` + 2D — caller mistakes now panic in tests instead of silently producing a broken wgpu import.
  - `#![forbid(unsafe_op_in_unsafe_fn)]` at the crate root + `#![warn(clippy::missing_safety_doc)]` on every `unsafe fn`. Inner unsafe calls are wrapped in explicit `unsafe { ... }` blocks.
  - New `pixel_surface::metal_iosurface::DROPPED_PIXEL_BUFFERS` / `DROPPED_METAL_TEXTURES` / `DROPPED_METAL_TEXTURE_CACHES` test instrumentation counters (gated `#[cfg(test)]` for increments) and a `tests/drop_discipline.rs` integration test that exercises the Drop shape — five tests currently, all passing on aarch64-apple-darwin.
- **Texture recycling + memory pressure (1.1.0).**
  - **Apple (Swift):** new `PixelBufferPool` keyed by `(width, height, pixelFormat)` with three warm buffers per bucket (1-second age limit). Every `createTexture` and `presentPixelBuffer` allocation now goes through the pool; resize is a `CVPixelBufferPoolFlush(.excludeNonReusableBuffers)` followed by a fresh `dequeue` — no more full re-allocations on size change. A new `CVMetalTextureCache` is allocated lazily and flushed together with the pool on memory pressure.
  - **Apple memory-warning hooks:** `UIApplication.didReceiveMemoryWarningNotification` (iOS) and `ProcessInfo.thermalStateDidChangeNotification` + `NSApplication.didResignActiveNotification` (macOS) both call `pool.flushAll()` + `CVMetalTextureCacheFlush`. The last warning timestamp is surfaced via `debugStats.lastMemoryWarningMs` so operators can confirm the handler fired.
  - **Android:** the plugin now implements `ComponentCallbacks2`. `onTrimMemory` levels `RUNNING_MODERATE` / `RUNNING_LOW` / `RUNNING_CRITICAL` and `UI_HIDDEN` / `BACKGROUND` / `MODERATE` / `COMPLETE` all recycle the backing `Bitmap` for every handle. Backing bitmaps are lazily re-created on the next `updateTexture` call — the Flutter texture handle survives the trim, only the GPU memory is released. The trim level, count, and total recycled count are surfaced via `debugStats`.
  - **New Dart API (additive, fully back-compat):**
    - `GpuTextureRegistry.resizeTexture({handle, width, height})` — cross-platform resize.
    - `GpuTextureRegistry.flushPools()` — operator-driven flush from Dart (e.g. "release memory" debug action).
    - `GpuTextureRegistry.debugStats()` → `PixelSurfaceStats` value with `handleCount`, `poolCount`, `createCount`, `reuseCount`, `lastFlushMs`, `lastMemoryWarningMs`, `trimEventCount`, `recycledBitmapCount`, `lastTrimLevel`. Parses both Apple and Android shapes via `PixelSurfaceStats.fromMap`.
  - **Logging:** all milestone lines under the `[PixelSurface]` tag — `create handle=… %dx%d id=…`, `present adopted/copied handle=…`, `resize handle=… %dx%d`, `flushPools pools=…`, `memory warning -> flush pools=…`, Android `onTrimMemory level=…` (via `lastTrimLevel` in `debugStats`). Operator-friendly without being high-frequency noise.
- **Safer GPU texture abstraction boundary (1.1.0).**
  - New `pixel_surface::metal_iosurface::BeautyOutputTarget` typed wrapper is the **single safe boundary** for adopting a Flutter-side `CVPixelBuffer` + `MTLTexture` pointer pair into a wgpu pipeline. Constructed via `unsafe fn BeautyOutputTarget::from_adopted(device, mtl_ptr, pb_ptr) -> Option<Self>`, which:
    - Validates `mtl_ptr` + `pb_ptr` are non-null before any retain transfer.
    - Validates the `CVPixelBuffer` and `MTLTexture` dimensions agree; mismatched dimensions return `None` *after* the just-adopted `MTLTexture` is dropped (so no leak on the error path).
    - Takes exactly one `+1` on the `CVPixelBuffer` via `retain_pixel_buffer`.
    - Imports the Metal resource as a wgpu `Texture` via the existing `wrap_metal_texture_as_wgpu_bgra` (with its debug-only `BGRA8Unorm` + 2D assertions).
  - Struct field order (`wgpu_texture` first, `metal_texture` second, `pixel_buffer` last) **guarantees** Rust drops the wgpu import before the `MTLTexture` is released — preventing the use-after-free that the old manual `clone_metal_texture` + `Drop` ordering could trigger. `unsafe impl Send + Sync for BeautyOutputTarget`.
  - `image_forge::surface::OutputTexture` collapsed from a leaky four-field struct (with `dead_code` warnings on three of the fields) into a two-variant `enum`:
    - `OutputTexture::Adopted(BeautyOutputTarget)` — production path; owns the +1 retains via the new safe wrapper.
    - `OutputTexture::Benchmark { wgpu_texture, width, height }` — benchmark path; no Flutter backing, no Core Foundation retains to manage.
  - `attach_output_texture` shrank from a 50-line manual `retain_pixel_buffer` + `adopt_metal_texture` + dimension check + `wrap_metal_texture_as_wgpu_bgra` dance into a 30-line call to `BeautyOutputTarget::from_adopted` with a single post-check. The retain-balance invariant is now **enforced in one place** rather than spread across two crates.
  - New `tests/drop_discipline.rs::beauty_output_target_is_send_sync` compile-time tripwire — future field changes that would break the `Send + Sync` contract now break the test, not the user.
- **Swift XCTest coverage (1.1.0).**
  - `PixelBufferPool` extracted from `RustGpuTexturePlugin.swift` into a dedicated `darwin/Classes/PixelBufferPool.swift` file with default (`internal`) Swift access. The plugin's `PixelBufferPool` is no longer private; the new test target can `@testable import pixel_surface` and exercise it directly.
  - New `darwin/Tests/PixelBufferPoolTests.swift` with 7 XCTest cases covering bucket creation, dequeue counting, `flushAll` / `flushNonReusable` idempotency, snapshot shape, and `Key` hashability. All pass on both `pod lib lint` iOS and macOS.
  - Both `ios/pixel_surface.podspec` and `macos/pixel_surface.podspec`:
    - Bumped `s.version` from `1.0.0` → `1.1.0` (the in-podspec version had drifted from `pubspec.yaml` since the rename).
    - `s.prepare_command` now also rsyncs `../darwin/Tests/` → `Tests/` (in addition to the existing `Classes/` rsync).
    - New `s.test_spec 'Tests' do |test_spec| … end` block; `requires_app_host = false` so the test target runs as a logic test (no Flutter engine needed for `PixelBufferPool` itself).
  - **Latent bugs caught + fixed by `pod lib lint` (not caught by the previous `flutter test` or `cargo test` runs):**
    - `CVPixelBufferPoolFlushFlags.excludeNonReusableBuffers` is not a real Swift name — the bridging is `CVPixelBufferPoolFlushFlags()` (empty option set = "flush all"). Both `PixelBufferPool.flushAll` and `flushNonReusable` now use the correct API.
    - `UploadLayout` enum cases are `.rgba8888` / `.bgra8888` (matching the Dart `PixelLayout` `name`), not `.rgba` / `.bgra` as the original Phase 4 switch had. Fixed.
    - `FlutterStandardTypedData.data` returns `Data` whose `withUnsafeBytes` overload set needs an explicit `(raw: UnsafeRawBufferPointer)` type annotation to disambiguate from the typed-pointer overload. Fixed.
  - The `PixelBufferPool.reuseCount` field was never actually incremented by the pool's logic — it was a placeholder that would have shipped a misleading metric to `debugStats`. Removed from the pool, the plugin's `debugStats` payload, the Dart `PixelSurfaceStats` value type, and all three layers' tests. `createCount` (every dequeue) and `poolCount` (number of buckets) remain; these are the only metrics the standard `CVPixelBufferPool` API lets us observe without opaque-pool internals.

- **Internal Rust API only** — Dart API is additive (new methods), all existing entry points retain their previous signatures.

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
