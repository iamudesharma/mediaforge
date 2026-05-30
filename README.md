# rust_image

Flutter image editor plugin with a **Rust** processing core and **flutter_rust_bridge** FFI.

## Package location

**Pre–pub.dev:** Multi-package monorepo (P0.1–P0.6 done):

| Package | Role |
|---------|------|
| [`rust_gpu_texture`](packages/rust_gpu_texture/) | GPU `Texture` bridge only |
| [`rust_image_core`](packages/rust_image_core/) | Rust engine + FRB |
| [`rust_image_editor`](packages/rust_image_editor/) | Editor UI |
| [`rust_camera_runtime`](packages/rust_camera_runtime/) | Live camera (mobile) |
| [`video_processor_core`](packages/video_processor_core/) | Video Rust engine + FRB + FFmpeg |
| [`flutter_video_processor`](packages/flutter_video_processor/) | Video compress / thumbnails SDK |
| [`video_thumbnail_cache`](packages/video_thumbnail_cache/) | Optional disk thumbnail cache |

Split design: [docs/PUB_PACKAGE_SPLIT.md](docs/PUB_PACKAGE_SPLIT.md) · checklist: [docs/P0_ACCEPTANCE.md](docs/P0_ACCEPTANCE.md) · platforms: [docs/PACKAGE_PLATFORM_MATRIX.md](docs/PACKAGE_PLATFORM_MATRIX.md). Video: [docs/VIDEO_PACKAGE_SPLIT.md](docs/VIDEO_PACKAGE_SPLIT.md) · preview runtime (Sprint V1): [docs/VIDEO_MEDIA_RUNTIME.md](docs/VIDEO_MEDIA_RUNTIME.md) · FFmpeg tooling in [`tools/ffmpeg/`](tools/ffmpeg/).

## Stack

| Purpose | Crate |
|---------|--------|
| Core decode/encode | `image` |
| Fast resize | `fast_image_resize` |
| Geometry / draw | `imageproc` |
| Filters | `photon-rs` |
| EXIF | `kamadak-exif` |
| Parallel batch | `rayon` |
| JPEG | `mozjpeg` |
| PNG optimize | `oxipng` |
| Bridge | `flutter_rust_bridge` |
| GPU compute | `wgpu` (Metal on Apple, Vulkan on Android/Linux) |

Default features: `avif`, `blurhash`, `gpu` (disable with `default-features: false` if needed).

## Quick start — drop-in editor widget

```yaml
dependencies:
  rust_image_editor:
    path: ../packages/rust_image_editor   # or pub.dev when published
```

```dart
import 'package:rust_image_editor/rust_image_editor.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MaterialApp(
    theme: AppTheme.dark(),
    home: RustImageEditorWidget(
      config: RustImageEditorConfig(
        title: 'Edit photo',
        initialImageBytes: await File('photo.jpg').readAsBytes(), // optional
        onExport: (bytes, info) async {
          await File('edited.jpg').writeAsBytes(bytes);
        },
        // Optional: custom picker instead of file_selector / image_picker
        // pickImage: () => myGalleryPicker(),
        // Limit tools:
        // enabledTools: [EditorTool.import, EditorTool.filters, EditorTool.export_],
      ),
    ),
  ));
}
```

The widget includes import, transform, filters, adjust, draw, overlay, export, and advanced (RGBA/GPU) tabs — same UI as the studio demo, configurable via [RustImageEditorConfig](rust_image/lib/src/editor/rust_image_editor_config.dart).

## Quick start — APIs only

Use [RustImageEditor] when you build your own UI and only need Rust processing:

```dart
await RustImageEditor.ensureInitialized();
final thumb = RustImageEditor.thumbnail(bytes: bytes, maxEdge: 512);
final filtered = RustImageEditor.filter(
  bytes: bytes,
  filter: const ImageFilter.blur(radius: 4),
);
```

See **[ROADMAP.md](../ROADMAP.md)** for the performance sprint plan (Phase 0–5).

## GPU vs CPU

With `ProcessingBackend.auto` (default) on macOS, **Metal** is used when the `gpu` feature is enabled:

| Operation | GPU (Metal) | CPU |
|-----------|-------------|-----|
| Resize / thumbnail | Yes (bilinear/nearest; not Lanczos) | `fast_image_resize` (full algorithms) |
| Brightness / contrast / saturation | Yes | photon-rs |
| Blur, sharpen, presets, hue, oil, etc. | No | photon-rs (direct RGBA, no PNG round-trip) |

Blur and most filters are **CPU-only** by design today; the editor keeps an **RGBA pipeline** and JPEG previews so filters avoid re-decoding JPEG/PNG each time.

## Example app

Runs the packaged [RustImageEditorWidget] (studio demo).

```bash
cd examples/image_editor
flutter run
```

## Android prerequisites

Install Rust via [rustup](https://rustup.rs) (not only Homebrew `rustc`). The repo includes `packages/rust_image_core/rust/rust-toolchain.toml` so Android targets are installed automatically.

If you see `can't find crate for core` / `aarch64-linux-android target may not be installed`:

```bash
rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android i686-linux-android
# If you use Homebrew Rust, unlink it so rustup is used:
# brew unlink rust
```

Then clean and rebuild:

```bash
cd examples/image_editor
flutter clean
flutter run
```

## Android / Gradle 9

If you see `Could not find method exec()` from `cargokit/gradle/plugin.gradle`, the bundled CargoKit script is already patched to use `ExecOperations` (required for Gradle 9+). The first Android build compiles Rust for each ABI and can take several minutes.

## Regenerate bindings

After changing `rust/src/api/*.rs`:

```bash
cd packages/rust_image_core
flutter_rust_bridge_codegen generate
```

## Project layout

```
packages/
├── rust_image_core/      # Rust core + FRB
│   └── rust/src/
│       ├── api/          # FRB exports
│       ├── resize.rs
│       ├── filters.rs
│       ├── exif.rs
│       └── ...
├── rust_image_editor/    # Editor UI (Riverpod)
│   └── lib/
│       └── ...
├── rust_gpu_texture/     # GPU Texture bridge
├── rust_camera_runtime/  # Live camera YUV stream
├── video_processor_core/ # Video Rust engine + FFmpeg
├── flutter_video_processor/ # Video compress/thumbnails SDK
├── rust_media_runtime/   # Media playback runtime
└── video_thumbnail_cache/ # Optional disk cache

examples/
├── image_editor/         # Image editor example app
└── media_studio/         # Video/audio editor showcase
```

## Roadmap

- **Phase 1** ✓ resize, thumbnail, crop, rotate, compress, EXIF, filters, draw/text, batch
- **Phase 2** ✓ BlurHash, AVIF, duotone presets, oil/glass/pixelize/solarize, overlay blend modes
- **Phase 3** ✓ RGBA buffer pipeline, progressive decode (preview JPEG + full RGBA), buffer pool, metadata probe
- **GPU** ✓ **wgpu** compute (Metal/Vulkan). `ProcessingBackend.gpu` / `.auto`. GPU today: resize, **blur**, **sharpen**, brightness/contrast/saturation/**hue**; presets, oil/glass, Lanczos export resize stay on CPU.
- **Perf tuning** — `RUST_IMAGE_RAYON_THREADS`, `RAYON_NUM_THREADS`, `RUST_IMAGE_NO_POOL` (see [ROADMAP.md](ROADMAP.md) Sprint 1.5).

### GPU API (Dart)

```dart
final gpu = RustImageEditor.gpuInfo();
if (gpu.available) {
  print('${gpu.api} — ${gpu.device}');
}

final thumb = RustImageEditor.thumbnail(
  bytes: bytes,
  maxEdge: 512,
  backend: ProcessingBackend.gpu, // or .auto
);
```

### Phase 2 API (Dart)

```dart
final hash = RustImageEditor.blurHashEncode(bytes);
final out = RustImageEditor.overlay(
  baseBytes: base,
  overlayBytes: logo,
  x: 40,
  y: 40,
  blendMode: BlendMode.multiply,
);
RustImageEditor.compress(bytes: bytes, format: OutputFormat.avif, quality: 75);
```

### Phase 3 API (Dart)

```dart
final info = RustImageEditor.probe(bytes);
final prog = RustImageEditor.decodeProgressive(bytes, previewMaxEdge: 128);
// Show prog.previewJpeg immediately, then edit prog.buffer:
var rgba = prog.buffer;
rgba = RustImageEditor.filterRgba(rgba, const ImageFilter.blur(radius: 3));
final jpeg = RustImageEditor.encodeRgba(rgba, format: OutputFormat.jpeg);
```

## Benchmarks

Cold API benchmarks (10 runs per op, CPU vs GPU, no caching) live in [`benchmark/`](benchmark/README.md).

**Rust CLI (fastest):**

```bash
cd packages/rust_image_core/rust
cargo run --release --features gpu --bin rust_image_benchmark -- --synthetic --iterations 10
```

**Dart / Flutter** (not `dart run`): `cd benchmark && ./run_dart_benchmark.sh` — use `BENCH_PIPELINE=worker` for the editor isolate path

See [benchmark/README.md](benchmark/README.md) for full options and CSV export.

## Running tests

`rust_image` ships three test layers. Run any of them individually, or run all
of them via the repo-root convenience script:

```bash
chmod +x test_all.sh   # one time
./test_all.sh
```

| Layer | Command | What it covers |
|-------|---------|----------------|
| Rust  | `cd packages/rust_image_core/rust && cargo test --features gpu,blurhash` | Core image API (resize, crop, rotate, EXIF, compress, filters, draw, overlay, blurhash, RGBA pipeline, edit graph, batch, pool, backend). |
| Dart unit | `cd packages/rust_image_editor && flutter test test/editor/` | Pure-Dart editor logic (edit graph, layer stack, filter descriptors, config defaults) — no device, no native lib. |
| Integration | `cd examples/image_editor && flutter test integration_test/ -d <device>` | End-to-end `RustImageEditor` API on a real Flutter engine (smoke, thorough, RGBA pipeline, edit pipeline, BlendMode matrix + BlurHash). Requires a connected device or simulator. |

### `test_all.sh` environment knobs

- `TEST_RUST_FEATURES` — cargo `--features` list for the Rust crate. Default
  `gpu,blurhash`. Set to `gpu,blurhash,avif` if your host has NASM and you want
  AVIF coverage; the AVIF encoder otherwise fails to build.
- `RUN_INTEGRATION=1` — enables the on-device integration layer (off by default
  because it needs a Flutter device/simulator and rebuilds native code).
- `TEST_DEVICE` — Flutter device id passed to `flutter test -d`. Default
  `macos`. Use `flutter devices` to list available targets.
- `SKIP_NATIVE_SYNC` — set to `1` to skip `cargo build` before Dart tests (faster).
  `test_all.sh` runs `cargo build` so `rust/target/debug/librust_image_core.dylib`
  matches the Rust API; `editor_widget_smoke_test` may still log an FRB content-hash
  warning because `flutter test` often loads a cached plugin dylib — that is harmless
  for the mount-only check. Use `RUN_INTEGRATION=1` for full FFI on a device.

Example: everything, including integration on the iOS simulator:

```bash
TEST_RUST_FEATURES=gpu,blurhash,avif RUN_INTEGRATION=1 TEST_DEVICE="iPhone 15" ./test_all.sh
```
