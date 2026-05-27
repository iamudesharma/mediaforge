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
- **Layers tool (Sprint 17):** drag a selection rectangle on the canvas to select multiple layers; **Group** / **Ungroup** / **Duplicate** in the Layers panel (or Ctrl/Cmd+D on desktop). Move, scale, and rotate the selection together before grouping.
- **Text / shape / blank canvas** use in-stack overlays on phone (not full-route modals) so the image remains in view.
- `showCanvasFloatingChrome: true` (default) toggles canvas flip/layers controls.

See the [root README](../README.md) for macOS sandbox entitlements (file picker) and GPU notes.

### iOS Release / Rust FFI (flutter_rust_bridge)

Debug builds often work while **Release**, **Profile**, or **Archive** fail with a Rust initializer error such as `Failed to lookup symbol 'frb_get_rust_content_hash'`. That happens when Xcode’s linker strips Rust symbols that Dart loads via `ExternalLibrary.process()` — not because Rust failed to compile.

**Plugin-side (this package):** `rust_image.podspec` uses Cargokit `force_load` on `librust_image_core.a`, `-Wl,-u,_frb_get_rust_content_hash`, and a Swift call to `rust_image_link_rust_for_frb()` in `RustImagePlugin.register`.

**After pulling these changes:**

```bash
cd your_app
flutter clean
rm -rf ios/Pods ios/Podfile.lock ios/.symlinks
flutter pub get
cd ios && pod install && cd ..
flutter build ios --release
```

**Host app (Runner) — required for TestFlight / App Store archives:**

1. Open `ios/Runner.xcworkspace` in Xcode.
2. Select **Runner** → **Build Settings** (Release configuration).
3. **Strip Style** → **Non-Global Symbols** (not “All Symbols”).
4. **Strip Linked Product** → **No** (or **Deployment Postprocessing** → **No**).

Optional `ios/Podfile` `post_install` (applies to all configs):

```ruby
post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
    target.build_configurations.each do |config|
      if target.name == 'Runner' || target.name == 'rust_image'
        config.build_settings['STRIP_STYLE'] = 'non-global'
        config.build_settings['DEAD_CODE_STRIPPING'] = 'NO'
      end
    end
  end
end
```

**Xcode “Build Rust library” script timeout:** The first Release iOS build compiles Rust for device (`aarch64-apple-ios`) and can take several minutes. Let the “Build Rust library” phase finish; avoid stopping the build early. Subsequent builds are incremental.

**Verify:** Run on a physical iPhone with `flutter run --release` before archiving.

**HEIC / HEIF:** iPhone and macOS photos are converted to PNG via the platform image codec before Rust decode. If import still fails, export as JPEG from Photos and try again.

**Swipe combo looks (Sprint 15):** Swipe left/right on the preview for TikTok/Instagram combo filters (Korean Glass Skin, Soft Glam, Golden Hour, …) — global grade + regional beauty in one commit. Classic mood grades (Rose, Clarendon, …) moved to the **Filters** tab. Set `enableSwipeLooks: false` to disable.

**GPU mood (11b.1):** Mood + vignette run on wgpu when backend is auto/Gpu; status line shows `gpu_mood` / `gpu_vignette`.

**GPU texture preview (11b.2):** Set `useGpuTexturePreview: true` on macOS **or iOS** for Flutter `Texture` display (skips Dart `ui.Image` decode). Falls back to `RgbaPreviewImage` when unavailable.

**Beauty (Nexus complete):** Beauty tab → looks, regional sliders, eraser, under-eye, **teeth whiten**. **Live camera:** temporal face smooth + GPU texture preview on Apple when `useGpuTexturePreview: true`. Optional **MediaPipe 468** download in Beauty panel (`enableMediaPipeDownloadPrompt`). Vision / ML Kit fallback without download.

**GPU overlay (Sprint 2 P2):** `apply_gpu_overlay_blend` composites one RGBA layer on the GPU preview cache (normal / multiply / screen).

### GPU coverage (preview vs export)

| Tool | Preview | Export |
|------|---------|--------|
| Adjust (brightness, contrast, …) | GPU when `ProcessingBackend.auto/gpu` | Full-res CPU/GPU replay |
| Filters tab presets | GPU mood-capable ops; photon fallback | Full-res replay |
| Mood swipe | `gpu_mood` + `gpu_vignette` | Committed in edit graph |
| Beauty (still) | GPU WGSL chain + CPU plump/under-eye | Full-res `apply_beauty_rgba` |
| Live camera | GPU texture + beauty WGSL (Apple); CPU Android | N/A (capture not export) |
| Layers (stickers/text/paint) | Flutter overlay; optional GPU overlay blend | CPU bake via `LayerBake` |
| Crop / straighten | Flutter overlay; two-finger straighten gesture | Pixel bake on commit |

Status line (`showPerformanceInStatus: true`): filter path, stage ms, `gpu_*` / `cpu_*` beauty hints, live fps.

## Editor state (Sprint 14 — Riverpod, internal)

Flutter UI state uses **Riverpod** inside `RustImageEditorWidget` (`ProviderScope` + narrow listenables for preview vs shell chrome). **Host apps do not need Riverpod** — keep using `RustImageEditorConfig` and optional `session:` as before.

Preview updates rebuild the canvas only; tool panels and nav do not repaint on every preview frame. See [`docs/FLUTTER_STATE.md`](../docs/FLUTTER_STATE.md) for provider map and DevTools rebuild checklist.

## Worker pool (Sprint 13)

Heavy image work runs in a **Squadron** worker pool (`RustWorker`) so the UI isolate stays responsive. Live camera uses a dedicated worker for YUV→RGBA.

After changing `@SquadronMethod` in `lib/src/editor/services/rust_worker_service.dart`:

```bash
cd rust_image
dart run build_runner build
```

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
