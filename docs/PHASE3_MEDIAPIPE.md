# Phase 3 — Face beauty & AR (Sprint 12 → Nexus)

Design reference for regional face effects (beauty, makeup, Snapchat-style AR). Depends on **Sprint 11b.2** GPU texture preview for live camera ingress.

**Status:** Sprint 12 static beauty **shipped** (skin smooth, Vision landmarks). **Nexus** is the next multi-sprint track: live camera + regional makeup + one-tap beauty looks.

---

## Goals (end state)

- **Face Landmarker** — MediaPipe Tasks 468-point mesh (upgrade from Vision ~87 pts)
- **Image Segmenter** — selfie / person mask (R8 edit-res), intersected with landmark regions
- **Temporal smoothing** — EMA on landmarks (α ≈ 0.25) + mask morphological stabilize (live)
- **Regional GPU filters** on `GpuEditSurface` — skin, eyes, lips, blush
- **Beauty looks** — Instagram / Snapchat-style one-tap presets + optional fine-tune sliders
- **Live camera** — front camera → texture preview at 24–30 fps

---

## Architecture

```text
Camera frame / still import → GpuEditSurface (11b.2)
  ↓
Native face pipeline (Vision v1 → MediaPipe Tasks in Nexus A)
  ↓
FaceAnalysisResult (FRB): landmarks[], segmentation R8, faceContourCount, confidence
  ↓
TemporalSmoother (live only): EMA landmarks + mask stabilize
  ↓
build_*_mask (Rust regions.rs): skin | eyes | lips | blush
  ↓
Regional passes (CPU v1 → GPU WGSL in Nexus D):
  skin_smooth | eye_brighten | lip_tint | lip_plump | blush
  ↓
Optional BeautyLookPreset recipe (bundled strengths)
  ↓
Flutter Texture / RGBA preview → encode once on export
```

---

## Platform integration

| Platform | Stack |
|----------|--------|
| iOS / macOS | Vision (v1) → MediaPipe Tasks Swift (Nexus A) → `MethodChannel('rust_image/face')` → FRB |
| Android | MediaPipe AAR + Kotlin Tasks API (Nexus D) |
| Desktop fallback | Vision on Apple; no-op beauty on other desktops |

Models: optional download via [`scripts/download_mediapipe_models.sh`](../mediaforge/scripts/download_mediapipe_models.sh) → `darwin/Resources/mediapipe/`.

---

## Rust module (`src/face/`)

| Module | Role |
|--------|------|
| `landmark.rs` | Normalized 2D points; region index tables (Vision + MP 468) |
| `regions.rs` | Rasterize soft masks: skin, eyes, lips (outer/inner), blush cheeks |
| `beauty.rs` | Skin frequency-separation smooth (shipped) |
| `makeup.rs` | **Nexus B** — eye brighten, lip HSL tint, cheek blush (CPU) |
| `warp.rs` | **Nexus B** — lip plump / thin via localized radial warp (edit-res) |
| `looks.rs` | **Nexus C** — `BeautyLookPreset` + parametric recipes |
| `smoothing.rs` | `TemporalSmoother` for live camera |

---

## Dart / UI

| Piece | Sprint |
|-------|--------|
| [`FaceAnalysisService`](../rust_image/lib/src/editor/services/face_analysis_service.dart) | 12 ✓ |
| [`BeautyPanel`](../rust_image/lib/src/editor/panels/beauty_panel.dart) — skin smooth | 12 ✓ |
| **Beauty looks strip** — horizontal preset chips (Natural, Soft, Glow, Glam, …) | Nexus C |
| **Fine-tune section** — collapsible sliders per region | Nexus B/C |
| Live camera tool / ingress | Nexus A |
| Debug mesh overlay (dev flag) | Nexus A |

### Beauty panel UX (target)

```text
┌─ Beauty ─────────────────────────────────────┐
│  [Natural] [Soft] [Glow] [Glam] [Peach] …   │  ← one-tap looks (Nexus C)
│  ─────────────────────────────────────────── │
│  Skin smooth      ████████░░  80%            │
│  Eye brighten     ███░░░░░░░  30%            │  ← Nexus B
│  Lip color        ● ○ ○ ○ ○  + strength      │
│  Lip size         ████░░░░░░  40%            │  ← warp; subtle by default
│  Blush            ██░░░░░░░░  20%            │
│  [Re-analyze face]                           │
└──────────────────────────────────────────────┘
```

Presets set all sliders; user can override any slider after picking a look (committed to `EditGraph` beauty slot as structured params, not separate graph ops per slider).

---

## Static photo path (Sprint 12 v1 — shipped)

```text
Import → Vision analyze at edit resolution (≤1280 edge)
  → build_skin_mask_from_landmarks (Rust)
  → replay edit graph + apply_skin_smooth_cpu / apply_gpu_beauty_pass
  → preview / export
```

**Fix shipped:** Vision landmarks mapped from face-bbox space to full-image coords via `VNImagePointForFaceLandmarkPoint`.

---

## Regional effects — technical notes

### Skin smooth (done)
Frequency separation; cheeks/forehead; eyes/lips/nose excluded via `regions.rs`.

### Eye brighten (Nexus B)
Lift luminance in eye ellipses; optional subtle iris saturation. Mask from `leftEye` / `rightEye` landmark regions. WGSL: `eye_brighten.wgsl`.

### Lip color (Nexus B)
Mask = union of `outerLips` + `innerLips` (Vision) or MP lip indices. Apply HSL shift + saturation toward target hue; preserve lip line contrast. Preset swatches: Nude, Rose, Berry, Coral, Red.

### Lip size (Nexus B)
**Localized warp**, not global scale: push lip contour vertices outward along normals (plump) or inward (thin). Cap ±15% at slider 100% to avoid uncanny valley. Requires lip landmark loop (≥12 pts); quality improves with MediaPipe 468 in Nexus A.

### Blush (Nexus B)
Soft pink/orange ellipses on cheek landmarks; multiply blend at low opacity.

### Beauty looks (Nexus C)
Mirror [`mood_presets.rs`](../packages/image_forge/rust/src/filters/mood_presets.rs) pattern:

```rust
pub struct BeautyRecipe {
    pub skin_smooth: f32,
    pub eye_brighten: f32,
    pub lip_tint: LipTint,      // hue + strength
    pub lip_plump: f32,
    pub blush: f32,
    pub under_eye: f32,         // optional v2
}
```

Example presets:

| Look | Skin | Eyes | Lips | Plump | Blush |
|------|------|------|------|-------|-------|
| Natural | 0.35 | 0.10 | nude 0.2 | 0.0 | 0.0 |
| Soft | 0.55 | 0.20 | rose 0.3 | 0.15 | 0.15 |
| Glow | 0.45 | 0.35 | coral 0.25 | 0.10 | 0.20 |
| Glam | 0.50 | 0.40 | berry 0.5 | 0.25 | 0.10 |
| Clear | 0.70 | 0.15 | none | 0.0 | 0.0 |

Looks apply to **face regions only** — unlike mood swipe (global). Mood/filters tabs unchanged.

---

## Edit graph model (Nexus B/C)

Extend beauty slot from scalar strength to structured params:

```dart
// v1 (shipped): ImageFilter.skinSmooth(strength: 0.8)
// Nexus: ImageFilter.beautyLook(BeautyParams params)
//   or BeautyParams from preset + per-slider overrides
```

Session holds `faceAnalysis` + cached regional masks; graph holds committed `BeautyParams` for undo/export replay.

---

## Out of scope

- Full 3D mesh rendering / ARKit face replacement
- Body tracking / background replacement (separate AR sprint)
- Replacing mood swipe or Filters-tab presets
- Real-time teeth whitening v1 (defer to Nexus E polish)

---

## Acceptance

### Sprint 12 v1 (static) — done
- Portrait import: skin smooth on face; no face → "No face detected"; export at full res

### Nexus A — live camera
- Front camera → `GpuEditSurface`; stable mask 24–30 fps; `TemporalSmoother` warm-up ~5 frames

### Nexus B — regional controls (still + live)
- Sliders: eye brighten, lip color (+ swatches), lip size, blush; eyes/lips stay recognizable at 100%
- Re-analyze after import; masks align with face (bbox-correct landmarks)

### Nexus C — beauty looks
- ≥5 one-tap presets; chip strip in Beauty panel; commit on tap; fine-tune overrides persist
- Export and undo/redo preserve look + overrides

### Nexus D — platform parity
- MediaPipe 468 on iOS/macOS when models bundled; Android Kotlin plugin; GPU bind for regional WGSL passes

---

## Bundle size

Ship MediaPipe models as optional download or feature flag if AAR/framework size is prohibitive. Vision-only fallback keeps skin smooth + basic lip masks on Apple without MP.

---

## References

- Roadmap: [ROADMAP.md](../ROADMAP.md) — Sprint Nexus breakdown
- Sprint 12 code: `rust/src/face/`, `darwin/Classes/RustImageFacePlugin.swift`
- GPU shaders: `rust/src/gpu/shaders/skin_smooth.wgsl` (+ `lip_tint.wgsl`, `eye_brighten.wgsl` planned)

*Last updated: Nexus sprint planning*
