# Video media runtime & texture preview (Sprint V1)

**Status:** V1.1 **done** — V1.2+ planned ([ROADMAP.md](../ROADMAP.md) Sprint V1).

**Goal:** Move from **preview-centric / frame-on-demand** to a **stream-centric** playback model with explicit **runtime ownership**, **decoder-clock** timing, **texture lifecycle**, and a **frame queue** — without building a custom full video engine in V1.

**Related:** [VIDEO_PACKAGE_SPLIT.md](VIDEO_PACKAGE_SPLIT.md) · [V0_ACCEPTANCE.md](V0_ACCEPTANCE.md) · image texture bridge [`rust_gpu_texture`](../packages/rust_gpu_texture/) · legacy [rust video/docs/architecture.md](../rust%20video/docs/architecture.md).

**Prerequisite:** V0 package split done (`video_processor_core`, `flutter_video_processor`, `video_thumbnail_cache`).

**Not in V1:** Full render graph, HDR display pipeline, multi-track audio mixer — documented as **future sprints** below.

---

## Maturity model

| Level | Model | V1 target |
|-------|--------|-----------|
| 0 (today) | `video_player` OR thumbnail → `Image.file` | Example studio only |
| 1 | **MediaRuntime** owns asset; **frame queue** + **texture lifecycle**; scrub via decode | **V1.1–V1.2** |
| 2 | **Decoder-clock** playback (Rust time master, not UI `Timer`) | **V1.3** |
| 3 | **GPU residency** — CVPixelBuffer / SurfaceTexture zero-copy where possible | **V1.4** |
| 4 | **Compositor** — Flutter `Stack` overlays + timeline metadata (Sprint 20 UI) | **V1.5** + Sprint 20 |
| 5 | **Render graph** — Rust/GPU node graph for filters, transitions, exports | Future (V2+) |
| 6 | **HDR / wide gamut** + **audio master clock** | Future (V3+) |

---

## Architecture (target)

```text
┌─────────────────────────────────────────────────────────────────┐
│  UI (example / future video editor)                              │
│  Stack: overlays (stickers, text) + VideoPreviewSurface widget   │
└───────────────────────────────┬─────────────────────────────────┘
                                │ listens to MediaRuntime
┌───────────────────────────────▼─────────────────────────────────┐
│  flutter_video_processor — MediaRuntime (Dart)                     │
│  • single owner per open asset                                     │
│  • PlaybackClock (decoder time)                                    │
│  • FrameQueue (producer/consumer)                                  │
│  • VideoTexturePool / lifecycle (rust_gpu_texture handles)         │
└───────────────┬─────────────────────────────┬───────────────────┘
                │ FRB (decode, seek)            │ MethodChannel
┌───────────────▼───────────────┐   ┌──────────▼──────────────────┐
│  video_processor_core          │   │  rust_gpu_texture            │
│  PreviewDecoder session        │   │  TextureRegistry, GpuTextureView │
│  (FFmpeg; optional HW path)    │   │  (display only)              │
└───────────────────────────────┘   └─────────────────────────────┘
```

**Hard boundaries (unchanged from V0):**

- `video_processor_core`: decode, timestamps, bytes/buffer handles — **no** Flutter plugin.
- `rust_gpu_texture`: GPU/Flutter texture — **no** FFmpeg.
- `flutter_video_processor`: **MediaRuntime** + optional `rust_gpu_texture` dependency.
- **Do not** depend on `rust_image_core` / `GpuEditSurface` for video.

---

## 1. MediaRuntime layer

**Purpose:** One object owns the lifecycle of an open video asset so UI widgets do not call FRB or texture APIs directly.

| Responsibility | Owner |
|----------------|--------|
| Open / close input (path, URL, ingest copy) | `MediaRuntime` |
| Probe `MediaInfo` (once) | `MediaRuntime` |
| Trim range (`startMs`, `endMs`) as **metadata** | `MediaRuntime` |
| Play / pause / seek | `MediaRuntime` → `PlaybackClock` |
| Expose `Listenable` / `Stream<MediaFrame>` for UI | `MediaRuntime` |
| Compress / export jobs | Existing `VideoProcessor` / queue (**separate** from preview runtime) |

**Sketch API (Dart):**

```dart
final runtime = MediaRuntime(
  previewMaxEdge: 720,
  texturePool: VideoTexturePool(),
);

await runtime.open(VideoAsset.local(path));
runtime.setTrimRange(startMs: 0, endMs: 30_000);
await runtime.seekTo(Duration(milliseconds: 12_000)); // scrub
await runtime.play(); // decoder-clock in V1.3+

// Widget: runtime.previewSurface(fit: BoxFit.contain)
```

**Rules:**

- At most **one** `PreviewDecoder` session per `MediaRuntime` instance.
- `dispose()` cancels decode, drains queue, releases all texture handles.
- Filmstrip thumbnails stay on **`video_thumbnail_cache`** — not through MediaRuntime.

---

## 2. Decoder-clock playback

**Problem:** UI `Timer.periodic` drifts from real media time; A/V and trim export disagree with preview.

**V1.3 approach:** **Decoder clock** = monotonic media timeline driven by decoded frame PTS, not wall clock alone.

| Component | Role |
|-----------|------|
| `PlaybackClock` | Holds `mediaTimeMs`, `rate`, `state` (idle / playing / paused) |
| Decode loop (Rust or Dart isolate) | Produces `(ptsMs, frame)` into queue |
| Clock advance | On each displayed frame: `mediaTimeMs = ptsMs`; UI notified |
| Catch-up | If queue empty: hold last frame or drop to next keyframe; never spin UI faster than decode |
| Scrub | `seekTo(ms)` flushes queue, resets clock, enqueues single frame |

**Not V1:** Sample-accurate audio render — see [§7 Audio sync](#7-audio-sync-roadmap). V1.3 may play **video-only** with silent clock or optional `video_player` audio bridge behind a flag.

---

## 3. Texture lifecycle manager

**Purpose:** Avoid texture leaks, double-register, and resize races when scrubbing or rotating preview size.

`VideoTexturePool` (Dart, uses `rust_gpu_texture`):

| Operation | Behavior |
|-----------|----------|
| `acquire(width, height)` | Stable `handle` per pool slot; `createTexture` once per size bucket |
| `present(handle, rgba \| nativeBuffer)` | `updateTexture` or `notifyFrameAvailable` (V1.4) |
| `resize(w, h)` | Dispose old registration if dimensions change; acquire new |
| `releaseAll()` | `disposeTexture` for every handle on `MediaRuntime.dispose()` |

**Preview surface widget:** `VideoPreviewSurface` wraps `GpuTextureView` + aspect ratio from `MediaInfo`; rebuilds only on `textureId` / dimension change, not every queue tick (use `Listenable` / `ValueListenable<int>` for generation counter).

---

## 4. Frame queue architecture

**Purpose:** Decouple **decode producer** from **UI consumer** (stream-centric, not “await one frame per `setState`”).

```text
PreviewDecoder (producer)          FrameQueue (bounded)          Presenter (consumer)
     │                                    │                            │
     │  decode thread / FRB batch         │  max N=3 frames            │  main isolate
     ├─ seek ──► flush ──► decode ───────►│  drop oldest if full       ├─► texture.present
     │                                    │  priority: scrub > play     │  clock.advance(pts)
```

| Policy | Value |
|--------|--------|
| Max depth | 3 (tune on device) |
| Scrub | Flush queue; single in-flight decode; coalesce rapid seeks (280 ms debounce, match studio) |
| Play | Fill queue ahead; drop stale frames if `pts < clock.mediaTimeMs` |
| Frame payload V1.1 | `PreviewFrame { ptsMs, width, height, rgba }` |
| Frame payload V1.4 | `HwPreviewFrame { ptsMs, bufferHandle }` on Apple |

**Rust:** `PreviewDecoder` session in `video_processor_core` (new `pipeline/preview.rs`), reusing thumbnail seek helpers but **separate** from filmstrip CPU-only policy (preview may enable HW decode on Apple when stable).

---

## 5. Future render graph (notes only)

**When:** After V1.5 + Sprint 20 timeline UI — **V2 sprint**, not V1.

**Intent:** Directed acyclic graph of nodes for reproducible export and effects:

```text
[Source] → [Decode] → [Color] → [Overlay composite] → [Encode]
              ↑              ↑
         [Sticker GPU]   [LUT / grade]
```

| Node type | Owner (likely) |
|-----------|----------------|
| Source / trim | `video_processor_core` |
| Display present | `rust_gpu_texture` |
| 2D overlays (stickers) | Flutter `Stack` first; optional GPU composite node later |
| Transitions | Rust graph (V2) |

**V1.5 stop line:** Flutter `Stack` over `VideoPreviewSurface` (same pattern as image `LivePreview`) — **no** Rust render graph in V1.

---

## 6. HDR / color-space roadmap

**When:** V3+ — after SDR texture path is stable.

| Phase | Scope |
|-------|--------|
| **HDR-0** | Document source tags: probe `color_primaries`, `color_trc`, `colorspace` in `MediaInfo` (FFmpeg metadata) |
| **HDR-1** | Decode to linear/float intermediate for export only |
| **HDR-2** | Display: EOTF-aware preview on Apple (EDR) / fallback SDR tonemap on Android |
| **HDR-3** | Render graph color-managed pipeline (ACES or fixed SDR bake) |

**V1 rule:** Preview in **SDR 8-bit RGBA** (or BGRA texture); preserve metadata for future. Do not block V1 on HDR.

---

## 7. Audio sync roadmap

**When:** V2–V3 — parallel to decoder-clock video.

| Phase | Scope |
|-------|--------|
| **A-0** | Video-only preview (V1.3) |
| **A-1** | Optional `video_player` audio + Rust video clock sync bridge (short-term) |
| **A-2** | FFmpeg audio demux + platform audio output (`AVAudioEngine` / `AudioTrack`) locked to `PlaybackClock.mediaTimeMs` |
| **A-3** | Multi-track mixer (Sprint 20) with single master clock |

**V1 rule:** Do not delay V1.1–V1.2 on audio.

---

## Delivery phases (implement in order)

| ID | Name | Deliverable | Package touchpoints |
|----|------|-------------|---------------------|
| **V1.1** | MediaRuntime + texture lifecycle | **Done** — `MediaRuntime`, `VideoTexturePool`, `VideoPreviewSurface`; FRB `decodePreviewFrameRgba`; studio scrub on texture | `flutter_video_processor`, `video_processor_core`, `rust_gpu_texture` |
| **V1.2** | Frame queue + scrub stream | Bounded queue, flush/coalesce on seek; remove `Image.file` scrub fallback in studio | Same |
| **V1.3** | Decoder-clock playback | `PlaybackClock`, decode loop, play/pause; video-only 24–30 fps target at `previewMaxEdge` | + `PreviewDecoder` session API |
| **V1.4** | GPU residency (Apple first) | `rust_gpu_texture` CVPixelBuffer attach; VT HW decode path for preview | `rust_gpu_texture`, `video_processor_core` |
| **V1.5** | Overlay compositor shell | `VideoEditorCanvas` = texture + `Stack` overlays; trim/playhead wired to runtime | Example + thin SDK widgets |
| **V1.6** | Android zero-copy | MediaCodec → SurfaceTexture path (if stable) | Platform-specific |
| **V1.7** | Metrics & perf matrix | Scenarios I/J/K in ROADMAP; status timing in example | Docs + example |

**Explicitly out of V1:** Custom full video engine, render graph execution, HDR display, audio mixer.

---

## What we keep from today

| Piece | Keep? |
|-------|--------|
| `video_thumbnail_cache` + filmstrip | **Yes** — disk LRU for many frames |
| `VideoProcessor` compress / queue | **Yes** — separate from MediaRuntime |
| `video_player` in status-only preview | **Optional** — simple loop screens; editor uses MediaRuntime |
| Thumbnail CPU pipeline for batch strip | **Yes** — do not conflate with preview decode |

---

## Perf matrix (video studio)

Run in `flutter_video_processor` example after each sub-phase:

| ID | Scenario | Target |
|----|----------|--------|
| **I** | 720p, scrub playhead 5 s | Debounced frame visible &lt; 300 ms; no JPEG disk in hot path (V1.2+) |
| **J** | 720p, play 10 s trim range | ≥ 24 fps sustained at `previewMaxEdge=720` (V1.3+) |
| **K** | Open / dispose 10 clips in a row | No texture/handle leaks (DevTools + native logs) (V1.1+) |

---

## File map (planned)

| Layer | Path (planned) |
|-------|----------------|
| Design | `docs/VIDEO_MEDIA_RUNTIME.md` (this file) |
| Runtime | `packages/flutter_video_processor/lib/src/runtime/media_runtime.dart` |
| Queue | `packages/flutter_video_processor/lib/src/runtime/frame_queue.dart` |
| Clock | `packages/flutter_video_processor/lib/src/runtime/playback_clock.dart` |
| Textures | `packages/flutter_video_processor/lib/src/runtime/video_texture_pool.dart` |
| Widget | `packages/flutter_video_processor/lib/src/widgets/video_preview_surface.dart` |
| Rust preview | `packages/video_processor_core/rust/src/pipeline/preview.rs` |
| FRB | `packages/video_processor_core/rust/src/api/preview.rs` |

---

## Sprint 20 dependency

[Sprint 20](../ROADMAP.md#sprint-20--video-clips--audio-timeline-editors) (multi-track timeline UI) should build on **MediaRuntime + decoder clock + V1.5 overlay shell**, not on raw `video_player` + thumbnails.

---

*Last updated: V1.1 implemented*
