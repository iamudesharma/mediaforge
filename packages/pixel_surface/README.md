# pixel_surface

[![pub package](https://img.shields.io/pub/v/pixel_surface.svg)](https://pub.dev/packages/pixel_surface)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

Flutter GPU **Texture** runtime — register a platform texture, upload RGBA / BGRA frames, and display with `GpuTextureView`. Includes a `PixelBufferPool` for texture recycling and automatic memory-pressure handling on iOS, macOS, and Android.

**No** editor, filters, or beauty. Use for camera apps, custom renderers, AI preview, or as a GPU display layer.

---

## Platform Support

| Platform | Support | Notes |
|----------|---------|-------|
| Android  | Yes     | API 21+, `SurfaceTexture`; `decodePreviewToSurface` (MediaCodec zero-copy) |
| iOS      | Yes     | 12+, `CVPixelBuffer`; `vImage` swizzle for RGBA |
| macOS    | Yes     | 12+, `CVPixelBuffer`; `vImage` swizzle for RGBA |
| Linux    | No      | Use an RGBA widget fallback in your app |
| Windows  | No      | Use an RGBA widget fallback in your app |
| Web      | No      | Use an RGBA widget fallback in your app |

**Rust / NDK:** not required for this package alone.

---

## Quick Start

```dart
import 'package:pixel_surface/pixel_surface.dart';

const handle = 1;
final textureId = await GpuTextureRegistry.createTexture(
  handle: handle,
  width: 512,
  height: 512,
);

// RGBA (default) or BGRA — BGRA is a single memcpy on Apple, no channel swap.
await GpuTextureRegistry.updateTextureBgra(
  handle: handle,
  pixels: bgra8888,
);

GpuTextureView(textureId: textureId!, width: 512, height: 512);
```

Method channel: `pixel_surface/texture`.

---

## What You Can Do

- **Cross-platform texture registration** — single `createTexture` / `updateTexture` / `disposeTexture` API.
- **RGBA & BGRA uploads** — `updateTexture` (RGBA) and `updateTextureBgra` (single memcpy, no channel swap). `PixelLayout` enum for the format.
- **`presentPixelBuffer`** — zero-copy blit of a VideoToolbox decode buffer into the IOSurface / Metal-compatible texture backing (fixes Flutter `CVReturn -6660`).
- **`decodePreviewToSurface`** — Android MediaCodec → Flutter `SurfaceTexture` (V1.6).
- **`GpuTextureView` widget** — GPU-resident frame display, no `RepaintBoundary` round-trip.
- **Texture recycling (`PixelBufferPool`)** — keyed by `(width, height, pixelFormat)` with 3 warm buffers per bucket. `resizeTexture` and `flushPools` for cross-platform memory pressure handling.
- **Memory-pressure hooks** — Apple `didReceiveMemoryWarning` + `thermalStateDidChange`; Android `ComponentCallbacks2.onTrimMemory` (levels `RUNNING_MODERATE` / `RUNNING_LOW` / `RUNNING_CRITICAL` / `UI_HIDDEN` / `BACKGROUND` / `MODERATE` / `COMPLETE`).
- **`debugStats()`** — `PixelSurfaceStats` with `handleCount`, `poolCount`, `createCount`, `lastFlushMs`, `lastMemoryWarningMs`, `trimEventCount`, `recycledBitmapCount`, `lastTrimLevel`.
- **RAII safety** — `BeautyOutputTarget` typed wrapper for adopting a Flutter-side `CVPixelBuffer` + `MTLTexture` pair into a wgpu pipeline. Closes the original `CVMetalTextureRef` leak.
- **`kCVPixelBufferMetalCompatibilityKey`** set on every texture allocation.
- **Modern Flutter** — uses `TextureRegistry.SurfaceProducer` + `scheduleFrame()` (Flutter 3.27+; `markTextureFrameAvailable` removed).

---

## Installation

```bash
flutter pub add pixel_surface
```

No Rust toolchain or NDK is required to consume this package on its own. If you use the higher-level beauty / GPU pipeline, you'll also want `image_forge`.

---

## More Examples

### `GpuTextureView`
```dart
GpuTextureView(
  textureId: textureId!,
  width: 512,
  height: 512,
  fit: BoxFit.contain,
)
```

### Present a CVPixelBuffer (zero-copy)
```dart
await GpuTextureRegistry.presentPixelBuffer(
  handle: handle,
  pixelBuffer: vtDecodedBuffer,
);
```

### Memory pressure
```dart
// Recycle every backing bitmap and CVMetalTextureCache
await GpuTextureRegistry.flushPools();

// Inspect operator-facing counters
final stats = await GpuTextureRegistry.debugStats();
print('last trim level: ${stats.lastTrimLevel}');
```

### Resize a texture
```dart
await GpuTextureRegistry.resizeTexture(
  handle: handle,
  width: 1024,
  height: 1024,
);
```

---

## Build & Test

```bash
# Dart unit tests (registry + stats parsing)
cd packages/pixel_surface && flutter test

# Run the example app
cd packages/pixel_surface/example
flutter pub get
cd macos && pod install && cd ..
flutter run -d macos   # or ios / android
```

If Xcode reports `Unable to find module dependency: pixel_surface`, delete `example/macos/Pods` and re-run `pod install`.

---

## Contributing

This package is part of the [MediaForge monorepo](https://github.com/iamudesharma/mediaforge). Issues and pull requests are welcome on [GitHub](https://github.com/iamudesharma/mediaforge/issues).

---

## Links

- [GitHub Repository](https://github.com/iamudesharma/mediaforge)
- [Issue Tracker](https://github.com/iamudesharma/mediaforge/issues)
- [Image Engine (image_forge)](../image_forge/)
- [Lightweight Image Engine (image_forge_core)](../image_forge_core/)
- [Video Engine (video_forge)](../video_forge/)
