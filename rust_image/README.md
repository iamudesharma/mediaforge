# rust_image

Flutter image editor plugin with a **Rust** core (FFI via `flutter_rust_bridge`) and an optional **drop-in editor UI**.

## Install

```yaml
dependencies:
  rust_image: ^0.1.0
```

## Drop-in editor widget

```dart
import 'package:rust_image/rust_image.dart';

RustImageEditorWidget(
  config: RustImageEditorConfig(
    title: 'Edit photo',
    onExport: (bytes, info) => save(bytes),
    pickImage: () => myCustomPicker(), // optional
    enabledTools: EditorTool.values,    // or a subset
    useRgbaPreview: true,               // Sprint 4: skip JPEG on live filter preview
    liveEditMaxEdge: 1280,              // edit-scale preview; full res on export
    layoutMode: EditorLayoutMode.auto,  // immersive on phone, sidebar on desktop
    toolBarPlacement: EditorToolBarPlacement.bottom, // or .top on mobile
  ),
)
```

See the [root README](../README.md) for macOS sandbox entitlements (file picker) and GPU notes.

## Benchmarks

[`benchmark/`](benchmark/README.md) — cold API runs (10× default, CPU vs GPU). Rust: `cd rust && cargo run --release --features gpu --bin rust_image_benchmark -- --synthetic`. Dart/FRB: `cd benchmark && ./run_dart_benchmark.sh`.

## APIs only

```dart
await RustImageEditor.ensureInitialized();
final out = RustImageEditor.filter(
  bytes: bytes,
  filter: const ImageFilter.blur(radius: 4),
);
```

## Example

```bash
cd example && flutter run
```
