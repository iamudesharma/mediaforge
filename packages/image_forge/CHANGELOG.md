## 1.0.0

- **Renamed from `rust_image_core` to `image_forge`** — a proper pub.dev package name.
- Initial pub.dev release: Rust image processing engine for Flutter.
- GPU-accelerated filters, beauty, face analysis, EXIF, JPEG/PNG/AVIF/WebP encode/decode.
- Depends on `pixel_surface` (was `rust_gpu_texture`) for GPU texture boundaries.
- Breaking change: package import path changed from `package:rust_image_core` to `package:image_forge`.

## 0.2.0

- Monorepo package extraction (P0.3): Rust engine + FRB + native face plugins.
- Depends on `pixel_surface` for texture crate boundary.
- Example app: synthetic RGBA → filter → JPEG export (P0.6).

## 0.1.0

- Pre-split: engine lived inside `rust_image` plugin.
