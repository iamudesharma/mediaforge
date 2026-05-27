# rust_image_core

Rust image processing engine + **flutter_rust_bridge** Dart bindings. No editor widgets.

**Depends on:** [`rust_gpu_texture`](../rust_gpu_texture/) (Flutter texture bridge + Rust `rust_gpu_texture` crate).

## Platform matrix

| Platform | Support | Notes |
|----------|---------|--------|
| Android | Yes | minSdk **21**, NDK, Rust Android targets |
| iOS | Yes | **15.0+**, Rust linked via CargoKit |
| macOS | Yes | **12+**, Vision face analysis |
| Linux / Windows | Yes | CPU + optional wgpu GPU |
| Web | No | FRB / native Rust not wired |

Full matrix: [docs/PACKAGE_PLATFORM_MATRIX.md](../../docs/PACKAGE_PLATFORM_MATRIX.md).

## Use from an app

```yaml
dependencies:
  rust_image_core:
  rust_gpu_texture:   # required for GPU Texture preview APIs
```

```dart
import 'package:rust_image_core/rust_image_core.dart';

await RustLib.init();
final rgba = decodeToRgbaBuffer(bytes: fileBytes, fixExif: true, maxEdge: 1280);
final out = filterRgbaBuffer(
  buffer: rgba,
  filter: const ImageFilter.blur(radius: 4),
  backend: ProcessingBackend.auto,
);
```

For the full editor UI, use [`rust_image_editor`](../rust_image_editor/) (or the `rust_image` compatibility shim).

## Example (P0.6)

RGBA filter + JPEG export — no editor:

```bash
cd packages/rust_image_core/rust && cargo build --features gpu
cd ../example && flutter run -d macos
```

See [example/README.md](example/README.md).

## Build native (local)

```bash
# From monorepo root
dart pub get && dart run melos bootstrap
cd packages/rust_image_core/rust && cargo check --features gpu
```

Release / iOS symbol stripping: [rust_image/README.md](../../rust_image/README.md).

## Changelog

See [CHANGELOG.md](CHANGELOG.md).

## Status

- Engine + FRB live in this package (P0.3).
- `GpuEditSurface` / wgpu engine still in `rust/` here; physical move into `rust_gpu_texture` Rust crate is deferred.
