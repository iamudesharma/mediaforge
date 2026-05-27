# rust_gpu_texture

Flutter GPU **Texture** runtime — register a platform texture, upload RGBA frames, and display with `GpuTextureView`.

**No** editor, filters, beauty, or `rust_image_core`. Use for camera apps, custom renderers, AI preview, or as the display layer for `rust_image`.

## Platform matrix

| Platform | Support | Notes |
|----------|---------|--------|
| Android | Yes | API **21+**, `SurfaceTexture`; V1.6 `decodePreviewToSurface` (MediaCodec zero-copy) |
| iOS | Yes | **12+**, CVPixelBuffer |
| macOS | Yes | **12+**, CVPixelBuffer |
| Linux / Windows / Web | No | Use RGBA widget fallback in your app |

Full matrix: [docs/PACKAGE_PLATFORM_MATRIX.md](../../docs/PACKAGE_PLATFORM_MATRIX.md).

**Rust / NDK:** not required for this package alone.

## Usage

```dart
import 'package:rust_gpu_texture/rust_gpu_texture.dart';

const handle = 1;
final textureId = await GpuTextureRegistry.createTexture(
  handle: handle,
  width: 512,
  height: 512,
);
await GpuTextureRegistry.updateTexture(handle: handle, pixels: rgba8888);
GpuTextureView(textureId: textureId!, width: 512, height: 512);
```

Method channel: `rust_gpu_texture/texture`.

## Example

Animated RGBA gradient — **no** `rust_image_core`:

```bash
cd packages/rust_gpu_texture/example
flutter pub get
cd macos && pod install && cd ..
flutter run -d macos
```

If Xcode reports `Unable to find module dependency: rust_gpu_texture`, delete `example/macos/Pods` and re-run `pod install`.

## Changelog

See [CHANGELOG.md](CHANGELOG.md).

## Roadmap

- **P0.2:** Flutter + native texture bridge (done)
- **Later:** Rust `GpuEditSurface` / wgpu moves here from `rust_image_core` ([PUB_PACKAGE_SPLIT.md](../../docs/PUB_PACKAGE_SPLIT.md))

## Workspace

From repo root: `dart pub get` && `dart run melos bootstrap`.
