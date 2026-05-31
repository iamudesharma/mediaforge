---
name: project-workflows
description: Use when the user asks how to run any example in the repo, regenerate flutter_rust_bridge (FRB) bindings, run benchmarks, build FFmpeg, or rebuild native Rust for a specific platform. Covers media_studio, video_forge_kit, image_forge, media_forge, pixel_surface examples, Rust CLI benchmarks, and Dart benchmark suite.
---

# Project Workflows

## FRB codegen — regenerate Dart bindings after editing `rust/src/api/*.rs`

| Package | Command |
|---------|---------|
| `image_forge` | `cd packages/image_forge && flutter_rust_bridge_codegen generate` |
| `video_forge` | `cd packages/video_forge && flutter_rust_bridge_codegen generate` |
| `media_forge` | `cd packages/media_forge && flutter_rust_bridge_codegen generate` |

**Never edit** generated `frb_generated.rs`, `lib/src/rust/*.dart`, or `lib/src/frb_generated/*.dart`.

Some scripts run codegen automatically:
- `scripts/rebuild-video-native-macos.sh` → runs `video_forge` codegen
- `scripts/run-rust-media-macos.sh` → runs `media_forge` codegen

The legacy `rust_image/flutter_rust_bridge.yaml` and `rust video/native/rust_core/flutter_rust_bridge.yaml` are **not active** — do not use them.

---

## Running examples

### media_studio (main unified demo)

```bash
# macOS (with HW decode):
bash scripts/run-media-studio-macos.sh
# Skip native rebuild:
bash scripts/run-media-studio-macos.sh --no-rebuild

# iOS (physical device):
bash scripts/run-media-studio-ios.sh [device_id]

# Android (physical arm64):
bash scripts/run-media-studio-android.sh [device_id]
# All ABIs:
bash scripts/run-media-studio-android.sh --all [device_id]

# Manual (any platform):
cd examples/media_studio && flutter run -d macos
```

### video_forge_kit example

```bash
bash scripts/run-video-macos.sh
# Or:
cd packages/video_forge_kit/example && flutter run -d macos

# iOS:
./scripts/run-ios.sh [device_id]

# Android:
./scripts/run-android.sh [device_id]
./scripts/run-android.sh --all [device_id]
```

### media_forge example

```bash
# One-time FFmpeg build (VT-capable, ~30-60 min):
bash scripts/build-ffmpeg-macos-vt.sh

# Run:
bash scripts/run-rust-media-macos.sh

# Disable HW decode for A/B test:
VFP_DISABLE_HW_DECODE=1 flutter run -d macos
```

### mediaforge example

```bash
cd mediaforge/example && flutter run -d macos
```

### image_forge example

```bash
cd packages/image_forge/rust && cargo build --features gpu
cd ../example && flutter run -d macos
```

### pixel_surface example

```bash
cd packages/pixel_surface/example && flutter run -d macos
```

---

## Benchmarks

### Rust CLI (fastest, no Flutter)

```bash
cd packages/image_forge/rust
cargo run --release --features gpu --bin rust_image_benchmark -- --synthetic -n 10
# Single op:
cargo run --release --features gpu --bin rust_image_benchmark -- --synthetic -n 10 --only filter_rgba_blur --warmup 1
```

### Dart/Flutter benchmarks (must run inside Flutter, not `dart run`)

```bash
cd mediaforge/benchmark
./run_dart_benchmark.sh                     # direct FRB calls
BENCH_PIPELINE=worker ./run_dart_benchmark.sh  # editor isolate path
BENCH_PIPELINE=both ./run_dart_benchmark.sh    # both paths
./run_dart_benchmark.sh rust                   # Rust core only
./run_dart_benchmark.sh test                   # CI / headless
```

### Video CLI benchmarks

```bash
cd packages/video_forge
cargo run --release -p video_forge --bin vp_compress -- <args>
cargo run --release -p video_forge --bin vp_bench -- <args>
```

---

## Rebuild native Rust (no codegen)

| Platform | Script |
|----------|--------|
| macOS (video) | `bash scripts/rebuild-video-native-macos.sh` |
| iOS (image) | `bash scripts/rebuild-rust-image-ios.sh` |
| Android (image) | `bash scripts/rebuild-rust-image-android.sh` |
| Android (video) | `bash scripts/package-video-android.sh` |

---

## Full test suite

```bash
chmod +x test_all.sh && ./test_all.sh
```

Env knobs: `TEST_RUST_FEATURES` (default `gpu,blurhash`), `RUN_INTEGRATION=1`, `TEST_DEVICE` (default `macos`), `SKIP_NATIVE_SYNC=1`.

### Per-layer tests

```bash
# Rust image core
cd packages/image_forge/rust && cargo test --features gpu,blurhash

# Rust video core
cd packages/video_forge && cargo test -p video_forge

# Rust media runtime
cd packages/media_forge/rust && cargo test

# Dart unit tests (editor)
cd rust_image && flutter test test/editor/

# Dart unit tests (media runtime)
cd packages/media_forge && flutter test

# Dart integration
cd mediaforge/example && flutter test integration_test/ -d <device>
```

### Melos analyze

```bash
dart run melos analyze
# Per-package:
dart run melos exec --scope=image_forge_editor -- flutter analyze lib test --no-fatal-infos --no-fatal-warnings
```
