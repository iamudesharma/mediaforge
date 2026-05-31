# image_forge_editor

Instagram-style Flutter image editor UI (panels, crop, beauty, filters, layers, export).

## Dependencies

| Package | Role |
|---------|------|
| [`image_forge`](../image_forge/) | Rust + FRB engine |
| [`pixel_surface`](../pixel_surface/) | GPU `Texture` preview |
| [`image_forge_camera`](../image_forge_camera/) | Live front camera (mobile) |

`camera` and `permission_handler` are **not** direct dependencies — they come from `image_forge_camera`.

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
  image_forge_editor:
```

```dart
import 'package:image_forge_editor/image_forge_editor.dart';

await RustImageEditor.ensureInitialized();

RustImageEditorWidget(
  config: RustImageEditorConfig(),
);
```

The legacy package name `rust_image` re-exports this library for one release cycle.

## Example / studio demo

```bash
dart pub get && dart run melos bootstrap
cd packages/image_forge/rust && cargo build --features gpu
cd ../../../rust_image/example
cd macos && pod install && cd ..
flutter run -d macos
```

## Verify tests

```bash
cd packages/image_forge_editor && flutter test
```

Set `RUST_IMAGE_DYLIB` to a built `libimage_forge` if the test runner is not plugin-linked.

## Changelog

See [CHANGELOG.md](CHANGELOG.md).

## Acceptance

Pre-publish checklist: [docs/P0_ACCEPTANCE.md](../../docs/P0_ACCEPTANCE.md).
