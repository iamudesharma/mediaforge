# P0 — Pre-publish acceptance checklist

Use this before the first pub.dev release of the four-package split. See [PUB_PACKAGE_SPLIT.md](PUB_PACKAGE_SPLIT.md).

---

## Package demos

| Check | Command / path |
|-------|----------------|
| **rust_gpu_texture** — Texture only, no core | `cd packages/rust_gpu_texture/example && flutter run -d macos` |
| **rust_image_core** — RGBA filter + JPEG export | `cd packages/rust_image_core/example && flutter run -d macos` |
| **rust_image_editor** — full UI | `cd rust_image/example && flutter run -d macos` |
| **rust_camera_runtime** — unit smoke | `cd packages/rust_camera_runtime && flutter test` |

### Engine CLI (no Flutter UI)

```bash
cd packages/rust_image_core/rust
cargo run --release --features gpu --bin rust_image_benchmark -- \
  --synthetic -n 5 --only filter_rgba_brightness
```

---

## CI (monorepo root)

```bash
dart pub get && dart run melos bootstrap
dart run melos exec --scope=rust_gpu_texture -- flutter test
dart run melos exec --scope=rust_camera_runtime -- flutter test
cd packages/rust_image_core/rust && cargo build --features gpu
cd ../../rust_image_editor && flutter test
```

---

## Dependency boundaries

- [x] `rust_gpu_texture` has no `rust_image_core` in `pubspec.yaml`
- [x] `rust_image_core` has no editor / Riverpod / `camera`
- [x] `rust_image_editor` does not list `camera` / `permission_handler` directly — uses `rust_camera_runtime`
- [x] `rust_camera_runtime` has no editor widgets

---

## Platform matrix

See [PACKAGE_PLATFORM_MATRIX.md](PACKAGE_PLATFORM_MATRIX.md).

---

## Docs per package

| Package | README | CHANGELOG | Example |
|---------|--------|-----------|---------|
| `rust_gpu_texture` | [packages/rust_gpu_texture/README.md](../packages/rust_gpu_texture/README.md) | [CHANGELOG.md](../packages/rust_gpu_texture/CHANGELOG.md) | [example/](../packages/rust_gpu_texture/example/) |
| `rust_image_core` | [packages/rust_image_core/README.md](../packages/rust_image_core/README.md) | [CHANGELOG.md](../packages/rust_image_core/CHANGELOG.md) | [example/](../packages/rust_image_core/example/) |
| `rust_image_editor` | [packages/rust_image_editor/README.md](../packages/rust_image_editor/README.md) | [CHANGELOG.md](../packages/rust_image_editor/CHANGELOG.md) | [rust_image/example/](../rust_image/example/) |
| `rust_camera_runtime` | [packages/rust_camera_runtime/README.md](../packages/rust_camera_runtime/README.md) | [CHANGELOG.md](../packages/rust_camera_runtime/CHANGELOG.md) | (via editor Beauty → Live camera) |

---

## Perf matrix (studio)

After editor changes, run scenarios in [ROADMAP.md](../ROADMAP.md#perf-matrix) on **rust_image Studio** (`rust_image/example`).

---

*Last updated: P0.6*
