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
    layoutMode: EditorLayoutMode.auto,  // immersive on phone (<900px), sidebar on desktop
    toolBarPlacement: EditorToolBarPlacement.bottom, // or .top — mobile tool dock only
    showMobileMetaOverlay: true,       // dimensions/GPU chips over the canvas on phone
    showCanvasFloatingChrome: true,    // flip + layers on canvas (mobile)
  ),
)
```

### Mobile layout (immersive)

- **Canvas stays large** while a tool sheet is open: the sheet floats over the bottom of the preview (no dead gap above the sheet).
- **Top-left on canvas:** flip H/V and a **Layers** button with a compact popover (layers are not in the bottom nav).
- **Bottom nav** lists editing tools plus **Import**; **Export** stays in the top bar.
- **Context strip** (filters, adjust, crop aspects, paint colors, sticker tabs) is embedded in the tool sheet header — one continuous panel, no floating gap.
- **Text / shape / blank canvas** use in-stack overlays on phone (not full-route modals) so the image remains in view.
- `showCanvasFloatingChrome: true` (default) toggles canvas flip/layers controls.

See the [root README](../README.md) for macOS sandbox entitlements (file picker) and GPU notes.

**HEIC / HEIF:** iPhone and macOS photos are converted to PNG via the platform image codec before Rust decode. If import still fails, export as JPEG from Photos and try again.

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
