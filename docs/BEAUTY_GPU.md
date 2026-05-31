# Beauty GPU & texture residency (Sprint 22)

Design for moving regional beauty off the CPU hot path onto **wgpu** (`GpuEditSurface`), with optional Flutter **Texture** display.

**Related:** [PHASE3_MEDIAPIPE.md](PHASE3_MEDIAPIPE.md), [ROADMAP.md](../ROADMAP.md) Sprint 22.

---

## Architecture

```text
Edit base → upload GpuEditSurface
  → face_warp.wgsl (optional)
  → lip_plump / skin / eye / lip / blush / under_eye / teeth (WGSL)
  → Display:
      Texture (macOS / iOS / Android + useGpuTexturePreview): updateTexture, previewRgba = null
      RGBA only: single readback → RgbaPreviewImage
  → Export / compare: readback on demand
```

---

## Gating (Dart)

| Helper | Meaning |
|--------|---------|
| `_gpuBeautyComputeAvailable()` | `gpu::is_available()` and backend ≠ `cpu` |
| `_gpuBeautyDisplayViaTexture()` | `useGpuTexturePreview` && `GpuTextureRegistry.isSupported` |

`GpuTextureRegistry.isSupported`: **macOS, iOS, Android**.

---

## Phases

| Phase | Status | Notes |
|-------|--------|-------|
| **22.1** | Done | GPU compute without requiring Texture |
| **22.2** | Done | Still preview: `previewRgba = null` when Texture active; `LivePreview` prefers `GpuTexturePreview` |
| **22.3** | Done | `under_eye.wgsl`, `lip_plump.wgsl`, `face_warp.wgsl`; no CPU readback in `apply_surface_beauty_pipeline` |
| **22.4** | Done | `RustImageTexturePlugin.kt` + registry on Android |
| **22.5** | Planned | Fewer re-uploads when only `BeautyParams` change |
| **22.6** | Planned | Benchmarks + perf matrix G/H |

---

## WGSL shaders (`rust/src/gpu/shaders/`)

| Shader | Effect |
|--------|--------|
| `skin_smooth.wgsl` | Frequency-style smooth |
| `eye_brighten.wgsl` | Eye lift |
| `lip_tint.wgsl` | HSL lip tint |
| `blush.wgsl` | Cheek blush |
| `teeth_whiten.wgsl` | Teeth lift |
| `under_eye.wgsl` | Under-eye box blur blend |
| `lip_plump.wgsl` | Radial lip warp |
| `face_warp.wgsl` | Landmark radial warp passes |

Status suffixes: `gpu_skin`, `gpu_eye`, `gpu_lip`, `gpu_plump`, `gpu_under_eye`, `gpu_beauty`.

---

## Host config

```dart
RustImageEditorConfig(
  useRgbaPreview: true,
  useGpuTexturePreview: true,   // Texture on Apple + Android; optional on Android if RGBA-only is OK
  defaultBackend: ProcessingBackend.auto,
  showPerformanceInStatus: true,
)
```

- **Android:** GPU beauty runs with `useRgbaPreview: true` even when `useGpuTexturePreview: false`. Set `useGpuTexturePreview: true` for `Texture` display (Phase 4).
- **Apple:** Enable both for best still-photo slider performance (no `RgbaPreviewImage` rebuild per tick).

---

## Verification

| Scenario | Expect |
|----------|--------|
| **G** Lip slider | `gpu_beauty` · `gpu_lip`; panel stable (Riverpod) |
| **H** Live camera | Texture path on Apple/Android when enabled; ≥ 24 fps |
| Rust bench | `cargo run --release --features gpu --bin rust_image_benchmark -- --only beauty_skin_smooth_gpu` |

---

## Key files

| Layer | Path |
|-------|------|
| Session | `rust_image/lib/src/editor/editor_session.dart` |
| Texture registry | `rust_image/lib/src/editor/services/gpu_texture_registry.dart` |
| Android texture | `rust_image/android/.../RustImageTexturePlugin.kt` |
| Apple texture | `rust_image/macos/Classes/RustImageTexturePlugin.swift` |
| GPU surface | `packages/image_forge/rust/src/gpu/surface.rs`, `beauty_pass.rs` |

*Last updated: Sprint 22 Phases 1–4*
