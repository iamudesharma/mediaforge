# image_forge

[![pub package](https://img.shields.io/pub/v/image_forge.svg)](https://pub.dev/packages/image_forge)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

> Open-source project maintained by the community. Found a bug or want to contribute? [PRs and issues are welcome](https://github.com/iamudesharma/mediaforge/issues).

Full-featured Rust image processing engine for Flutter — GPU-accelerated filters, face beauty, layer composition, multi-format encoding, mood/swipe presets, LUT support, and GPU preview surface. Runs native Rust on device with SIMD and WGSL compute shaders.

> [!NOTE]
> This is a **headless engine** (no UI widgets). For the full editor with crop, filters panel, draw, layers, and export UI, use [`image_forge_editor`](../image_forge_editor/). For GPU texture display, see [`pixel_surface`](../pixel_surface/). For lightweight image operations (resize, crop, compress, thumbnails), see [`image_forge_core`](../image_forge_core/) — a smaller version without face beauty or mood/swipe presets.

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
import 'package:image_forge/image_forge.dart';

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

// Apply a filter
final filtered = applyFilter(
  bytes: bytes,
  filter: const ImageFilter.brightness(amount: 0.2),
  format: OutputFormat.jpeg,
  quality: 85,
  fixExif: true,
);

// Probe image info without full decode
final info = probeImage(bytes: bytes);
print('${info.width}x${info.height}');
```

---

## What You Can Do

- **Resize, crop, rotate** — Multiple resize algorithms (Lanczos3, Mitchell, CatmullRom, etc.) with batch parallelism.
- **Filters & adjustments** — Brightness, contrast, saturation, hue, warmth, fade, vignette, highlights, shadows, structure, presets, LUTs.
- **Face beauty** — Skin smoothing, eye brightening, lip tinting with GPU compute shaders.
- **Stickers & drawing** — Text, lines, circles, watermark overlays with blend modes (Multiply, Screen, Overlay, Add).
- **EXIF handling** — Read and fix orientation without re-encoding.
- **Multi-format** — JPEG, PNG, WebP, AVIF encode/decode.
- **Progressive decode** — Low-res preview + full-res buffer in one pass.
- **GPU compute** — wgpu Metal/Vulkan acceleration for resize, blur, sharpen, brightness, contrast, saturation, hue, and beauty passes.
- **Buffer pool** — Zero-allocation byte vector reuse for render loops.
- **Face landmark smoothing** — EMA stabilizer for live camera streams.

For the full API, see the [Dart API reference](https://pub.dev/documentation/image_forge/latest/).

---

## Pros & Cons

| Pros | Cons |
|---|---|
| Much faster than pure-Dart image processing | No web support |
| GPU acceleration on supported devices | Increases app size (bundles native Rust) |
| Android, iOS, macOS (Windows & Linux in progress) | Developer needs Rust toolchain installed |
| Multi-format: JPEG, PNG, WebP, AVIF | First Android build is slow (4 ABI compiles) |
| Free and open source (Apache 2.0) | More setup than a pure-Dart image package |

---

## App Size

The package bundles native Rust libraries per platform. Size impact by component:

| Component | Est. Size | What you lose if removed |
|---|---|---|
| Core engine (resize, crop, rotate, compress, EXIF, filters, drawing) | **~7–9 MB** | — |
| GPU compute (wgpu — Metal/Vulkan) | **+4–6 MB** | Hardware-accelerated resize, blur, sharpen, brightness/contrast/saturation/hue |
| AVIF encode/decode (rav1e) | **+1–2 MB** | AVIF format support |
| Face beauty engine (skin smooth, eye brighten, lip tint, presets) | **+~100 KB** | Face retouching features |

The beauty engine is tiny (~100 KB) — it's pure Rust without external ML dependencies. The GPU stack and AVIF encoder are the real size drivers.

**Package split available:**
- [`image_forge_core`](../image_forge_core/) — Core ops + filters + drawing (~8-12 MB)
- `image_forge` — Core + face beauty + mood/swipe presets + LUT + layers + GPU preview surface (~14-18 MB)
- These are independently versioned. Use `image_forge_core` if you only need image processing without beauty/filter presets.

---

## Installation

```bash
flutter pub add image_forge
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
  bytes: bytes, rotation: Rotation.deg90,
  format: OutputFormat.jpeg, quality: 85, fixExif: true,
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
final result = decodeProgressiveImage(bytes, previewMaxEdge: 128, fixExif: true);
// Show result.previewBytes immediately for instant feedback
// Then work with result.fullBuffer for full-resolution editing
```

### GPU detection
```dart
final gpu = gpuComputeInfo();
if (gpu != null) print('GPU: ${gpu.deviceName} (${gpu.backend})');

// Use GPU backend for supported operations
final thumb = resizeImage(
  bytes: bytes, width: 512, height: 512,
  algorithm: ResizeAlgorithm.lanczos3,
  format: OutputFormat.jpeg, quality: 85,
  fixExif: true,
  backend: ProcessingBackend.auto, // auto = GPU if available
);
```

---

## Build & Test

```bash
# Rust unit tests
cd packages/image_forge/rust && cargo test --features gpu,blurhash

# Run example app
cd packages/image_forge/example && flutter run -d macos

# CLI benchmarks
cd packages/image_forge/rust
cargo run --release --features gpu --bin rust_image_benchmark -- --synthetic -n 5
```

---

## Contributing

This package is part of the [MediaForge monorepo](https://github.com/iamudesharma/mediaforge). Issues and pull requests are welcome on [GitHub](https://github.com/iamudesharma/mediaforge/issues).

---

## Links

- [GitHub Repository](https://github.com/iamudesharma/mediaforge)
- [Issue Tracker](https://github.com/iamudesharma/mediaforge/issues)
- [Editor UI Package](../image_forge_editor/)
- [GPU Texture Bridge](../pixel_surface/)
- [Live Camera SDK](../image_forge_camera/)
