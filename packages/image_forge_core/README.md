# image_forge_core

[![pub package](https://img.shields.io/pub/v/image_forge_core.svg)](https://pub.dev/packages/image_forge_core)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

> Open-source project maintained by the community. Found a bug or want to contribute? [PRs and issues are welcome](https://github.com/iamudesharma/mediaforge/issues).

Lightweight Rust image processing engine for Flutter — core operations only. GPU-accelerated resize, crop, rotate, compress, thumbnails, basic filters, and multi-format encoding. Runs native Rust on device with SIMD and WGSL compute shaders.

> [!NOTE]
> This is the **lightweight core** (no face beauty, no mood/swipe/LUT presets, no GPU preview surface). For the full engine with face beauty, mood filters, swipe looks, LUT, layer compositing, temporal smoothing, and GPU preview surface, use [`image_forge`](../image_forge/). For the full editor UI, use [`image_forge_editor`](../image_forge_editor/).

---

## Platform Support

| Platform | Status |
|---|---|
| Android | Tested (API 21+) |
| iOS | Tested (15.0+) |
| macOS | Tested (12+) |
| Windows | In progress |
| Linux | In progress |
| Web | Not supported |

---

## Quick Start

```dart
import 'package:image_forge_core/image_forge_core.dart';

// Resize an image
final thumb = resizeImage(
  bytes: bytes,
  width: 512,
  height: 512,
  algorithm: ResizeAlgorithm.lanczos3,
  format: OutputFormat.jpeg,
  quality: 85,
  fixExif: true,
  backend: ProcessingBackend.auto,
);

// Compress an image
final compressed = compressImage(
  bytes: bytes,
  format: OutputFormat.jpeg,
  quality: 70,
);

// Create a thumbnail (fits within max_edge bounding box)
final thumb = createThumbnail(
  bytes: bytes,
  maxEdge: 512,
  format: OutputFormat.jpeg,
  quality: 85,
  algorithm: ResizeAlgorithm.lanczos3,
  fixExif: true,
  backend: ProcessingBackend.auto,
);

// Probe image info without full decode
final info = probeImage(bytes: bytes);
print('${info.width}x${info.height}');
```

---

## What You Get

- **Resize, crop, rotate** — Multiple resize algorithms (Lanczos3, Mitchell, CatmullRom, etc.) with batch parallelism.
- **Compress & thumbnails** — MozJPEG and oxipng optimization, fast thumbnail generation.
- **Basic filters** — Brightness, contrast, saturation, hue, blur, sharpen, warmth, fade, vignette, highlights, shadows, structure, pixelize, frosted glass, oil, solarize, and 14 classic presets.
- **Drawing & overlays** — Text, lines, circles, watermark image overlays with blend modes (Multiply, Screen, Overlay, Add).
- **EXIF handling** — Read and fix orientation without re-encoding.
- **Multi-format** — JPEG (MozJPEG), PNG (oxipng), WebP, AVIF encode/decode.
- **Progressive decode** — Low-res preview + full-res buffer in one pass.
- **GPU compute** — wgpu Metal/Vulkan acceleration for resize, blur, sharpen, and color adjustments.
- **Buffer pool** — Zero-allocation byte vector reuse for render loops.
- **BlurHash** — Placeholder generation for loading states.

For the full API, see the [Dart API reference](https://pub.dev/documentation/image_forge_core/latest/).

---

## image_forge vs image_forge_core

| Feature | image_forge_core | image_forge |
|---|---|---|
| Resize, crop, rotate | Yes | Yes |
| Compress (MozJPEG/oxipng) | Yes | Yes |
| Thumbnails | Yes | Yes |
| EXIF orientation | Yes | Yes |
| BlurHash | Yes | Yes |
| Basic filters (blur, brightness, etc.) | Yes | Yes |
| Classic presets (Neue, Lofi, etc.) | Yes | Yes |
| Drawing (text, lines, circles) | Yes | Yes |
| Watermark / image overlay | Yes | Yes |
| RGBA buffer pipeline | Yes | Yes |
| GPU compute (resize, blur, color) | Yes | Yes |
| Mood filters (Clarendon, Juno, etc.) | No | Yes |
| Swipe looks (Clean Girl Glow, etc.) | No | Yes |
| 3D LUT PNG support | No | Yes |
| Face beauty (skin smooth, eye, lip) | No | Yes |
| Layer compositing | No | Yes |
| Temporal smoothing (live camera) | No | Yes |
| GPU preview surface | No | Yes |
| **Approximate app size** | **~8-12 MB** | **~14-18 MB** |

---

## App Size

The package bundles native Rust libraries per platform. Size impact by component:

| Component | Est. Size | What you lose if removed |
|---|---|---|
| Core engine (resize, crop, rotate, compress, EXIF, filters, drawing) | **~7-9 MB** | — |
| GPU compute (wgpu — Metal/Vulkan) | **+4-6 MB** | Hardware-accelerated resize, blur, sharpen, brightness/contrast/saturation/hue |
| AVIF encode/decode (rav1e) | **+1-2 MB** | AVIF format support |

> The `image_forge` package adds additional features: face beauty, mood/swipe presets, LUT, layer compositing, temporal smoothing, GPU preview surface, and MediaPipe models (~4 MB).

---

## Installation

```bash
flutter pub add image_forge_core
```

**Prerequisites:** A [Rust toolchain](https://rustup.rs) on your development machine. For Android:
```bash
rustup target add aarch64-linux-android armv7-linux-androideabi \
  x86_64-linux-android i686-linux-android
```

---

## More Examples

### Crop & rotate
```dart
final cropped = cropImage(
  bytes: bytes, x: 100, y: 100, width: 400, height: 300,
  format: OutputFormat.jpeg, quality: 85, fixExif: true,
);

final rotated = rotateImage(
  bytes: bytes, rotation: Rotation.rotate90,
  format: OutputFormat.jpeg, quality: 85, fixExif: true,
);
```

### Apply a filter
```dart
final filtered = applyFilter(
  bytes: bytes,
  filter: ImageFilter.brightness(amount: 25),
  format: OutputFormat.jpeg,
  quality: 85,
  fixExif: true,
);
```

### Overlay with blend mode
```dart
final composed = overlayImage(
  baseBytes: photo, overlayBytes: logo,
  x: 40, y: 40, blendMode: BlendMode.multiply,
  format: OutputFormat.png, quality: 100,
);
```

### Progressive decode (low-res preview + full buffer)
```dart
final result = decodeProgressiveImage(
  bytes: bytes,
  previewMaxEdge: 128,
  fixExif: true,
);
// Show result.previewRgba immediately for instant feedback
// Then work with result.buffer for full-resolution editing
```

### Batch resize (parallel)
```dart
final results = batchResizeImages(
  items: [
    BatchResizeItem(bytes: img1, width: 512, height: 512),
    BatchResizeItem(bytes: img2, width: 256, height: 256),
  ],
  algorithm: ResizeAlgorithm.lanczos3,
  format: OutputFormat.jpeg,
  quality: 85,
  backend: ProcessingBackend.auto,
);
```

### GPU detection
```dart
final gpu = gpuComputeInfo();
if (gpu.available) print('GPU: ${gpu.device} (${gpu.api})');

final thumb = resizeImage(
  bytes: bytes, width: 512, height: 512,
  algorithm: ResizeAlgorithm.lanczos3,
  format: OutputFormat.jpeg, quality: 85,
  fixExif: true,
  backend: ProcessingBackend.auto, // auto = GPU if available
);
```

### RGBA buffer pipeline (zero intermediate encode/decode)
```dart
final buf = decodeToRgbaBuffer(bytes: bytes, fixExif: true);

// Chain operations on raw pixels
final filtered = filterRgbaBuffer(
  buffer: buf,
  filter: ImageFilter.blur(radius: 4),
  backend: ProcessingBackend.auto,
);
final resized = resizeRgbaBuffer(
  buffer: filtered,
  width: 1024, height: 768,
  algorithm: ResizeAlgorithm.lanczos3,
  backend: ProcessingBackend.gpu,
);

// Encode once at the end
final out = encodeRgbaBuffer(
  buffer: resized,
  format: OutputFormat.jpeg,
  quality: 90,
);
```

---

## Build & Test

```bash
# Rust unit tests
cd packages/image_forge_core/rust && cargo test --features gpu,blurhash

# Dart tests (requires FRB codegen first)
cd packages/image_forge_core && flutter test

# CLI benchmarks
cd packages/image_forge_core/rust
cargo run --release --features gpu --bin image_forge_core_benchmark -- --synthetic -n 5
```

---

## Contributing

This package is part of the [MediaForge monorepo](https://github.com/iamudesharma/mediaforge). Issues and pull requests are welcome on [GitHub](https://github.com/iamudesharma/mediaforge/issues).

---

## Links

- [GitHub Repository](https://github.com/iamudesharma/mediaforge)
- [Issue Tracker](https://github.com/iamudesharma/mediaforge/issues)
- [Full Engine Package](../image_forge/)
- [Editor UI Package](../image_forge_editor/)
- [GPU Texture Bridge](../pixel_surface/)
- [Live Camera SDK](../image_forge_camera/)
