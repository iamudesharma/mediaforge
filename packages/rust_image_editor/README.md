# rust_image_editor

Instagram-style Flutter image editor UI (panels, crop, beauty, filters, layers, export).

## Dependencies

| Package | Role |
|---------|------|
| [`rust_image_core`](../rust_image_core/) | Rust + FRB engine |
| [`rust_gpu_texture`](../rust_gpu_texture/) | GPU `Texture` preview |
| [`rust_camera_runtime`](../rust_camera_runtime/) | Live front camera (mobile) |

`camera` and `permission_handler` are **not** direct dependencies — they come from `rust_camera_runtime`.

## Platform matrix

| Platform | Editor | Live camera beauty |
|----------|--------|---------------------|
| Android | Yes | Yes |
| iOS | Yes | Yes |
| macOS | Yes (Vision face) | No |
| Linux / Windows | Reduced (no native face) | No |
| Web | Not supported | No |

Setup (NDK, iOS 15, Rust): [rust_image/README.md](../../rust_image/README.md) and [docs/PACKAGE_PLATFORM_MATRIX.md](../../docs/PACKAGE_PLATFORM_MATRIX.md).

## Use in an app

```yaml
dependencies:
  rust_image_editor:
```

```dart
import 'package:rust_image_editor/rust_image_editor.dart';

await RustImageEditor.ensureInitialized();

RustImageEditorWidget(
  config: RustImageEditorConfig(),
);
```

The legacy package name `rust_image` re-exports this library for one release cycle.

## Example / studio demo

```bash
dart pub get && dart run melos bootstrap
cd packages/rust_image_core/rust && cargo build --features gpu
cd ../../../rust_image/example
cd macos && pod install && cd ..
flutter run -d macos
```

## Verify tests

```bash
cd packages/rust_image_editor && flutter test
```

Set `RUST_IMAGE_DYLIB` to a built `librust_image_core` if the test runner is not plugin-linked.

## Changelog

See [CHANGELOG.md](CHANGELOG.md).

## Acceptance

Pre-publish checklist: [docs/P0_ACCEPTANCE.md](../../docs/P0_ACCEPTANCE.md).
