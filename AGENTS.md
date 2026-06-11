# AGENTS.md

Instructions for AI agents working in this repository.

## Monorepo layout

- **Dart workspace** managed by `melos` (root `pubspec.yaml` has `melos:` config)
- **Three Rust crates** — not a single Cargo workspace:
  - `packages/image_forge/rust/` — image processing engine (standalone `Cargo.toml`)
  - `packages/video_forge/rust/` — video engine (workspace root at `packages/video_forge/Cargo.toml`, member `rust/`)
  - `packages/media_forge/rust/` — media playback engine (standalone `Cargo.toml`; FFmpeg + cpal for real-time video/audio decode and mixing)

## Package boundaries


| Package                   | Role                                        | Depends on                                         |
| ------------------------- | ------------------------------------------- | -------------------------------------------------- |
| `pixel_surface`        | GPU Texture bridge only                     | —                                                  |
| `image_forge`         | Rust engine + FRB APIs                     | `pixel_surface`                                  |
| `image_forge_editor`       | Editor UI (Riverpod)                       | `image_forge`, `pixel_surface`, `image_forge_camera` |
| `image_forge_camera`     | Live camera YUV stream                     | —                                                  |
| `media_forge`      | Media playback runtime (decode, clock, texture, audio) | `pixel_surface`                        |
| `video_forge`    | Video Rust engine + FFmpeg                  | —                                                  |
| `video_forge_kit` | Video compress/thumbnails SDK               | `video_forge`, `pixel_surface`, `video_forge_cache` |
| `video_forge_cache`   | Optional disk cache                         | —                                                  |


## Logging & observability (required when writing code)

**Every non-trivial change should include logs** so the next person (or agent) can follow what happened without guessing. Bugs often look like "UI didn't play" when the real failure was two layers earlier (e.g. mux file bad, not the player). Structured logs narrow the search quickly.

### When to add logs

Add or extend logging when you touch:

- **Async / multi-step flows** — job start, progress, success, failure (compress, decode, export, preview mux).
- **State machines** — open → ready → play → pause → dispose; cache hit vs miss; reopen vs reuse.
- **Boundaries** — Dart ↔ Rust (FRB), Flutter ↔ native plugins, file I/O (paths, durations, sizes).
- **Branches that can fail silently** — empty input, early return, fallback path, "success" with wrong data.
- **Bug fixes** — log the decisive state *at the layer you fixed*, not only in the UI.

Do **not** log inside hot loops (per-frame decode, `build()`, position tickers every 16 ms).

### Format (same idea in Dart and Rust)

Use a **stable bracket tag** per subsystem, then a short message and key=value fields:

| Layer | API | Example |
| ----- | --- | ------- |
| Dart / Flutter | `debugPrint` (or `kDebugMode` + `debugPrint`) | `debugPrint('[PreviewMux] ready ${durationMs}ms → $path');` |
| Rust (`video_forge`, etc.) | `log::info!` / `warn!` / `error!` / `debug!` | `log::info!("[preview] seek target_ms={}", t);` |
| Rust (`media_forge`) | `eprintln!` via `runtime_log!` macro | `runtime_log!("[AudioRuntime] cpal audio stream started successfully: rate={} channels={}", sample_rate, channels);` |

Rules:

1. **Tag** — `[ComponentName]` or `[crate::module]`; grep-friendly, one tag per file or feature area.
2. **Milestone, not noise** — one line per meaningful step (started, ready, opened, failed), not every internal variable.
3. **Decisive fields** — paths, durations, counts, flags (`muted`, `usesMux`), error + stack on failure.
4. **Failures are explicit** — `failed: $e` and stack in Dart; `log::error!(..., err)` in Rust with context (input path, stage name).
5. **Do not delete useful logs** when refactoring unless you replace them with equivalent milestones in the same layer.
6. **No secrets / PII** — avoid logging tokens, full user directories if unnecessary; paths to temp/cache files are OK for debug.

### How to use logs when debugging

1. Reproduce once with debug console or `flutter run` visible.
2. **Grep the tag** (e.g. `[PreviewMux]`, `[NativePlayback]`, `[AudioRuntime]`) and read lines **in order** — the first missing or wrong milestone is usually the right layer to fix.
3. If Dart says success but behavior is wrong, **verify artifacts outside Flutter** (`ffprobe`, `ffmpeg`, file size) before adding more UI logic.
4. After **Rust/native** changes, assume logs from old binaries are stale until a full native rebuild.

### Agent checklist (before marking work done)

- [ ] New or changed flow has logs at **start**, **success**, and **failure** (with error context).
- [ ] Tag is consistent with nearby code in the same package.
- [ ] A human can paste the log sequence and see which step failed without opening the debugger.
- [ ] No new high-frequency spam in listeners / decode loops.

Package-specific examples (media preview audio) are in **Debugging overlay audio preview** below.

## Build & test commands

### Full test suite (repo root)

```bash
chmod +x test_all.sh   # one time
./test_all.sh
```

Env knobs: `TEST_RUST_FEATURES` (default `gpu,blurhash`), `RUN_INTEGRATION=1`, `TEST_DEVICE` (default `macos`), `SKIP_NATIVE_SYNC=1`.

### **Per-layer commands**


| **Layer**                      | **Command**                                                                                    |
| ------------------------------ | ---------------------------------------------------------------------------------------------- |
| Rust image core                | `cd packages/image_forge/rust && cargo test --features gpu,blurhash`                        |
| Rust video core                | `cd packages/video_forge && cargo test -p video_forge`                        |
| Rust media runtime             | `cd packages/media_forge/rust && cargo test`                                              |
| Dart unit tests (editor)       | `cd packages/image_forge_editor && flutter test test/editor/`                                                    |
| Dart unit tests (media runtime) | `cd packages/media_forge && flutter test`                                                |
| Dart integration               | `cd examples/image_editor && flutter test integration_test/ -d <device>`                           |
| Dart analyze (all)              | `dart run melos analyze`                                                                        |


### **Per-package analyze via melos**

```
dart run melos exec --scope=image_forge_editor -- flutter analyze lib test --no-fatal-infos --no-fatal-warnings
dart run melos exec --scope=pixel_surface -- flutter analyze --no-fatal-infos
dart run melos exec --scope=media_forge -- flutter analyze --no-fatal-infos
```

### **Benchmarks**

**Rust CLI (fastest, no Flutter):**

```
cd packages/image_forge/rust
cargo run --release --features gpu --bin rust_image_benchmark -- --synthetic -n 10
```

**Dart/Flutter benchmarks** — must run inside Flutter, not `dart run` (FRB code crashes the standalone Dart VM):

```
cd benchmark && ./run_dart_benchmark.sh
BENCH_PIPELINE=worker ./run_dart_benchmark.sh   # editor isolate path
```

### **Run media_studio (macOS, with VT-capable FFmpeg)**

```
bash scripts/run-rust-media-macos.sh
```

Requires a VT-enabled FFmpeg build first: `bash scripts/build-ffmpeg-macos-vt.sh`.

## **FRB codegen**

After editing `rust/src/api/*.rs`, regenerate Dart bindings:

| Package | Command | Output |
|---------|---------|--------|
| `image_forge` | `cd packages/image_forge && flutter_rust_bridge_codegen generate` | `lib/src/rust/` |
| `video_forge` | `cd packages/video_forge && flutter_rust_bridge_codegen generate` | `lib/src/frb_generated/` |
| `media_forge` | `cd packages/media_forge && flutter_rust_bridge_codegen generate` | `lib/src/frb_generated/` |

**Never edit generated** `frb_generated.rs` or `lib/src/rust/*.dart` or `lib/src/frb_generated/*.dart` — they are overwritten.

FRB config per package: `flutter_rust_bridge.yaml` (rust_input: `crate::api`, dart_output varies by package).

## **media_forge: real-time audio mixing**

`media_forge` provides real-time overlay audio mixing via cpal (cross-platform audio I/O). The cpal callback mixes source video audio with overlay tracks in-process.

### Architecture (simplified)

```
Dart: MediaPlaybackEngine → addOverlayAudio / removeOverlayAudio / setMuted
       ↕ FRB
Rust:  AudioRuntime.start() → cpal output stream
         ├── Source audio    → PacketQueue → AudioDecoder → FrameQueue → cpal callback (mixed)
         └── Overlay tracks → OverlayDemuxer → OverlayDecoder → per-overlay FrameQueue → cpal callback (mixed)
```

### Known pitfalls

- **cpal callback is real-time** — do NOT lock per-overlay mutexes per sample. Pre-fetch overlay samples once per buffer, then mix from the local copy. Per-sample per-overlay locking causes priority inversion and audio dropouts.
- **Overlay sample rate** — `add_overlay()` reads the cpal device format (stored at `start()` time). If `add_overlay()` is called before `start()`, it falls back to 48000 Hz / 2 channels, which may not match the actual device.
- **`setMuted(true)`** mutes **all audio** (source + overlays) via the cpal callback silence path. It does NOT mute only the source. Use per-overlay volume instead.
- **`trim_end_ms`** silences all audio when the audio clock reaches the trim end. Do not set it to the video duration unless you want playback to end there.

## **media_studio: audio preview architecture**

The `examples/media_studio` example uses a **single Rust-backed playback path** for both the timeline preview and the home screen status previews — no `video_player`, no Flutter audio session conflict.

| Layer | Role |
| ----- | ---- |
| `video_creator_flow.dart` | Timeline UI, play/pause, seeks; calls `RustBackend.syncOverlayTracks()` whenever the audio clips change |
| `RustBackend` (`services/rust_backend.dart`) | Wraps `MediaPlaybackEngine` from `media_forge`. Demuxes the source file, decodes video + audio, uploads frames to a GPU texture |
| `media_forge` → cpal callback | Real-time mix of source audio + overlay tracks → output device. No temp file, no separate Flutter player |
| `RustStatusPlayer` (`widgets/rust_status_player.dart`) | Standalone `RustBackend` for full-screen status previews in the home Updates strip |

**Design rule (CapCut / Instagram style):** one playback clock, one mixed soundtrack, in the Rust runtime — not `video_player` + `just_audio` fighting for the macOS audio session, and no FFmpeg preview-mux round-trip.

The home status player and the timeline player are completely independent `RustBackend` instances (each with its own GPU texture handle) so opening / closing the home dialog does not disturb the timeline.

**After changing Rust in `media_forge/rust/src/api/runtime.rs`:** rebuild the native media core and re-run (e.g. `./scripts/run-rust-media-macos.sh`).

See also: `docs/VIDEO_MEDIA_RUNTIME.md` (audio roadmap A-2/A-3).

## **Debugging overlay audio preview (layered checklist)**

When the user reports "added audio track does not play", work **top to bottom**. Do not assume the bug is in Dart playback until the file and player state are verified.

### Step 1 — Confirm timeline state (Dart)

- Non-muted clip exists: `_exportAudioTracks()` is non-empty.
- `muteOriginalAudio` matches the UI ("Mute original video audio").
- Playhead is inside the clip window (`timelineStartMs` … `timelineEndMs`); outside range → no audio by design.

### Step 2 — Confirm Rust real-time audio mixing (Rust logs)

`media_studio` no longer does a preview-mux round-trip. Overlay audio is mixed in real time by the cpal callback. Look for these in order:

```
[AudioRuntime] cpal audio stream started successfully: rate=... channels=...
[AudioRuntime] Added overlay id=N path=... vol=... start=...ms dur=...ms source_start=...ms
[OverlayDemuxer] id=N started
[OverlayDemuxer] id=N initial seek to ...ms succeeded (master=...ms)
[OverlayDecoder] id=N started
```

| Log | Healthy meaning | If missing / wrong |
| --- | ----------------- | ------------------ |
| `cpal audio stream started` | Output device ready | FFmpeg/cpal init failed → no audio at all |
| `Added overlay id=N` | Overlay track registered with the engine | `syncOverlayTracks` not called from `_onTimelineUpdated` |
| `OverlayDemuxer` start + initial seek | Overlay demuxer positioned at master clock | `master=NaN` or seek exception → overlay silent from start |
| `OverlayDecoder started` | Overlay decoder thread is alive | Decoder thread crashed → overlay silent |

If overlays are present but source audio is silent while overlay audio plays:
1. Check `[AudioRuntime] Muted=...` — if `true`, source audio is deliberately muted (user toggle or bug).
2. Check `[AudioDecoder] Decoded N audio frames` — if 0, the source audio decoder is not producing frames.
3. Check source `FrameQueue` fullness — if always empty, the audio decoder thread may be starved by CPU contention (many overlay threads).
4. Check the cpal callback mixer — source audio `current_frame` should not be `None` for extended periods during playback.

### Step 3 — What we fixed once (do not reintroduce)

| Wrong approach | Why it failed |
| -------------- | ------------- |
| Second `VideoPlayerController` or `just_audio` for BGM | macOS audio session conflicts; `ProcessingState.completed` at pos 0 on broken files |
| `just_audio` + drift seeks on Apple Silicon | Position stuck at 0 → endless re-seek → silent playback |
| Muting original video whenever overlay exists | User hears nothing if overlay path fails |
| AAC stream added in `add_aac_output_stream` **before** `avcodec_open2` | MP4 missing proper AAC extradata; FFmpeg plays, AVPlayer often silent |
| Per-sample per-overlay Mutex locking in cpal callback | Priority inversion with 8+ overlay tracks: real-time audio callback blocked by decoder thread contention → source audio dropouts |
| Two `RustBackend` instances in the home status player and timeline | Both fighting for the macOS audio session via cpal — one stops. Each player uses its **own** `MediaPlaybackEngine` so the audio devices are independent. |

## **media_studio preview: log tags (reference)**

Follow **Logging & observability** above. These tags already exist for overlay-audio preview:

| Tag | File | Log after |
| --- | ---- | --------- |
| `[PreviewMux]` | `examples/media_studio/lib/services/preview_playback_mux.dart` | Cache miss, job start, `ready`, failures |
| `[PreviewMux]` | `examples/media_studio/lib/video_creator_flow.dart` | `ensure ready`, `opened muxed=`, reopen decisions |
| `[NativePlayback]` | `packages/video_forge_kit/lib/src/playback/native_playback_controller.dart` | `open`, `volume`, `play` |
| `[AudioRuntime]` | `packages/media_forge/rust/src/api/runtime.rs` | `cpal audio stream started`, `Muted=`, overlay add/remove |
| `[OverlayDemuxer]` | `packages/media_forge/rust/src/api/runtime.rs` | Overlay demuxer seek/start/finish |
| `[MediaPlaybackEngine]` | `packages/media_forge/rust/src/api/runtime.rs` | `Starting runtimes`, `Trim range set`, `Seeking to` |
| `[RustBackend]` | `examples/media_studio/lib/services/rust_backend.dart` | `addOverlayAudio`, `removeOverlayAudio`, `setEmbeddedAudioMuted` |

Rust side: `log::` in `packages/video_forge/rust/src/pipeline/` (preview, transcode, `audio_mix`); `runtime_log!` (eprintln) in `packages/media_forge/rust/src/api/runtime.rs`.

### Example healthy sequence (copy when verifying fixes) — Native backend

```
[PreviewMux] building .../preview_abc.mp4 (1 track(s))
[PreviewMux] ready 71800ms → .../preview_abc.mp4
[PreviewMux] ensure ready path=.../preview_abc.mp4 current=.../original.mp4 usesMux=false needsReopen=true
[NativePlayback] open path=.../preview_abc.mp4 duration=71800ms audio=aac muted=false
[NativePlayback] volume path=.../preview_abc.mp4 muted=false
[PreviewMux] opened muxed=true path=.../preview_abc.mp4 isOpen=true duration=71800ms playAfterOpen=true
[NativePlayback] play path=.../preview_abc.mp4 pos=0ms trim=0-71800 playing=true
```

### Example healthy sequence — Rust backend

```
[AudioRuntime] cpal audio stream started successfully: rate=48000 channels=2
[AudioRuntime] Added overlay id=1 path=... vol=0.17 start=0ms dur=75050ms source_start=87326ms
[OverlayDemuxer] id=1 started path=...
[OverlayDemuxer] id=1 initial seek to ...ms succeeded (master=...ms)
[OverlayDecoder] id=1 started
[MediaPlaybackEngine] Starting runtimes
[PlaybackClock] Playback started rate=1 media_time_ms=...
[AudioDecoder] Decoded ... audio frames, current PTS: ...ms
```

If audio sequence appears but source audio is silent while overlay plays, check `[AudioRuntime] Muted=...` and source `FrameQueue` fullness.

## **Gotchas**

- **AVIF encoder needs NASM** — builds fail on hosts without it. Use `TEST_RUST_FEATURES=gpu,blurhash` (no avif) unless NASM is installed.
- **Android builds require** `rustup`, not Homebrew `rustc`. The repo has `rust/rust-toolchain.toml` for auto-installing Android targets. If you see `can't find crate for core`, run `rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android i686-linux-android`.
- **Three Rust crate roots** — `packages/image_forge/rust/` standalone; `packages/video_forge/Cargo.toml` workspace root with `rust/` member; `packages/media_forge/rust/` standalone.
- `dart run` **does not work** for FRB-based benchmarks or apps. Always use `flutter run` or `flutter test`.
- **First Android build** compiles Rust for each ABI — can take several minutes.
- **Melos bootstrap** required after cloning: `dart pub get && dart run melos bootstrap`.
- **media_forge needs FFmpeg with VideoToolbox** for HW decode on macOS. Run `bash scripts/build-ffmpeg-macos-vt.sh` first, then `bash scripts/run-rust-media-macos.sh`. Homebrew FFmpeg works for SW decode but lacks `hevc_videotoolbox` HW accel.
- **media_forge is not yet in CI** — `.github/workflows/ci.yml` does not include `media_forge` analyze/test steps. Run them manually: `cd packages/media_forge && flutter analyze --no-fatal-infos` and `cd packages/media_forge/rust && cargo test`.

## **image_forge_editor UI conventions**

The Lumina Darkroom editor (`packages/image_forge_editor/`) is a **dark-only, single-accent (mint `#4EDEA3`) editor**. Use these conventions when adding or refactoring UI:

### Design tokens (`lib/src/editor/theme/lumina_tokens.dart`)

| Use | Read from | Don't |
| --- | --- | --- |
| Surface color | `LuminaTokens.surfaceContainerLow` (chrome) / `surfaceContainer` (panels) / `surfaceContainerHigh` (chips) / `canvas` (scaffold) | hardcode `Color(0xFF…)` |
| Foreground | `LuminaTokens.onSurface` / `onSurfaceVariant` / `onSurfaceMuted` | `Colors.white`, `Colors.white70` |
| Accent | `LuminaTokens.accent` (mint) / `accentContainer` (selected) | the legacy `primary` (kept as an alias) |
| Spacing | `LuminaTokens.space1`..`space8` (4-pt scale) | ad-hoc integers |
| Radius | `LuminaTokens.radiusXs`..`radius2xl` | `BorderRadius.circular(8)` |
| Touch target | `LuminaTokens.touchTarget = 44` for tool buttons | `IconButton` without explicit size |
| Breakpoints | `LuminaTokens.breakpointPhone` (600) / `breakpointTablet` (900) / `breakpointDesktop` (1100) / `breakpointLarge` (1440) | scattered `width >= 900` checks |

### Reusable widgets (exported from `image_forge_editor`)

| Widget | Use for | Notes |
| --- | --- | --- |
| `ValueChipSlider` | All sliders (Adjust, Beauty, Paint, Shapes, Overlay, Transform) | CapCut-style value bubble, double-tap reset, center detent haptic. |
| `ChipPill` / `ChipPillRow` / `ChipPillWrap` | Choice-of-N selections | 32-px tall, accent fill when selected. |
| `ToolButton` | Mobile bottom nav + "More" sheet + desktop rail | 44-pt hit target, filled/outlined icon swap. |
| `FrostedBar` | Mobile top/bottom bars, desktop inspector header, desktop top bar | `BackdropFilter` blur over translucent surface. |
| `InspectorPanel` | Desktop right-side properties panel | Titled header (tool name + Reset/Done), scroll-fade body, status footer. |
| `CategorizedToolRail` | Desktop left rail with Edit / Decorate / Manage sections | Built atop `NavigationRail` styling but as a custom scrollable column. |
| `FilterThumbnail` | Filter strip cells | Real thumbnails cached in `FilterThumbnailCache` (LRU 32). |
| `AdjustPageViewPanel` | The Adjust tool | Horizontal `PageView` of 12 adjustments (Brightness, Contrast, Saturation, Warmth, Hue, Fade, Vignette, Highlights, Shadows, Sharpen, Structure, Grain). |

### Selected state vocabulary
- **Filled vs. outlined icon**: use `EditorIcons.filled(tool)` for selected, `EditorIcons.outlined(tool)` for unselected. The accent color is `LuminaTokens.accent` for filled, `onSurfaceVariant` for outlined.
- **Underline** at the bottom of mobile tool buttons (2 px, 16 px wide, accent).
- **Container fill** in the desktop rail and chip pills.
- **Border** in cards and inspector panel sections.

### Typography
- `AppTypography.toolName` (17 pt w600) for the active tool name in the title bar and inspector header — **sentence case** (no `.toUpperCase()` for buttons or titles).
- `AppTypography.sectionCaps` (11 pt w600, +0.4 letter-spacing) for inspector section labels only.
- `AppTypography.numericValue` / `sliderValueBubble` (mono 12 pt) for slider values, accent color.
- `AppTypography.navLabel` (11 pt w500) for tool palette labels.

### Motion
- `EditorMotion.fast` (150 ms) for icon swaps, chip selection.
- `EditorMotion.medium` (250 ms) for panel cross-fade.
- `EditorMotion.slow` (400 ms) for sheet enter.
- All durations use `Curves.fastOutSlowIn` (Material 3 standard).

### Layout
- **Mobile (< 900 dp)**: 5 curated primary tools in the bottom nav + a "More" overflow sheet. Frosted top bar with the active tool name. Draggable tool sheet with grabber.
- **Desktop (≥ 900 dp)**: `CategorizedToolRail` on the left, `LivePreview` in the center, `InspectorPanel` on the right (widens to 480 px at ≥ 1440 dp). Grouped top bar with `[title] | [status] | [history] | [compare] | [export]`.
- **Always** route layout decisions through `LuminaTokens.breakpoint*` constants — no scattered `width >= 900` checks.

### New log tags
In addition to the tags in the Logging section above, the editor adds:

| Tag | File | Log after |
| --- | --- | --- |
| `[EditorChrome]` | `lib/src/editor/layout/mobile_editor_chrome.dart` and `editor_screen.dart` | Tool selection, sheet open/close, layout mode choice. |
| `[AdjustStrip]` | `lib/src/editor/panels/adjust_pageview_panel.dart` | Page change, `Auto` pressed, Reset pressed. |
| `[FilterThumb]` | `lib/src/editor/widgets/filter_thumbnail.dart` | Bake start, cache hit, cache miss + decode done, decode fail. |

Use `debugPrint('[Tag] event key=value')` style for these.

## **CI**

`.github/workflows/ci.yml` runs on `ubuntu-latest`: melos bootstrap → per-package analyze → per-package test → Rust video test. No native build step in CI (Dart-only checks).
