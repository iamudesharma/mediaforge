# mediaforge benchmarks

## Why not `dart run` or plain Node?

| Your other project | This project |
|--------------------|--------------|
| Node/Bun runs a `.ts` script that loads a native `.node` addon | Flutter loads Rust via **flutter_rust_bridge** inside a **Flutter engine** |
| `node benchmark.js` | `flutter run -t lib/benchmark_main.dart` (this repo’s equivalent) |

Plain **`dart run` does not work** here: the Dart VM’s FFI compiler crashes on FRB-generated code. Benchmarks must run inside **Flutter** (real app or `flutter test` for CI).

**`flutter test` is not the main path** — it’s a headless shortcut for CI. For “how does it perform in Flutter?”, use the **Flutter app entry** below.

---

## What to run (Flutter — recommended)

From `mediaforge/benchmark`:

```bash
chmod +x run_dart_benchmark.sh   # once

# Direct FRB calls (main isolate)
./run_dart_benchmark.sh

# Editor hot path: background isolate + preview JPEG (what the UI uses)
BENCH_PIPELINE=worker ./run_dart_benchmark.sh

# Both tables printed
BENCH_PIPELINE=both ./run_dart_benchmark.sh
```

This runs `example/lib/benchmark_main.dart` with **`flutter run --release`** on macOS:

- Same **Flutter engine** and **plugin-linked** `image_forge` as the editor app  
- Not the test runner, not a loose `dart` VM  

Optional env:

| Variable | Default | Meaning |
|----------|---------|---------|
| `BENCH_ITERATIONS` | `10` | Runs per operation |
| `BENCH_SYNTHETIC` | `1` | 1280×720 test JPEG |
| `BENCH_IMAGE` | — | Real photo path |
| `BENCH_PIPELINE` | `direct` | `direct` \| `worker` \| `both` |
| `BENCH_DEVICE` | `macos` | `flutter run -d` target |
| `BENCH_CSV` | — | Write CSV (suffix `_direct` / `_worker`) |

Manual equivalent:

```bash
cd mediaforge/example
BENCH_PIPELINE=worker flutter run -d macos -t lib/benchmark_main.dart --release
```

### Pipelines explained

1. **`direct`** — `RustImageEditor.*` on the **main isolate**. Measures FRB + Rust only (no worker queue).
2. **`worker`** — `RustWorker.*` on a **Squadron worker pool** (2–4 isolates) + preview encode. This is what **live filters and preview** use in the editor.

Use **`worker`** when you care about slider/filter responsiveness in the app.

---

## Rust core only (no Flutter)

Fastest; no Dart/FRB/isolate overhead:

```bash
cd packages/image_forge/rust
cargo run --release --features gpu --bin image_forge_benchmark -- --synthetic -n 10
```

Or: `./run_dart_benchmark.sh rust`

### Phase 0+1 runbook (comparable numbers)

| Goal | Command |
|------|---------|
| Full suite | `cargo run --release --features gpu --bin image_forge_benchmark -- --synthetic -n 10 --warmup 1` |
| One operation | `... --only filter_rgba_blur -n 10 --warmup 2` |
| App-like preview | `... --preview-profile fast` |
| Stress preview | `... --preview-profile quality` |
| Reduce cross-op noise | `... --cooldown-ms 200` |
| Cap Rayon | `RAYON_NUM_THREADS=8` or `RUST_IMAGE_RAYON_THREADS=4 cargo run --release ...` |
| Pool off (A/B) | `RUST_IMAGE_NO_POOL=1 cargo run --release ...` |

Report columns include **median**, **p95**, **path** (`cpu_parallel`, `gpu_blur`, `gpu_resize`, …), **build profile**, and **RAYON_NUM_THREADS**.

Always use **`--release`** and AC power. Warmup iterations are discarded (default `1`) so GPU/Metal is not cold on iteration 1.

---

## CI / headless (`flutter test`)

Loads a release `.dylib` manually; good for automation, **not** identical to a release macOS app link:

```bash
./run_dart_benchmark.sh test
```

---

## What is *not* measured

- Widget rebuilds, `Image.memory`, animation frames  
- Full editor session (undo stack, multiple tabs)  

For that: profile the example app with **Flutter DevTools** while editing. These benchmarks isolate **image API + isolate pipeline** cost.
