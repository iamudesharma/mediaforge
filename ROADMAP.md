# rust_image roadmap

Performance and architecture plan for reaching native-editor responsiveness (GPU-resident editing, texture display, preview/export split).

**Current sprint:** All tracked sprints complete (Sprint 13)  
**Status:** Sprint 13 + Nexus + Sprint 10b + Sprint 2 P2 + Sprint 5 shipped — Squadron worker pool, parallel pipelines, offload camera YUV conversion, MediaPipe download, live GPU texture, teeth whiten

---

## Sprint 1 — Phase 0 + Phase 1 (done)

**Goal:** Measure real bottlenecks, then remove avoidable work without a full GPU rewrite.

**Target:** ~1 week

### Phase 0 — Baseline & metrics

| Task | Status | Notes |
|------|--------|-------|
| Split timings: filter / preview JPEG / isolate round-trip | Done | Status line: `filter Nms · preview Nms` via `OperationProfile` |
| Record execution path (`gpu` vs `cpu_photon`) | Done | `gpu_adjust` / `cpu_photon` in status; `RUST_IMAGE_PERF=1` in Rust |
| Document test matrix (768p, 4K, blur, preset, adjust) | Done | See [Performance test matrix](#performance-test-matrix) |
| Confirm GPU device is singleton (not per-op) | Done | `GpuEngine` via `OnceLock` |

### Phase 1 — Quick wins

| Task | Status | Notes |
|------|--------|-------|
| **1a** Preview-resolution editing (1280px edge live, full res on commit) | Done | `liveEditMaxEdge` / `previewMaxEdge` in config; adjust uses edit-scale base |
| **1b** Reduce Flutter JPEG re-decode (`ui.Image` cache in preview) | Done | `CachedPreviewImage` widget |
| **1c** Fewer buffer copies in worker isolate | Done | `TransferableTypedData.fromList([buffer.pixels])` on send/receive |
| **1d** GPU path audit & status label | Done | `filterExecutionPath` API + status suffix |
| **1e** Preview vs commit split for adjust/filters | Done | Live adjust: `fromBase` → downscaled `rgbaBase`; presets on `rgbaBuffer` |

**Exit criteria**

- Status line shows e.g. `Blur · 120 ms · cpu_photon · preview 18 ms`

### Benchmark harness

| Component | Location |
|-----------|----------|
| Rust CLI (`rust_image_benchmark`) | `rust_image/rust/src/benchmark/`, `src/bin/rust_image_benchmark.rs` |
| Dart / FRB runner | `rust_image/benchmark/` |

Run before/after perf work: `cargo run --release --features gpu --bin rust_image_benchmark -- --synthetic -n 10`. Export CSV with `--csv results.csv`. Details: [benchmark/README.md](rust_image/benchmark/README.md).
- Adjust sliders run on ≤1280px edge until commit
- Loading image prepares RGBA + edit-scale buffer
- No PNG round-trip in RGBA filter path (already done in Rust)

---

## Sprint 1.5 — Perf Phase 2 + 3 (done)

**Goal:** Reduce contention and avoidable copies identified after benchmark regression analysis.

### Phase 2 — Contention diagnostics

| Knob | Env var | Purpose |
|------|---------|---------|
| Rayon threads | `RAYON_NUM_THREADS` or `RUST_IMAGE_RAYON_THREADS` | Cap CPU parallelism (set before first Rayon use; `init_app` applies) |
| Buffer pool off | `RUST_IMAGE_NO_POOL=1` or `RUST_IMAGE_BENCH_NO_POOL=1` | A/B pool vs direct allocation |
| Single-op bench | `--only <name>` | Isolate ops (see benchmark README) |

### Phase 3 — Targeted fixes (implemented)

| Fix | Notes |
|-----|--------|
| CPU `resize_rgba` | `fast_image_resize` on raw RGBA — no `DynamicImage` round-trip |
| GPU resize cache | Reuses src/dst/readback GPU buffers when dimensions match |
| Crop buffer | Pre-sized pool buffer + row `copy_from_slice` (no `extend`) |
| Pool bypass | `RUST_IMAGE_NO_POOL` skips mutex when diagnosing contention |
| Docs | README GPU table includes blur; benchmark reports `pool=on/off` |

**Verify:**

```bash
cd rust_image/rust
cargo run --release --features gpu --bin rust_image_benchmark -- \
  --synthetic -n 10 --only filter_rgba_brightness
RAYON_NUM_THREADS=4 cargo run --release --features gpu --bin rust_image_benchmark -- \
  --synthetic -n 10 --only resize_rgba_50pct
```

---

## Sprint 2 — GPU filter engine v1 (done)

**Goal:** Move expensive filters off CPU photon for the preview pipeline.

| Priority | Work | Status |
|----------|------|--------|
| P0 | Separable Gaussian blur (WGSL compute) | Done (`blur.wgsl`, ping-pong) |
| P1 | Sharpen (`sharpen.wgsl`) | Done |
| P1 | Unified color matrix + hue (`color_adjust.wgsl`) | Done |
| P2 | Vignette, LUT, GPU overlay blend | Done (11b.1 LUT/vignette; overlay `overlay_composite.wgsl` + `apply_gpu_overlay_blend`) |
| Infra | Ping-pong GPU buffers + single readback in `process_gpu_pipeline` | Done |

**GPU filters (preview path):** blur, sharpen, brightness, contrast, saturation, hue rotate (+ resize).

**Exit criteria:** Blur/sharpen sliders on 1080p preview feel interactive on Mac Metal — verify in Studio.

```bash
cd rust_image/rust
cargo run --release --features gpu --bin rust_image_benchmark -- \
  --synthetic -n 5 --only filter_rgba_sharpen
cargo run --release --features gpu --bin rust_image_benchmark -- \
  --synthetic -n 5 --only filter_rgba_blur
```

---

## Sprint 3 — Edit graph & export (done)

**Goal:** Non-destructive filter op list; full-res replay only on export.

| Item | Status |
|------|--------|
| `EditGraph` + `EditGraphState` in `lib/src/editor/models/edit_graph.dart` | Done |
| Committed filters stored in `EditorSession.editGraph` | Done |
| Preview replays graph on `rgbaEditBase` via `RustWorker.replayEditPipeline` | Done |
| Export replays `editGraph.ops` on full `rgbaBase` via `applyEditPipelineFull` | Done |
| Undo/redo as op stack (`_undoGraph` / `_redoGraph`) | Done |
| Draw/overlay bake graph into full base before pixel edits | Done |

---

## Sprint 4 — Flutter RGBA preview (done)

**Goal:** Remove JPEG encode/decode from the live filter hot path.

| Item | Status |
|------|--------|
| `RgbaPreviewImage` — `ImageDescriptor.raw` + `RawImage` | Done |
| `RustImageEditorConfig.useRgbaPreview` (default `true`) | Done |
| Worker skips preview JPEG when `encodePreviewJpeg: false` | Done |
| Future: `Texture` / external Metal texture (Sprint 4b) | Deferred |

Set `useRgbaPreview: false` to fall back to JPEG + `CachedPreviewImage`.

---

## Sprint 5 — Phase 5: API & product (done)

| Item | Status | Notes |
|------|--------|-------|
| README GPU coverage table (preview vs export) | Done | [`rust_image/README.md`](rust_image/README.md) |
| `RustImageEditorConfig`: `liveEditMaxEdge`, `previewMaxEdge`, `showPerformanceInStatus` | Done | + `enableMediaPipeDownloadPrompt`, live camera knobs |
| Per-tool backend hints | Done | Status line: `gpu_mood`, `gpu_teeth`, `cpu_plump`, live fps |

---

## Sprint 6 — Sticker / Emoji / Text layers (done)

**Goal:** Instagram-style non-destructive layers (emoji, stickers, text) on top of the image; bake on export.

| Item | Status | Notes |
|------|--------|-------|
| `OverlayLayer` + `LayerStack` models | Done | `overlay_layer.dart`, `layer_stack.dart`, `layer_transform.dart` |
| `TransformableLayer` + `LayerEditorOverlay` | Done | Pinch/drag/rotate; expanded hit targets; dynamic scale limits |
| `stickers_panel.dart` (Emoji / Stickers / Text tabs) | Done | Emoji grid, built-in stickers, import image, text + background styles |
| Built-in sticker assets + `assets/stickers/` | Done | `StickerCatalog` + `pubspec.yaml` `assets/stickers/` |
| `rust/src/layers.rs` + `bake_overlay_layers` FRB | Done | `composite_raster_layer` + `bake_overlay_layers` / `bakeLayersOnRgba` |
| `EditorSession.layerStack` + export bake | Done | Layer undo/redo; `LayerBake.bakeOnto` on export |
| `EditorTool.stickers` in mobile nav | Done | `tool_panels.dart`, `rust_image_editor_config.dart` default tools |

**Acceptance:** Multi emoji/sticker/text; pinch-drag-rotate; text background pill; export bakes full-res — **met**.

---

## Sprint 7 — Multi-stroke Paint editor (done)

**Goal:** Free-hand strokes as layers; brush types; per-stroke undo; bake on export.

| Item | Status | Notes |
|------|--------|-------|
| `PaintStrokeLayer` on `LayerStack` | Done | `addPaintStroke`, `PaintStrokePainter` |
| `paint_canvas.dart` + `paint_panel.dart` | Done | Pen / marker / highlighter; undo last stroke, clear all |
| `composite_paint_strokes` in Rust | Done | `layers.rs` + export via `LayerBake` |
| `EditorTool.paint` in mobile nav | Done | Wired in `editor_screen.dart` / `live_preview.dart` |

**Acceptance:** Multi-stroke draw; export at full resolution — **met**. Eraser brush UI exists; true stroke erase (not just undo/clear) — **deferred** (follow-up).

---

## Sprint 8 — Blank canvas + shaped image stickers (done)

**Goal:** Instagram-style blank start (aspect + solid/gradient/custom color) and image stickers with shape masks + multi-import.

| Item | Status | Notes |
|------|--------|-------|
| `BlankCanvasBuilder` + IG aspect presets | Done | Square 1080, Story 9:16, Portrait 4:5, Landscape 16:9 |
| `BlankCanvasSheet` + color/gradient presets | Done | 24 solids, 12 gradients, custom HSV tab |
| `allowBlankCanvas` + Import panel CTA | Done | Import tab + mobile import menu |
| `StickerShapeMask` on `StickerLayer` | Done | none, rounded, circle, oval, heart, star, hexagon, squircle |
| `ShapePaths` + rasterizer clip | Done | Preview `ClipPath` + export bake match |
| `pickMultipleImageBytes` | Done | Gallery multi (mobile) / openFiles (desktop) |
| Shape picker sheet + selected sticker chips | Done | Import flow + post-placement edit in Stickers panel |

**Acceptance:** Create blank canvas without photo; import 3+ images as separate shaped stickers; change shape on selected sticker — **met**.

---

## Sprint 9 — Interactive crop + filter intensity (done)

**Goal:** Instagram-style crop UX and filter strength; warmth/fade/vignette adjust; paint eraser + tests.

| Item | Status | Notes |
|------|--------|-------|
| `CropController` + `CropOverlay` | Done | Drag box + corners; aspects Free, 1:1, 4:5, 9:16, 16:9, Original |
| Transform panel wired to shared crop state | Done | [`crop_controller.dart`](rust_image/lib/src/editor/crop_controller.dart), preview when Crop tool active |
| Filter preset strength 0–100% | Done | `ImageFilter.preset { strength }` + lerp in Rust [`filters.rs`](rust_image/rust/src/filters.rs) |
| Warmth / Fade / Vignette adjust | Done | New `ImageFilter` variants + Adjust panel sliders |
| Paint eraser (stroke erase) | Done | `PaintStrokeInput.erase` + preview `BlendMode.clear` + export bake |
| Widget / unit tests | Done | `crop_controller_test`, `filters_panel_preset_test`, `editor_crop_filters_widget_test` |

**Acceptance:** Interactive crop on preview; filter intensity slider; adjust warmth/fade/vignette; eraser removes paint strokes — **met**.

---

## Sprint 10 — Layers, draw polish, tone depth, straighten (done)

**Goal:** Layer panel UX; text re-edit sheet; distinct brush preview/export; arrow sticker; highlights/shadows/structure; straighten slider with crop re-fit.

| Item | Status | Notes |
|------|--------|-------|
| `LayerStack` visibility + reorder APIs | Done | `visible`, `sendToBack`, `moveUp`/`moveDown`, `insertAt` |
| Layers panel + `EditorTool.layers` | Done | [`layers_panel.dart`](rust_image/lib/src/editor/panels/layers_panel.dart) |
| Text layer double-tap edit sheet | Done | [`text_layer_edit_sheet.dart`](rust_image/lib/src/editor/panels/text_layer_edit_sheet.dart) |
| Marker / highlighter / neon brushes | Done | Preview + `PaintStrokeInput.brushKind` export |
| Arrow on canvas | Done | Shapes panel → builtin `arrow` sticker |
| Highlights / Shadows / Structure | Done | CPU [`filters.rs`](rust_image/rust/src/filters.rs) + Adjust panel |
| Straighten slider + apply | Done | `rotate_rgba_arbitrary` + [`CropController`](rust_image/lib/src/editor/crop_controller.dart) |
| Tests | Done | `layer_stack_test`, `filter_descriptor_test`, `paint_stroke_painter_test` |

**Acceptance:** Layer list reorder/hide/delete; text double-tap opens edit; brush personalities in preview and export; tone sliders; straighten bakes rotation — **met**.

---

## Sprint 10b — Follow-on (done)

| Track | Status | Notes |
|-------|--------|-------|
| Straighten gestures | Done | Two-finger rotate on [`crop_overlay.dart`](rust_image/lib/src/editor/widgets/crop_overlay.dart) |

---

## Sprint 11 — Swipe mood filters (done)

**Goal:** Instagram/Snapchat-style global mood filters (Rose, Clarendon, …) via horizontal swipe on the preview — not in the Filters tab. Existing 14 Filters-tab presets unchanged.

| Item | Status | Notes |
|------|--------|-------|
| `MoodFilterPreset` + parametric recipes | Done | [`mood_presets.rs`](rust_image/rust/src/filters/mood_presets.rs) |
| `ImageFilter::Mood` + RGBA path | Done | Separate from `FilterPreset` / photon presets |
| Swipe on preview + name chip | Done | [`swipe_mood_filter.dart`](rust_image/lib/src/editor/widgets/swipe_mood_filter.dart) |
| Dedicated mood slot in edit graph | Done | `EditGraph.replaceMoodFilter` |
| Commit on finger release | Done | `EditorSession.setMoodFilter` |

---

## Sprint 11b.1 — GPU LUT + vignette (done)

**Goal:** Mood swipe + Adjust vignette on wgpu (WGSL compute); ~1–2 GPU passes + one readback. Filters-tab photon presets unchanged.

| Item | Status | Notes |
|------|--------|-------|
| `lut.wgsl` + 33³ mood LUT bake | Done | Color grade from `MoodRecipe`; vignette + structure as GPU sidecars |
| `vignette.wgsl` | Done | Matches `apply_vignette_rgba` |
| Wire `ImageFilter::Mood` + `Vignette` in GPU pipeline | Done | `is_gpu_capable`, `process_gpu_pipeline`, `perf.rs` |
| Benchmark + GPU vs CPU tolerance tests | Done | `--only filter_rgba_mood_*` |

**Backend note:** Metal / Vulkan / DX12 via wgpu `Backends::all()` — no separate `.metal` / GLSL tree.

```bash
cd rust_image/rust
cargo run --release --features gpu --bin rust_image_benchmark -- \
  --synthetic -n 10 --only filter_rgba_mood_clarendon
```

---

## Sprint 11b.2 — Flutter Texture preview (done)

**Goal:** GPU-resident edit surface; Flutter `Texture` widget (no Dart `ui.Image` decode). macOS Metal first.

| Item | Status | Notes |
|------|--------|-------|
| `GpuEditSurface` + FRB texture handle API | Done | `api/texture.rs`, `gpu/surface.rs` |
| macOS CVPixelBuffer → `TextureRegistry` | Done | `macos/Classes/RustImageTexturePlugin.swift` |
| `GpuTexturePreview` + `useGpuTexturePreview` | Done | Fallback to `RgbaPreviewImage` |

---

## Sprint 12 — MediaPipe face + beauty (Phase 3, static photo v1) — done

**Goal:** Regional face beauty on still images (macOS + iOS). Live camera deferred to Sprint 12b.

| Item | Status | Notes |
|------|--------|-------|
| Native face analysis (`rust_image/face`) | Done | Apple Vision landmarks + person mask; MediaPipe `.task` optional via [`scripts/download_mediapipe_models.sh`](rust_image/scripts/download_mediapipe_models.sh) |
| FRB `api/face.rs` + `regions.rs` mask | Done | Feathered R8 skin mask at edit resolution |
| `EditorTool.beauty` + skin smooth slider | Done | Mask in session; strength in edit graph slot |
| GPU preview beauty pass | Done | `apply_gpu_beauty_pipeline` — skin/eye/lip/blush WGSL on texture preview (Nexus D) |
| Design doc | Done | [`docs/PHASE3_MEDIAPIPE.md`](docs/PHASE3_MEDIAPIPE.md) |

**Verify:** Import portrait → Beauty tab → slider (face only) → export. No face → “No face detected”. Mood/filters regression unchanged.

---

## Sprint Nexus — Face AR + beauty looks (done)

**Goal:** Instagram / Snapchat-style face beautification: one-tap looks, regional makeup sliders (eyes, lips, blush), live front-camera.

**Design:** [`docs/PHASE3_MEDIAPIPE.md`](docs/PHASE3_MEDIAPIPE.md)

### Nexus A — Live camera + mesh upgrade — done

| Item | Status | Notes |
|------|--------|-------|
| Front-camera → live RGBA preview | Done | `LiveCameraService` + YUV→RGBA; beauty every frame |
| `TemporalSmoother` per frame | Done | FRB `api/temporal.rs`; α = 0.25; analyze every 3 frames |
| MediaPipe Face Landmarker (468 pts) | Done | Optional download via [`mediapipe_model_service.dart`](rust_image/lib/src/editor/services/mediapipe_model_service.dart); Vision / ML Kit fallback |
| Live beauty at ≥24 fps | Done | macOS/iOS GPU texture path; CPU fallback on Android |
| Debug landmark overlay | Done | `showDebugFaceLandmarks` + `FaceLandmarkOverlay` |
| Skip GPU readback (texture-only) | Done | Live GPU → `GpuTexturePreview` (no `previewRgba` hot loop); RGBA analyze (no JPEG) |

**Acceptance:** Front camera preview with stable skin mask after ~5 frames; no full-frame JPEG in loop.

### Nexus B — Regional makeup (still photo first, then live) — done

| Item | Status | Notes |
|------|--------|-------|
| `build_lip_mask` / `build_eye_mask` / blush regions | Done | [`regions.rs`](rust_image/rust/src/face/regions.rs); Vision lip indices; eraser exclude mask |
| Eye brighten | Done | CPU + GPU [`eye_brighten.wgsl`](rust_image/rust/src/gpu/shaders/eye_brighten.wgsl) |
| Lip color + swatches | Done | HSL tint; Nude / Rose / Berry / Coral / Red |
| Lip size (plump / thin) | Done | [`warp.rs`](rust_image/rust/src/face/warp.rs) — CPU warp; cap ±15% at 100% |
| Cheek blush | Done | Cheek ellipses; CPU + [`blush.wgsl`](rust_image/rust/src/gpu/shaders/blush.wgsl) |
| `BeautyParams` in edit graph | Done | Structured slot replaces scalar `skinSmooth` |
| Beauty panel fine-tune sliders | Done | Collapsible section under looks strip; eraser |

**Acceptance:** Portrait at edit-res — each slider affects only its region; 100% lip plump still recognizable; export at full res.

### Nexus C — Beauty looks (one-tap presets) — done

| Item | Status | Notes |
|------|--------|-------|
| `BeautyLookPreset` + `BeautyRecipe` | Done | [`face/looks.rs`](rust_image/rust/src/face/looks.rs) — mirror [`mood_presets.rs`](rust_image/rust/src/filters/mood_presets.rs) |
| Horizontal looks strip in Beauty panel | Done | Natural, Soft, Glow, Glam, Clear |
| Tap to apply / commit | Done | Sets all regional sliders; user can override after |
| Undo / redo / export | Done | Committed look + overrides in graph |
| Optional: swipe between looks on preview | Done | Same UX pattern as mood swipe on Beauty tool |

Example recipes (face-only, not global grade):

| Look | Skin | Eyes | Lips | Plump | Blush |
|------|------|------|------|-------|-------|
| Natural | 0.35 | 0.10 | nude 0.2 | 0.0 | 0.0 |
| Soft | 0.55 | 0.20 | rose 0.3 | 0.15 | 0.15 |
| Glow | 0.45 | 0.35 | coral 0.25 | 0.10 | 0.20 |
| Glam | 0.50 | 0.40 | berry 0.5 | 0.25 | 0.10 |
| Clear | 0.70 | 0.15 | none | 0.0 | 0.0 |

**Acceptance:** Pick “Soft” → visible skin + lip change on face; tweak lip color → export matches preview.

### Nexus D — Platform parity + GPU bind — done

| Item | Status | Notes |
|------|--------|-------|
| Bind `skin_smooth.wgsl` on GPU surface | Done | [`beauty_pass.rs`](rust_image/rust/src/gpu/beauty_pass.rs) on texture preview |
| `lip_tint.wgsl`, `eye_brighten.wgsl`, `blush.wgsl` | Done | Chained on `GpuEditSurface`; lip plump CPU warp |
| Android ML Kit face plugin | Done | [`RustImageFacePlugin.kt`](rust_image/android/src/main/kotlin/com/flutter_rust_bridge/rust_image/RustImageFacePlugin.kt) — same FRB shape |
| Benchmark beauty passes | Done | `--only beauty_skin_smooth_gpu` / `beauty_skin_smooth_cpu` |
| Optional model download UX | Done | `enableMediaPipeDownloadPrompt` + Beauty panel banner |

**Acceptance:** iOS + Android portrait beauty looks; status line shows `gpu_lip` / `gpu_eye` when GPU path used.

### Nexus E — Polish — done

| Item | Status | Notes |
|-------|--------|-------|
| Under-eye softening | Done | `under_eye` in `BeautyParams`; `build_under_eye_mask` |
| Teeth whiten | Done | teeth_whiten CPU + [`teeth_whiten.wgsl`](rust_image/rust/src/gpu/shaders/teeth_whiten.wgsl) |
| Compare-hold for beauty | Done | Compare shows pre-beauty RGBA on Beauty tool |
| Preset thumbnails | Done | Gradient look chips in Beauty panel |

---

## Sprint 13 — Squadron Worker Pool Integration (done)

**Goal:** Replace hand-rolled isolate with Squadron-managed multithreaded worker pool and dedicated camera worker for peak performance and UI smoothness.

| Phase | Tasks / Deliverables | Status | Notes |
|-------|----------------------|--------|-------|
| Phase 1 | Foundation: `@SquadronService` + single worker proxy | Done | Added squadron/builder to pubspec; generated proxy/workers; preserved static RustWorker API |
| Phase 2 | Parallelization: Worker pool + parallel loading & export | Done | Created auto-scaling pool config (2-4 workers); coalesce tracker for preview operations; parallel loading and export pipelines |
| Phase 3 | Live Camera: Offload YUV conversion & dedicated isolate | Done | Maintained separate dedicated camera worker to isolate camera stream processing from editor preview pipeline |

---

## Architecture target (end state)

```text
Decode ONCE
  ↓
Full-res RGBA (export source)
  ↓
Edit-res RGBA / GPU texture (≤1280–2048 edge)
  ↓
Shader / filter passes (GPU, persistent)
  ↓
Flutter Texture (no per-frame JPEG)
  ↓
Encode once on export
```

## Current architecture (today)

```text
Decode once → rgbaBase (full) + rgbaEditBase (≤1280px)
  ↓
Edit graph replay on GPU surface or CPU RGBA preview
  ↓
Live camera → uploadGpuPreviewSurface → beauty WGSL → Flutter Texture (macOS/iOS)
  ↓
LayerStack (emoji / sticker / text / paint) — Flutter overlay; GPU overlay blend optional
  ↓
RgbaPreviewImage OR GpuTexturePreview OR JPEG fallback
  ↓
Export: replay graph + bake layers onto full rgbaBase → encode once
```

## Performance test matrix

Run in **rust_image Studio** after changes; record status-line timings.

| Scenario | Resolution | Op | Backend | Target (Phase 1) |
|----------|------------|-----|---------|------------------|
| A | 768×1152 JPEG | Blur r=4 commit | auto | < 500 ms total |
| B | 768×1152 | Adjust brightness live | auto | < 200 ms debounced |
| C | 4K JPEG | Blur r=4 commit | auto | < 2 s (preview-scale live) |
| D | 768×1152 | Preset “Dramatic” | auto | < 400 ms |
| E | 768×1152 | Resize 50% | auto | GPU path in status |
| F | 768×1024 portrait | Beauty look “Soft” commit | auto | < 600 ms still |
| G | 768×1024 | Lip color live drag | auto | < 200 ms debounced |
| H | 720p front camera | Skin smooth live | gpu | ≥ 24 fps sustained |

## References

- Root README: [README.md](README.md)
- Plugin README: [rust_image/README.md](rust_image/README.md)
- Face / beauty design: [docs/PHASE3_MEDIAPIPE.md](docs/PHASE3_MEDIAPIPE.md)
- GPU notes: Metal via wgpu when `gpu` feature enabled

---

*Last updated: All tracked sprints complete (Sprint 13, Nexus, 10b, 2 P2, 5)*
