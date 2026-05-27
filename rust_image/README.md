# rust_image

Flutter image editor plugin with a **Rust** core (FFI via `flutter_rust_bridge`) and an optional **drop-in editor UI**.

## Install

```yaml
dependencies:
  rust_image: ^0.1.0
```

## Supported Platforms & Setup Requirements

The editor UI lives in **`rust_image_editor`**; this package re-exports it for compatibility. Native Rust is built via **`rust_image_core`** (CargoKit) — install the Rust toolchain on your machine.

### General Prerequisites

Install Rust via [rustup](https://rustup.rs):
```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```
Make sure you use the official toolchain installer (do not use Homebrew `rustc` on macOS, as it lacks support for cross-compiling target architectures).

---

### 🤖 Android Setup

1. **Rust Targets**: Install the Android targets for cross-compiling:
   ```bash
   rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android i686-linux-android
   ```
2. **Android NDK**: Ensure you have the Android NDK installed. The build system will automatically look up the NDK path specified in your project's `local.properties` or `ANDROID_NDK_HOME` environment variable.
3. **Minimum SDK**: This plugin requires a minimum Android SDK version of **21** or higher. Ensure your app's `android/app/build.gradle` has:
   ```groovy
   defaultConfig {
       minSdkVersion 21
   }
   ```

---

### 🍏 iOS Setup

1. **Minimum OS**: This plugin requires iOS **15.0** or higher. Ensure your `ios/Podfile` specifies:
   ```ruby
   platform :ios, '15.0'
   ```
2. **Release/Archive Entitlements**: Debug builds work out of the box, but Xcode's linker might strip native Rust symbols in Release or Archive modes, leading to `Failed to lookup symbol 'frb_get_rust_content_hash'`. To resolve this:
   - Open `ios/Runner.xcworkspace` in Xcode.
   - Go to **Runner** target → **Build Settings** (Release configuration).
   - Set **Strip Style** to `Non-Global Symbols` (do not use "All Symbols").
   - Set **Strip Linked Product** to `No` (or **Deployment Postprocessing** to `No`).
   - Alternatively, add this helper script to your `ios/Podfile`:
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

---

### 💻 macOS Setup

1. **Minimum OS**: This plugin requires macOS **12.0** or higher. Ensure your `macos/Podfile` specifies:
   ```ruby
   platform :osx, '12.0'
   ```
2. **App Sandbox Entitlements**: If your app is sandboxed (default for new macOS projects), you must allow user-selected file read/write access to let users pick and save images:
   - Open your project's macOS entitlements files (`macos/Runner/DebugProfile.entitlements` and `macos/Runner/Release.entitlements`).
   - Enable the following key:
     ```xml
     <key>com.apple.security.files.user-selected.read-write</key>
     <true/>
     ```

---

### 🪟 Windows Setup

1. **Build Tools**: Install Visual Studio with the "Desktop development with C++" workload (which includes MSVC, CMake 3.14+, and Windows SDK).
2. **Rust Target**: Install the MSVC toolchain target:
   ```bash
   rustup target add x86_64-pc-windows-msvc
   ```

---

### 🐧 Linux Setup

1. **System Dependencies**: Ensure standard C/C++ compilers, CMake, and GTK+ 3 development headers are installed:
   - On Ubuntu/Debian:
     ```bash
     sudo apt-get install build-essential cmake pkg-config libgtk-3-dev clang
     ```
2. **Rust Target**: Install the GNU toolchain target:
   ```bash
   rustup target add x86_64-unknown-linux-gnu
   ```

---

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

**GPU texture preview (11b.2 + Sprint 22.4):** Set `useGpuTexturePreview: true` on **macOS, iOS, or Android** for Flutter `Texture` display (skips `RgbaPreviewImage` on the hot path when active). Falls back to `RgbaPreviewImage` when unavailable.

**Beauty GPU (Sprint 22):** All regional beauty (skin, eyes, lips, blush, teeth, under-eye, plump, face warp) runs on **wgpu** when available. With `useGpuTexturePreview: true`, still-photo sliders update the `Texture` only (`previewRgba` stays null). Status: `gpu_beauty`, `gpu_skin`, `gpu_plump`, etc. See [`docs/BEAUTY_GPU.md`](../docs/BEAUTY_GPU.md).

**Beauty (Nexus complete):** Beauty tab → looks, regional sliders, eraser, under-eye, **teeth whiten**. **Live camera:** temporal face smooth + GPU Texture when `useGpuTexturePreview: true`. Optional **MediaPipe 468** download (`enableMediaPipeDownloadPrompt`). Vision / ML Kit fallback without download.

**Recommended config for portrait beauty performance:**

```dart
RustImageEditorConfig(
  useRgbaPreview: true,
  useGpuTexturePreview: true,
  showPerformanceInStatus: true,
)
```

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

## Publishing (planned split)

Before stable pub.dev, this plugin will split into **`rust_gpu_texture`**, **`rust_image_core`**, **`rust_image_editor`**, and (later) **`rust_camera_runtime`**. The Rust crate is already named `rust_image_core`; the Flutter package will become `rust_image_editor`. Details: [docs/PUB_PACKAGE_SPLIT.md](../docs/PUB_PACKAGE_SPLIT.md).
