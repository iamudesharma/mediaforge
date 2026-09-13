# iOS 15 compatibility (pixel_surface)

PeerStream targets iOS 15 while `pixel_surface` previously declared iOS 16.
Every API used by `pixel_surface` was audited; the implementation is
compatible with iOS 15, so the deployment target is now **15.0**
(`ios/pixel_surface.podspec`). No consumer needs to raise its target.

## Audited APIs

| API | Availability | Notes |
| --- | --- | --- |
| `CVPixelBufferPoolCreate` / `CreatePixelBuffer` / `Flush` | iOS 9+ | Bucketed pool in `PixelBufferPool.swift` |
| `kCVPixelBufferPoolMinimumBufferCountKey` / `MaximumBufferAgeKey` | iOS 9+ / 10+ | Pool tuning (3 warm, 1 s max age) |
| `kCVPixelBufferIOSurfacePropertiesKey` / `MetalCompatibilityKey` | iOS 11+ / 9+ | Zero-copy adoption attrs |
| `CVMetalTextureCacheCreate` / `CreateTextureFromImage` | iOS 8+ | `getMetalTexturePtr` path |
| `vImagePermuteChannels_ARGB8888` (Accelerate) | iOS 5+ | RGBA→BGRA swizzle fallback |
| `CFAbsoluteTimeGetCurrent` | iOS 2+ | `debugStats` timestamps |
| `FlutterTexture` / `FlutterMethodChannel` / `register` | Flutter iOS | No version-gated Flutter API |
| Swift 5.0, no `async/await`, no `#available` gates needed | — | Codebase uses callbacks only |

No API genuinely requires iOS 16, so no fallback implementation was
needed. If a future change introduces an iOS 16+ API, it must be gated
with `@available` / `#available` plus an iOS 15 fallback — never a silent
deployment-target bump.

## Verification

* `ios/pixel_surface.podspec`: `s.platform = :ios, '15.0'`.
* CI (`media_forge_native.yml`, `ios` job): builds the example with
  `IPHONEOS_DEPLOYMENT_TARGET=15.0` and fails on warnings in
  `pixel_surface` sources.
* Manual: open `pixel_surface/example/ios/Runner.xcworkspace`, set
  Runner deployment target to 15.0, build on an iOS 15 simulator/device;
  `GpuTextureRegistry.debugStats()` must succeed and `presentPixelBuffer`
  must adopt IOSurface buffers (log `present adopted`).
