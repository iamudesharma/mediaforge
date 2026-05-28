# AGENTS.md

Instructions for AI agents working in this repository.

## Monorepo layout

- **Dart workspace** managed by `melos` (root `pubspec.yaml` has `melos:` config)
- **Two Rust crates** — not a single Cargo workspace:
  - `packages/rust_image_core/rust/` — image processing engine (standalone `Cargo.toml`)
  - `packages/video_processor_core/rust/` — video engine (workspace root at `packages/video_processor_core/Cargo.toml`, member `rust/`)
- `**rust_image/`** is a thin shim that re-exports `rust_image_editor`. Do not add logic there.

## Package boundaries


| Package                   | Role                          | Depends on                                                   |
| ------------------------- | ----------------------------- | ------------------------------------------------------------ |
| `rust_gpu_texture`        | GPU Texture bridge only       | —                                                            |
| `rust_image_core`         | Rust engine + FRB APIs        | `rust_gpu_texture`                                           |
| `rust_image_editor`       | Editor UI (Riverpod)          | `rust_image_core`, `rust_gpu_texture`, `rust_camera_runtime` |
| `rust_camera_runtime`     | Live camera YUV stream        | —                                                            |
| `video_processor_core`    | Video Rust engine + FFmpeg    | —                                                            |
| `flutter_video_processor` | Video compress/thumbnails SDK | `video_processor_core`                                       |
| `video_thumbnail_cache`   | Optional disk cache           | —                                                            |


## Build & test commands

### Full test suite (repo root)

```bash
chmod +x test_all.sh   # one time
./test_all.sh
```

Env knobs: `TEST_RUST_FEATURES` (default `gpu,blurhash`), `RUN_INTEGRATION=1`, `TEST_DEVICE` (default `macos`), `SKIP_NATIVE_SYNC=1`.

### **Per-layer commands**


| **Layer**                | **Command**                                                              |
| ------------------------ | ------------------------------------------------------------------------ |
| Rust image core          | `cd packages/rust_image_core/rust && cargo test --features gpu,blurhash` |
| Rust video core          | `cd packages/video_processor_core && cargo test -p video_processor_core` |
| Dart unit tests (editor) | `cd rust_image && flutter test test/editor/`                             |
| Dart integration         | `cd rust_image/example && flutter test integration_test/ -d <device>`    |
| Dart analyze (all)       | `dart run melos analyze`                                                 |


### **Per-package analyze via melos**

```
dart run melos exec --scope=rust_image_editor -- flutter analyze lib test --no-fatal-infos --no-fatal-warnings
dart run melos exec --scope=rust_gpu_texture -- flutter analyze --no-fatal-infos
```

### **Benchmarks**

**Rust CLI (fastest, no Flutter):**

```
cd packages/rust_image_core/rust
cargo run --release --features gpu --bin rust_image_benchmark -- --synthetic -n 10
```

**Dart/Flutter benchmarks** — must run inside Flutter, not `dart run` (FRB code crashes the standalone Dart VM):

```
cd rust_image/benchmark && ./run_dart_benchmark.sh
BENCH_PIPELINE=worker ./run_dart_benchmark.sh   # editor isolate path
```

## **FRB codegen**

After editing `rust/src/api/*.rs`, regenerate Dart bindings:

```
cd packages/rust_image_core
flutter_rust_bridge_codegen generate
```

Output goes to `lib/src/rust/`. **Never edit generated** `frb_generated.rs` **or** `lib/src/rust/*.dart` — they are overwritten.

FRB config per package: `flutter_rust_bridge.yaml` (rust_input: `crate::api`, dart_output: `lib/src/rust`).

## **Gotchas**

- **AVIF encoder needs NASM** — builds fail on hosts without it. Use `TEST_RUST_FEATURES=gpu,blurhash` (no avif) unless NASM is installed.
- **Android builds require** `rustup`, not Homebrew `rustc`. The repo has `rust/rust-toolchain.toml` for auto-installing Android targets. If you see `can't find crate for core`, run `rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android i686-linux-android`.
- **Two Rust workspace roots** — `packages/rust_image_core/rust/` is standalone; `packages/video_processor_core/Cargo.toml` is a workspace root with `rust/` member. `rust video/` is legacy — ignore it.
- `dart run` **does not work** for FRB-based benchmarks or apps. Always use `flutter run` or `flutter test`.
- **First Android build** compiles Rust for each ABI — can take several minutes.
- **Melos bootstrap** required after cloning: `dart pub get && dart run melos bootstrap`.

## **CI**

`.github/workflows/ci.yml` runs on `ubuntu-latest`: melos bootstrap → per-package analyze → per-package test → Rust video test. No native build step in CI (Dart-only checks).