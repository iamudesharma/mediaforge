# Video package split (pre-publish architecture)

**Status:** V0.1–V0.6 in progress — engine, SDK, and optional thumbnail cache under [`packages/`](../packages/).

**Goal:** Three independently versioned packages with hard dependency boundaries. Host apps choose only what they need (engine/FRB only, ergonomic SDK, or disk-cached filmstrip helpers).

**Related:** Image split [PUB_PACKAGE_SPLIT.md](PUB_PACKAGE_SPLIT.md) · [V0_ACCEPTANCE.md](V0_ACCEPTANCE.md) · preview runtime [VIDEO_MEDIA_RUNTIME.md](VIDEO_MEDIA_RUNTIME.md) (Sprint V1) · legacy tooling in [`rust video/`](../rust%20video/).

---

## Why split

| Problem (monolith `flutter_video_processor`) | After split |
|---------------------------------------------|-------------|
| FFmpeg hook + FRB + disk cache ship one version | Patch cache without touching compress API |
| Upload backends pull `path_provider` / `crypto` for compress-only | Minimal transitive deps on `video_processor_core` |
| Breaking FRB types force SDK major bump | `video_processor_core` majors independently |
| Example UI mixed with published API surface | Demo stays in `example/` only |

---

## Target packages

```text
                    ┌─────────────────────────────┐
                    │   flutter_video_processor   │  ← app-facing SDK
                    │   (Dart facade + queue)     │
                    └──────────────┬──────────────┘
                                   │
              ┌────────────────────┼────────────────────┐
              ▼                    ▼                    ▼
┌──────────────────────┐  ┌──────────────────────────────┐
│ video_processor_core │  │ video_thumbnail_cache        │
│ Rust + FRB + hook    │  │ (optional disk LRU)          │
└──────────────────────┘  └──────────────────────────────┘
```

### Package 1 — `video_processor_core`

Rust `video_processor_core` cdylib, FRB bindings, native hook (FFmpeg). No `VideoProcessor` facade, no disk cache.

### Package 2 — `flutter_video_processor`

`VideoProcessor`, `VideoProcessorQueue`, `VideoJob`, presets. Depends on `video_processor_core` only (no `path_provider` / `crypto`).

### Package 3 — `video_thumbnail_cache` (optional)

`ThumbnailCache`, `thumbnailPathCached`, batch cached paths, eviction. Depends on `video_processor_core`.

---

## Hard boundaries

1. **`video_processor_core`** must not depend on `path_provider`, `crypto`, or `uuid`.
2. **`flutter_video_processor`** must not embed Rust sources or duplicate the native hook.
3. **`video_thumbnail_cache`** must not register FFI or ship FFmpeg artifacts.
4. **Example app** is not published; may depend on all layers.

---

## Consumer matrix

| App need | Packages |
|----------|----------|
| Compress / probe / jobs | `flutter_video_processor` or `video_processor_core` + FRB |
| In-memory thumbnails | `flutter_video_processor` |
| Filmstrip / `Image.file` cached paths | `flutter_video_processor` + `video_thumbnail_cache` |

---

## Repository layout

```text
rust_image/packages/
├── video_processor_core/     # rust/ + lib/frb + hook + android/ios
├── flutter_video_processor/  # SDK + example/
└── video_thumbnail_cache/
tools/video/                  # FFmpeg scripts (from rust video/tools)
video/Cargo.toml              # Rust workspace for video_processor_core
```

---

## Preview runtime (Sprint V1, planned)

Display and playback move to **MediaRuntime** + `rust_gpu_texture` — not `video_player` in the editor path. See [VIDEO_MEDIA_RUNTIME.md](VIDEO_MEDIA_RUNTIME.md). `video_processor_core` stays decode/encode; `flutter_video_processor` owns runtime + queue.

---

## References

- Legacy monorepo: [`rust video/README.md`](../rust%20video/README.md)
- Architecture: [`rust video/docs/architecture.md`](../rust%20video/docs/architecture.md)
- Sprint tracker: [ROADMAP.md](../ROADMAP.md) — Sprint V1

*Last updated: V0 split + V1 runtime design*
