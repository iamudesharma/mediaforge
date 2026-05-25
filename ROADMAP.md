# rust_image roadmap

Performance and architecture plan for reaching native-editor responsiveness (GPU-resident editing, texture display, preview/export split).

**Current sprint:** Sprint 10 (Layers, draw polish, tone depth, straighten)  
**Status:** Sprint 9 **done** — IG crop overlay, filter strength, warmth/fade/vignette, paint eraser

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
| P2 | Vignette, LUT, GPU overlay blend | Deferred → Sprint 2b |
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

## Sprint 5 — Phase 5: API & product

- README GPU coverage table (preview vs export)
- `RustImageEditorConfig`: `liveEditMaxEdge`, `previewMaxEdge`, `showPerformanceInStatus`
- Per-tool backend hints

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

## Sprint 10b — Follow-on (planned)

| Track | Notes |
|-------|-------|
| Straighten gestures | Two-finger refine on trackpad |
| GPU vignette + LUT pack | Sprint 2b (`vignette.wgsl`, `.cube` presets) |
| Metal texture preview | Sprint 4b (`Texture` + shared wgpu handle) |

---

## Sprint 11 — Beauty / face (planned)

Regional tone masks from face landmarks (ML Kit / native); not a small FRB filter.

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
Edit graph (filters) replayed on edit base for preview
  ↓
LayerStack (emoji / sticker / text / paint) — Flutter overlay, non-destructive
  ↓
RgbaPreviewImage (ImageDescriptor.raw) OR JPEG fallback
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

## References

- Root README: [README.md](README.md)
- Plugin README: [rust_image/README.md](rust_image/README.md)
- GPU notes: Metal via wgpu when `gpu` feature enabled

---

*Last updated: Sprint 10 complete*
