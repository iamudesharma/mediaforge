# Video package split (pre-publish architecture)

**Status:** V0.1–V0.6 in progress — engine, SDK, and optional thumbnail cache under [`packages/`](../packages/).

**Goal:** Three independently versioned packages with hard dependency boundaries. Host apps choose only what they need (engine/FRB only, ergonomic SDK, or disk-cached filmstrip helpers).

**Related:** Image split [PUB_PACKAGE_SPLIT.md](PUB_PACKAGE_SPLIT.md) · [V0_ACCEPTANCE.md](V0_ACCEPTANCE.md) · preview runtime [VIDEO_MEDIA_RUNTIME.md](VIDEO_MEDIA_RUNTIME.md) (Sprint V1) · FFmpeg tooling in [`tools/ffmpeg/`](../tools/ffmpeg/).

---

## Why split

| Problem (monolith `video_forge_kit`) | After split |
|---------------------------------------------|-------------|
| FFmpeg hook + FRB + disk cache ship one version | Patch cache without touching compress API |
| Upload backends pull `path_provider` / `crypto` for compress-only | Minimal transitive deps on `video_forge` |
| Breaking FRB types force SDK major bump | `video_forge` majors independently |
| Example UI mixed with published API surface | Demo stays in `example/` only |

---

## Target packages

```text
                    ┌─────────────────────────────┐
                    │   video_forge_kit   │  ← app-facing SDK
                    │   (Dart facade + queue)     │
                    └──────────────┬──────────────┘
                                   │
              ┌────────────────────┼────────────────────┐
              ▼                    ▼                    ▼
┌──────────────────────┐  ┌──────────────────────────────┐
│ video_forge │  │ video_forge_cache        │
│ Rust + FRB + hook    │  │ (optional disk LRU)          │
└──────────────────────┘  └──────────────────────────────┘
```

### Package 1 — `video_forge`

Rust `video_forge` cdylib, FRB bindings, native hook (FFmpeg). No `VideoProcessor` facade, no disk cache.

### Package 2 — `video_forge_kit`

`VideoProcessor`, `VideoProcessorQueue`, `VideoJob`, presets. Depends on `video_forge` only (no `path_provider` / `crypto`).

### Package 3 — `video_forge_cache` (optional)

`ThumbnailCache`, `thumbnailPathCached`, batch cached paths, eviction. Depends on `video_forge`.

---

## Hard boundaries

1. **`video_forge`** must not depend on `path_provider`, `crypto`, or `uuid`.
2. **`video_forge_kit`** must not embed Rust sources or duplicate the native hook.
3. **`video_forge_cache`** must not register FFI or ship FFmpeg artifacts.
4. **Example app** is not published; may depend on all layers.

---

## Consumer matrix

| App need | Packages |
|----------|----------|
| Compress / probe / jobs | `video_forge_kit` or `video_forge` + FRB |
| In-memory thumbnails | `video_forge_kit` |
| Filmstrip / `Image.file` cached paths | `video_forge_kit` + `video_forge_cache` |

---

## Repository layout

```text
rust_image/packages/
├── video_forge/     # rust/ + lib/frb + hook + android/ios
├── video_forge_kit/  # SDK + example/
└── video_forge_cache/
tools/ffmpeg/                 # FFmpeg build scripts
video/Cargo.toml              # Rust workspace for video_forge
```

---

## Preview runtime (Sprint V1, planned)

Display and playback move to **MediaRuntime** + `pixel_surface` — not `video_player` in the editor path. See [VIDEO_MEDIA_RUNTIME.md](VIDEO_MEDIA_RUNTIME.md). `video_forge` stays decode/encode; `video_forge_kit` owns runtime + queue.

---

## References

- FFmpeg builds: [`tools/ffmpeg/`](../tools/ffmpeg/)
- Sprint tracker: [ROADMAP.md](../ROADMAP.md) — Sprint V1

*Last updated: V0 split + V1 runtime design*
