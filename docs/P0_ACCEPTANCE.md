# P0 — Pre-publish acceptance checklist

Use this before the first pub.dev release of the four-package split. See [PUB_PACKAGE_SPLIT.md](PUB_PACKAGE_SPLIT.md).

---

## Package demos

| Check | Command / path |
|-------|----------------|
| **pixel_surface** — Texture only, no core | `cd packages/pixel_surface/example && flutter run -d macos` |
| **image_forge** — RGBA filter + JPEG export | `cd packages/image_forge/example && flutter run -d macos` |
| **image_forge_editor** — full UI | `cd mediaforge/example && flutter run -d macos` |
| **image_forge_camera** — unit smoke | `cd packages/image_forge_camera && flutter test` |

### Engine CLI (no Flutter UI)

```bash
cd packages/image_forge/rust
cargo run --release --features gpu --bin rust_image_benchmark -- \
  --synthetic -n 5 --only filter_rgba_brightness
```

---

## CI (monorepo root)

```bash
dart pub get && dart run melos bootstrap
dart run melos exec --scope=pixel_surface -- flutter test
dart run melos exec --scope=image_forge_camera -- flutter test
cd packages/image_forge/rust && cargo build --features gpu
cd ../../image_forge_editor && flutter test
```

---

## Dependency boundaries

- [x] `pixel_surface` has no `image_forge` in `pubspec.yaml`
- [x] `image_forge` has no editor / Riverpod / `camera`
- [x] `image_forge_editor` does not list `camera` / `permission_handler` directly — uses `image_forge_camera`
- [x] `image_forge_camera` has no editor widgets

---

## Platform matrix

See [PACKAGE_PLATFORM_MATRIX.md](PACKAGE_PLATFORM_MATRIX.md).

---

## Docs per package

| Package | README | CHANGELOG | Example |
|---------|--------|-----------|---------|
| `pixel_surface` | [packages/pixel_surface/README.md](../packages/pixel_surface/README.md) | [CHANGELOG.md](../packages/pixel_surface/CHANGELOG.md) | [example/](../packages/pixel_surface/example/) |
| `image_forge` | [packages/image_forge/README.md](../packages/image_forge/README.md) | [CHANGELOG.md](../packages/image_forge/CHANGELOG.md) | [example/](../packages/image_forge/example/) |
| `image_forge_editor` | [packages/image_forge_editor/README.md](../packages/image_forge_editor/README.md) | [CHANGELOG.md](../packages/image_forge_editor/CHANGELOG.md) | [mediaforge/example/](../mediaforge/example/) |
| `image_forge_camera` | [packages/image_forge_camera/README.md](../packages/image_forge_camera/README.md) | [CHANGELOG.md](../packages/image_forge_camera/CHANGELOG.md) | (via editor Beauty → Live camera) |

---

## Perf matrix (studio)

After editor changes, run scenarios in [ROADMAP.md](../ROADMAP.md#perf-matrix) on **mediaforge Studio** (`mediaforge/example`).

---

*Last updated: P0.6*
