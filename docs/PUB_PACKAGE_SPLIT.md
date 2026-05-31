# pub.dev package split (pre-publish architecture)

**Status:** P0.1–P0.6 **done** (structural + docs/examples) — `packages/image_forge_editor` has all `lib/src/editor/` UI; `rust_image` is a thin re-export shim. Engine: `image_forge`. Texture: `pixel_surface`. Camera: `image_forge_camera`. `GpuEditSurface` / wgpu still in `image_forge/rust` until moved to `pixel_surface/rust`.

**Goal:** Four independently versioned packages with hard dependency boundaries. Host apps choose only what they need (texture-only, engine-only, full editor, or camera SDK).

**Related:** [ROADMAP.md](../ROADMAP.md) — Sprint P0 (Package split), current [mediaforge/README.md](../mediaforge/README.md).

---

## Why split now

| Problem (monolith `rust_image`) | After split |
|----------------------------------|-------------|
| Texture + editor + camera ship one version line | Patch texture without touching Beauty UI |
| Apps that only need GPU preview pull camera, Riverpod, image_picker | Minimal transitive deps |
| Breaking FRB API forces editor widget major bump | `image_forge` majors independently |
| Camera permissions / MediaPipe bloat desktop & web editor consumers | Camera is opt-in via `image_forge_camera` |
| Hard to reuse `GpuEditSurface` in non-editor products | `pixel_surface` is a first-class SDK |

---

## Target packages

```text
                    ┌─────────────────────┐
                    │  image_forge_editor  │  ← app-facing Instagram UI
                    │  (Flutter only)     │
                    └──────────┬──────────┘
           ┌───────────────────┼───────────────────┐
           ▼                   ▼                   ▼
┌──────────────────┐  ┌─────────────────┐  ┌──────────────────────┐
│ pixel_surface     │  │ image_forge     │  │ image_forge_camera  │
│ Texture + wgpu   │  │ Engine (Rust)   │  │ Live camera SDK      │
│ surface bridge   │  │ FRB API layer   │  │ (optional, later)    │
└────────┬─────────┘  └────────┬────────┘  └──────────┬───────────┘
         │                     │                       │
         └─────────────────────┴───────────────────────┘
                               │
                    image_forge (Rust crate)
                    may depend on pixel_surface crate
```

### Package 1 — `pixel_surface`

**Purpose:** Reusable GPU-resident frame display — no editor, filters, or beauty.

| In scope | Out of scope |
|----------|----------------|
| `TextureRegistry` / platform texture bridge | Edit graph, filters, mood LUT |
| `GpuEditSurface` (wgpu device, ping-pong, resize) | Beauty / face / MediaPipe |
| Metal / Vulkan interop via wgpu | Crop UI, layers, Riverpod |
| CVPixelBuffer (Apple) / `SurfaceTexture` (Android) bridge | JPEG preview widget |
| Flutter `Texture` widget + frame scheduling | Squadron workers |
| Texture lifecycle, surface resize, GPU↔Flutter sync | Camera capture |

**Consumers:** camera apps, video players, realtime AI preview, game overlays, shader demos, `image_forge_editor`, `image_forge_camera`.

**Current code to extract (indicative):**

| Area | Today |
|------|--------|
| Rust | `packages/image_forge/rust/src/gpu/surface.rs`, texture-related `api/texture.rs`, minimal `gpu/mod.rs` engine singleton |
| Dart | `lib/src/editor/services/gpu_texture_registry.dart`, `widgets/gpu_texture_preview.dart` |
| Native | `darwin/Classes/RustImageTexturePlugin.swift`, `android/.../RustImageTexturePlugin.kt` |

**pub.dev surface (sketch):**

```dart
import 'package:pixel_surface/pixel_surface.dart';

final handle = await GpuTextureRegistry.register(width: w, height: h);
// Rust: upload RGBA / bind external texture, present frame
GpuTextureView(textureId: handle.textureId);
```

---

### Package 2 — `image_forge`

**Purpose:** Image processing engine — Rust + FRB APIs only. No Flutter widgets, no `Texture` widget.

| In scope | Out of scope |
|----------|----------------|
| Edit graph, undo model (Rust) | `RustImageEditorWidget`, panels, gestures |
| Filters, resize, crop, rotate, encode/decode | `GpuTexturePreview`, `LivePreview` |
| GPU shader pipeline (`wgpu`, all `.wgsl` except texture-only infra) | `camera`, `permission_handler`, `image_picker` |
| Overlays, paint rasterization, layers bake | Riverpod shell |
| Beauty, face masks, warp (engine) | Live camera orchestration (→ package 4) |
| FRB generated Dart under `src/rust/` | Platform texture plugins (→ package 1) |

**Note:** The Rust crate is **already** named `image_forge` (`packages/image_forge/rust/Cargo.toml`). Publishing means splitting it from the Flutter plugin tree and declaring a dependency from `pixel_surface` for surface operations.

**Current code (stays in engine):**

- `rust/src/` — `filters/`, `face/`, `gpu/beauty_pass.rs`, `gpu/shaders/*`, `layers.rs`, `decode.rs`, `api/*` (except texture moves to P1)
- `lib/src/rust/` — FRB bindings only
- `lib/src/editor/services/rust_worker_service.dart` — moves to editor or thin `image_forge_flutter` helper; engine stays isolate-agnostic

**Dependency:** `pixel_surface` (Rust crate + optional Flutter FRB re-export) for `GpuEditSurface` upload/readback used by filter and beauty pipelines.

---

### Package 3 — `image_forge_editor`

**Purpose:** Drop-in Instagram-style editor — the product most apps import today.

| In scope | Out of scope |
|----------|----------------|
| `RustImageEditorWidget`, `RustImageEditorConfig` | Low-level wgpu setup |
| Tool panels, crop overlay, swipe mood/beauty | Raw FRB types (re-exported) |
| Riverpod providers (`editor_providers.dart`) | Texture plugin native code |
| Layer stack UI, paint canvas, export sheet | Rust benchmark binary (stays in repo / `image_forge` dev) |
| Editor session, coalesce, status line | |

**Dependencies (target):**

```yaml
dependencies:
  pixel_surface: ^x.y.z
  image_forge: ^x.y.z   # FRB + thin Dart helpers
  flutter_riverpod: ...
  # file_selector, gal, etc. — editor-only UX deps
```

**Optional dependency:**

```yaml
image_forge_camera: ^x.y.z   # only if Beauty → Live camera enabled
```

**Migration:** Rename / republish current `rust_image` pub package as `image_forge_editor`, or ship a deprecation shim:

```yaml
# rust_image 1.0.0 — meta re-export (one release cycle)
dependencies:
  image_forge_editor: ^1.0.0
```

---

### Package 4 — `image_forge_camera` (later)

**Purpose:** Realtime front-camera SDK — not embedded in the editor package.

| In scope | Out of scope |
|----------|----------------|
| YUV → RGBA (platform / Rust) | Full editor chrome |
| Texture-only preview path | Export graph replay |
| `TemporalSmoother`, analyze cadence | Filters tab, crop, layers |
| MediaPipe / Vision / ML Kit orchestration | Desktop editor default deps |
| Landmark debug overlay hooks | Web editor (camera optional) |
| Dedicated camera worker / isolate contract | |

**Why separate:** Nexus live pipeline is already a product-sized stack ([PHASE3_MEDIAPIPE.md](PHASE3_MEDIAPIPE.md), Sprint Nexus A). Keeping it inside `image_forge_editor` will:

- Slow editor releases on camera-only fixes
- Force `camera` + `permission_handler` on static-photo apps
- Complicate platform matrix (Android GPU texture vs iOS vs desktop none)
- Block web/desktop editor builds that should not link camera natives

**Current code to extract (indicative):**

| Area | Today |
|------|--------|
| Dart | `packages/image_forge_camera/lib/src/` — `live_camera_service.dart`, `camera_permission.dart`, `temporal_face_smoother.dart` |
| Rust | `api/temporal.rs`, live upload paths in session that bypass JPEG |
| Native | MediaPipe analyzers, face plugins (may stay shared with core face **analysis** API; runtime owns **stream** wiring) |

**Depends on:** `pixel_surface`, `image_forge` (beauty on surface), optional face analysis FRB.

---

## Hard boundaries (enforced in review)

1. **`pixel_surface` must not** import `face/`, `filters/`, or `edit_graph`.
2. **`image_forge` must not** import `package:flutter` or register `TextureRegistry`.
3. **`image_forge_editor` must not** duplicate wgpu device creation — only call core + texture APIs.
4. **`image_forge_camera` must not** import editor panels or Riverpod; exposes a small Dart API (`CameraBeautySession`, `CameraPreview`, etc.).
5. **Face analysis** (still image) stays in core; **frame loop + smoothing** stays in camera runtime.

---

## Migration phases (recommended order)

| Phase | Deliverable | Rationale |
|-------|-------------|-----------|
| **P0.1** | Monorepo layout + CI per crate | `packages/pixel_surface`, `packages/image_forge`, `packages/image_forge_editor` |
| **P0.2** | Extract `pixel_surface` | Clearest boundary; unblocks non-editor users; Sprint 22 texture code is fresh |
| **P0.3** | **`packages/image_forge`** — engine + FRB + ffi plugin; `rust_image` path-dep only | **Done** — crates.io publish deferred; `pixel_surface` Rust path dep wired |
| **P0.4** | **`packages/image_forge_editor`**; `rust_image` re-exports editor | **Done** |
| **P0.5** | Extract `image_forge_camera` | **Done** — [`packages/image_forge_camera/`](packages/image_forge_camera/); editor depends on it; `camera` / `permission_handler` removed from editor |
| **P0.6** | Docs, example apps per package, perf matrix per crate | **Done** — [P0_ACCEPTANCE.md](P0_ACCEPTANCE.md), [PACKAGE_PLATFORM_MATRIX.md](PACKAGE_PLATFORM_MATRIX.md), per-package CHANGELOG |

**Do not** extract camera before texture + core boundaries are stable — camera is the highest coupling point.

---

## Versioning & breaking changes

| Package | Semver policy |
|---------|----------------|
| `pixel_surface` | Breaking: texture handle API, sync contract, min SDK |
| `image_forge` | Breaking: FRB types, `EditGraph` serialization, shader uniforms |
| `image_forge_editor` | Breaking: widget config, panel UX, provider names |
| `image_forge_camera` | Breaking: stream config, permission model |

**Pre-1.0:** Current `0.1.0` monolith can ship one `0.2.0` with split **or** go straight to `1.0.0` multi-package — prefer **no pub.dev publish** until P0.2–P0.4 complete so first public release is already split.

---

## Repository layout (target)

```text
mediaforge/                          # git monorepo (unchanged root)
├── packages/
│   ├── pixel_surface/            # Flutter plugin + rust/gpu_texture/
│   ├── image_forge/             # rust/ + lib/src/rust/ (FRB)
│   ├── image_forge_editor/           # lib/src/editor/ + example/
│   └── image_forge_camera/         # P0.5
├── docs/
│   ├── PUB_PACKAGE_SPLIT.md         # this file
│   └── ...
└── ROADMAP.md
```

Melos or plain `path:` dependencies for local dev; pub.dev publishes from each `packages/*/pubspec.yaml`.

---

## Acceptance (ready to publish)

- [x] `pixel_surface` example: animated RGBA gradient in `Texture` with no `image_forge` — [`packages/pixel_surface/example/`](packages/pixel_surface/example/)
- [x] `image_forge` example: RGBA filter + JPEG — [`packages/image_forge/example/`](packages/image_forge/example/); CLI via `rust_image_benchmark`
- [x] `image_forge_editor` package: editor UI + tests; studio demo via `mediaforge/example` (shim dep)
- [x] Editor `pubspec` does not depend on `camera` / `permission_handler` directly — via `image_forge_camera`
- [x] README per package with platform matrix — [PACKAGE_PLATFORM_MATRIX.md](PACKAGE_PLATFORM_MATRIX.md)
- [x] CHANGELOG per package; root README links all four

---

## Mapping from today's monolith

| Today (`mediaforge/`) | Target package |
|------------------------|----------------|
| `rust/` crate `image_forge` | **Package 2** (crate root moves) |
| `gpu/surface.rs`, texture API, texture plugins | **Package 1** |
| `lib/src/editor/*` | **Package 3** |
| `live_camera_service.dart`, temporal smoother | **Package 4** (`image_forge_camera`) |
| YUV→RGBA camera worker (`convertCameraImage`) | **Package 3** for now (Squadron in editor) |
| `face/` analysis (still) | **Package 2** |
| `face/` smoothing + live mask stabilize | **Package 4** (calls core masks) |
| `benchmark/` | Repo tool; depends on **Package 2** |

---

## References

- GPU texture (today): [BEAUTY_GPU.md](BEAUTY_GPU.md), Sprint 11b.2 / 22 in [ROADMAP.md](../ROADMAP.md)
- Face / live camera: [PHASE3_MEDIAPIPE.md](PHASE3_MEDIAPIPE.md)
- Flutter rebuild rules: [FLUTTER_STATE.md](FLUTTER_STATE.md)

*Last updated: P0.6 complete (pre-pub.dev)*
