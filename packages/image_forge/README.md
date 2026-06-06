# image_forge

[pub package](https://pub.dev/packages/image_forge)
[License](LICENSE)

> Open-source project maintained by the community. Found a bug or want to contribute? [PRs and issues are welcome](https://github.com/iamudesharma/mediaforge/issues).

Full-featured Rust image processing engine for Flutter — GPU-accelerated filters, face beauty, layer composition, multi-format encoding, mood/swipe presets, LUT support, and GPU preview surface. Runs native Rust on device with SIMD and WGSL compute shaders.

---

## Platform Support


| Platform | Status           |
| -------- | ---------------- |
| Android  | Tested (API 21+) |
| iOS      | Tested (15.0+)   |
| macOS    | Tested (12+)     |
| Windows  | In progress      |
| Linux    | In progress      |
| Web      | Not supported    |


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


| Pros                                              | Cons                                         |
| ------------------------------------------------- | -------------------------------------------- |
| Much faster than pure-Dart image processing       | No web support                               |
| GPU acceleration on supported devices             | Increases app size (bundles native Rust)     |
| Android, iOS, macOS (Windows & Linux in progress) | Developer needs Rust toolchain installed     |
| Multi-format: JPEG, PNG, WebP, AVIF               | First Android build is slow (4 ABI compiles) |
| Free and open source (Apache 2.0)                 | More setup than a pure-Dart image package    |


---

## App Size

The package bundles native Rust libraries per platform. Size impact by component:


| Component                                                            | Est. Size    | What you lose if removed                                                       |
| -------------------------------------------------------------------- | ------------ | ------------------------------------------------------------------------------ |
| Core engine (resize, crop, rotate, compress, EXIF, filters, drawing) | **~7–9 MB**  | —                                                                              |
| GPU compute (wgpu — Metal/Vulkan)                                    | **+4–6 MB**  | Hardware-accelerated resize, blur, sharpen, brightness/contrast/saturation/hue |
| AVIF encode/decode (rav1e)                                           | **+1–2 MB**  | AVIF format support                                                            |
| Face beauty engine (skin smooth, eye brighten, lip tint, presets)    | **+~100 KB** | Face retouching features                                                       |


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

## Contributing

This package is part of the [MediaForge monorepo](https://github.com/iamudesharma/mediaforge). Issues and pull requests are welcome on [GitHub](https://github.com/iamudesharma/mediaforge/issues).

---

## Links

- [GitHub Repository](https://github.com/iamudesharma/mediaforge)
- [Issue Tracker](https://github.com/iamudesharma/mediaforge/issues)

