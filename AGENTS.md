# AGENTS.md

Instructions for AI agents working in this repository.

## Monorepo layout

- **Dart workspace** managed by `melos` (root `pubspec.yaml` has `melos:` config)
- **Two Rust crates** — not a single Cargo workspace:
  - `packages/rust_image_core/rust/` — image processing engine (standalone `Cargo.toml`)
  - `packages/video_processor_core/rust/` — video engine (workspace root at `packages/video_processor_core/Cargo.toml`, member `rust/`)
- `**rust_image/`** is a thin shim that re-exports `rust_image_editor`. Do not add logic there.

## Package boundaries


| Package                   | Role                          | Depends on                                                   |
| ------------------------- | ----------------------------- | ------------------------------------------------------------ |
| `rust_gpu_texture`        | GPU Texture bridge only       | —                                                            |
| `rust_image_core`         | Rust engine + FRB APIs        | `rust_gpu_texture`                                           |
| `rust_image_editor`       | Editor UI (Riverpod)          | `rust_image_core`, `rust_gpu_texture`, `rust_camera_runtime` |
| `rust_camera_runtime`     | Live camera YUV stream        | —                                                            |
| `video_processor_core`    | Video Rust engine + FFmpeg    | —                                                            |
| `flutter_video_processor` | Video compress/thumbnails SDK | `video_processor_core`                                       |
| `video_thumbnail_cache`   | Optional disk cache           | —                                                            |


## Logging & observability (required when writing code)

**Every non-trivial change should include logs** so the next person (or agent) can follow what happened without guessing. Bugs often look like “UI didn’t play” when the real failure was two layers earlier (e.g. mux file bad, not the player). Structured logs narrow the search quickly.

### When to add logs

Add or extend logging when you touch:

- **Async / multi-step flows** — job start, progress, success, failure (compress, decode, export, preview mux).
- **State machines** — open → ready → play → pause → dispose; cache hit vs miss; reopen vs reuse.
- **Boundaries** — Dart ↔ Rust (FRB), Flutter ↔ native plugins, file I/O (paths, durations, sizes).
- **Branches that can fail silently** — empty input, early return, fallback path, “success” with wrong data.
- **Bug fixes** — log the decisive state *at the layer you fixed*, not only in the UI.

Do **not** log inside hot loops (per-frame decode, `build()`, position tickers every 16 ms).

### Format (same idea in Dart and Rust)

Use a **stable bracket tag** per subsystem, then a short message and key=value fields:

| Layer | API | Example |
| ----- | --- | ------- |
| Dart / Flutter | `debugPrint` (or `kDebugMode` + `debugPrint`) | `debugPrint('[PreviewMux] ready ${durationMs}ms → $path');` |
| Rust (`video_processor_core`, etc.) | `log::info!` / `warn!` / `error!` / `debug!` | `log::info!("[preview] seek target_ms={}", t);` |

Rules:

1. **Tag** — `[ComponentName]` or `[crate::module]`; grep-friendly, one tag per file or feature area.
2. **Milestone, not noise** — one line per meaningful step (started, ready, opened, failed), not every internal variable.
3. **Decisive fields** — paths, durations, counts, flags (`muted`, `usesMux`), error + stack on failure.
4. **Failures are explicit** — `failed: $e` and stack in Dart; `log::error!(..., err)` in Rust with context (input path, stage name).
5. **Do not delete useful logs** when refactoring unless you replace them with equivalent milestones in the same layer.
6. **No secrets / PII** — avoid logging tokens, full user directories if unnecessary; paths to temp/cache files are OK for debug.

### How to use logs when debugging

1. Reproduce once with debug console or `flutter run` visible.
2. **Grep the tag** (e.g. `[PreviewMux]`, `[NativePlayback]`) and read lines **in order** — the first missing or wrong milestone is usually the right layer to fix.
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


| **Layer**                | **Command**                                                              |
| ------------------------ | ------------------------------------------------------------------------ |
| Rust image core          | `cd packages/rust_image_core/rust && cargo test --features gpu,blurhash` |
| Rust video core          | `cd packages/video_processor_core && cargo test -p video_processor_core` |
| Dart unit tests (editor) | `cd rust_image && flutter test test/editor/`                             |
| Dart integration         | `cd rust_image/example && flutter test integration_test/ -d <device>`    |
| Dart analyze (all)       | `dart run melos analyze`                                                 |


### **Per-package analyze via melos**

```
dart run melos exec --scope=rust_image_editor -- flutter analyze lib test --no-fatal-infos --no-fatal-warnings
dart run melos exec --scope=rust_gpu_texture -- flutter analyze --no-fatal-infos
```

### **Benchmarks**

**Rust CLI (fastest, no Flutter):**

```
cd packages/rust_image_core/rust
cargo run --release --features gpu --bin rust_image_benchmark -- --synthetic -n 10
```

**Dart/Flutter benchmarks** — must run inside Flutter, not `dart run` (FRB code crashes the standalone Dart VM):

```
cd rust_image/benchmark && ./run_dart_benchmark.sh
BENCH_PIPELINE=worker ./run_dart_benchmark.sh   # editor isolate path
```

## **FRB codegen**

After editing `rust/src/api/*.rs`, regenerate Dart bindings:

```
cd packages/rust_image_core
flutter_rust_bridge_codegen generate
```

Output goes to `lib/src/rust/`. **Never edit generated** `frb_generated.rs` **or** `lib/src/rust/*.dart` — they are overwritten.

FRB config per package: `flutter_rust_bridge.yaml` (rust_input: `crate::api`, dart_output: `lib/src/rust`).

## **media_studio: audio preview architecture**

Background audio in `examples/media_studio` is **not** played by a second Flutter audio player during preview.

| Layer | Role |
| ----- | ---- |
| `video_creator_flow.dart` | Timeline UI, play/pause, seeks; calls preview mux when overlay tracks exist |
| `preview_playback_mux.dart` | Builds a temporary MP4 via `VideoProcessor.compressJob` (same mix path as export) |
| `video_processor_core` → `audio_mix.rs` | FFmpeg mix: original video audio + timeline `AudioTrackInput` lanes → one AAC stream |
| `NativePlaybackController` | Single `video_player` instance plays either the source file or the muxed preview file |

**Design rule (CapCut / Instagram style):** one playback clock, one mixed soundtrack for preview — not `video_player` + `just_audio` fighting for the macOS audio session.

**After changing Rust in `audio_mix.rs` or transcode:** hot restart is **not** enough. Rebuild native video core and re-run the app (e.g. `./scripts/run-video-macos.sh`). Old `preview_*.mp4` files in cache may have been built with a previous buggy encoder; delete `~/Library/Caches/.../preview_mux/` or add a new track to force a fresh mux.

See also: `docs/VIDEO_MEDIA_RUNTIME.md` (audio roadmap A-2/A-3).

## **Debugging overlay audio preview (layered checklist)**

When the user reports “added audio track does not play”, work **top to bottom**. Do not assume the bug is in Dart playback until the file and player state are verified.

### Step 1 — Confirm timeline state (Dart)

- Non-muted clip exists: `_exportAudioTracks()` is non-empty.
- `muteOriginalAudio` matches the UI (“Mute original video audio”).
- Playhead is inside the clip window (`timelineStartMs` … `timelineEndMs`); outside range → no audio by design.

### Step 2 — Confirm mux ran (Dart logs)

Look for these lines in order:

```
[PreviewMux] building .../preview_<key>.mp4 (N track(s))
[PreviewMux] ready <duration>ms → <path>
[PreviewMux] ensure ready path=... current=... usesMux=... needsReopen=...
[PreviewMux] opened muxed=true path=... isOpen=true duration=...ms playAfterOpen=...
```

| Log | Healthy meaning | If missing / wrong |
| --- | ----------------- | ------------------ |
| `building` | FFmpeg job started | No overlay tracks, or `PreviewPlaybackMux.ensure` not called |
| `ready` | Output file exists and has duration | Compress/mix failed; check `Preview mix failed` |
| `ensure ready` | Cache hit/miss and reopen decision | Stale cache key; path mismatch |
| `opened` | Player switched to mux file | Still on `widget.initialPath` → `usesMux=false` or reopen skipped |

### Step 3 — Confirm player handoff (Dart logs)

```
[NativePlayback] open path=... duration=...ms audio=... muted=false
[NativePlayback] volume path=... muted=false
[NativePlayback] play path=... pos=...ms trim=... playing=true
```

| Log | Healthy meaning | Red flag |
| --- | ----------------- | -------- |
| `open` | `video_player` initialized on mux path | `open` still shows original Downloads path after play with tracks |
| `volume muted=false` | Embedded audio not silenced on mux | `muted=true` while muxed (UI or export sheet toggled volume) |
| `play ... playing=true` | Controller thinks it is playing | `playing=true` but user hears nothing → **suspect file/container**, not Dart |

**Misleading case:** `playing=true` with **no sound** usually means the MP4 is bad for AVPlayer, not that `play()` was never called.

### Step 4 — Verify the mux file outside Flutter (required before more Dart changes)

On the path from `[PreviewMux] ready`:

```bash
# Streams present?
ffprobe -v error -show_entries stream=codec_type,codec_name,profile,duration \
  -of default=noprint_wrappers=1 "/path/to/preview_*.mp4"

# Audible signal? (should NOT be silent)
ffmpeg -hide_banner -i "/path/to/preview_*.mp4" -map 0:a:0 -af volumedetect -f null - 2>&1
```

| Observation | Interpretation |
| ------------- | ---------------- |
| No audio stream | Rust mix/export bug |
| Audio stream, `volumedetect` shows mean/max dB | File is fine; bug is player/session/UI mute |
| AAC `profile=-1` or missing vs source `AAC LC` | Rust AAC mux header/extradata bug (`audio_mix.rs` — encoder must be **opened before** `write_header`) |
| FFmpeg loud, AVPlayer silent | Classic “decodeable but AVFoundation-hostile” container — fix Rust mux, not Flutter |

### Step 5 — What we fixed once (do not reintroduce)

| Wrong approach | Why it failed |
| -------------- | ------------- |
| Second `VideoPlayerController` or `just_audio` for BGM | macOS audio session conflicts; `ProcessingState.completed` at pos 0 on broken files |
| `just_audio` + drift seeks on Apple Silicon | Position stuck at 0 → endless re-seek → silent playback |
| Muting original video whenever overlay exists | User hears nothing if overlay path fails |
| AAC stream added in `add_aac_output_stream` **before** `avcodec_open2` | MP4 missing proper AAC extradata; FFmpeg plays, AVPlayer often silent |

## **media_studio preview: log tags (reference)**

Follow **Logging & observability** above. These tags already exist for overlay-audio preview:

| Tag | File | Log after |
| --- | ---- | --------- |
| `[PreviewMux]` | `examples/media_studio/lib/services/preview_playback_mux.dart` | Cache miss, job start, `ready`, failures |
| `[PreviewMux]` | `examples/media_studio/lib/video_creator_flow.dart` | `ensure ready`, `opened muxed=`, reopen decisions |
| `[NativePlayback]` | `packages/flutter_video_processor/lib/src/playback/native_playback_controller.dart` | `open`, `volume`, `play` |

Rust side: `log::` in `packages/video_processor_core/rust/src/pipeline/` (preview, transcode, `audio_mix`).

### Example healthy sequence (copy when verifying fixes)

```
[PreviewMux] building .../preview_abc.mp4 (1 track(s))
[PreviewMux] ready 71800ms → .../preview_abc.mp4
[PreviewMux] ensure ready path=.../preview_abc.mp4 current=.../original.mp4 usesMux=false needsReopen=true
[NativePlayback] open path=.../preview_abc.mp4 duration=71800ms audio=aac muted=false
[NativePlayback] volume path=.../preview_abc.mp4 muted=false
[PreviewMux] opened muxed=true path=.../preview_abc.mp4 isOpen=true duration=71800ms playAfterOpen=true
[NativePlayback] play path=.../preview_abc.mp4 pos=0ms trim=0-71800 playing=true
```

If this sequence appears but the user still hears nothing, run Step 4 (`ffprobe` / `volumedetect`) before changing Dart again.

## **Gotchas**

- **AVIF encoder needs NASM** — builds fail on hosts without it. Use `TEST_RUST_FEATURES=gpu,blurhash` (no avif) unless NASM is installed.
- **Android builds require** `rustup`, not Homebrew `rustc`. The repo has `rust/rust-toolchain.toml` for auto-installing Android targets. If you see `can't find crate for core`, run `rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android i686-linux-android`.
- **Two Rust workspace roots** — `packages/rust_image_core/rust/` is standalone; `packages/video_processor_core/Cargo.toml` is a workspace root with `rust/` member. `rust video/` is legacy — ignore it.
- `dart run` **does not work** for FRB-based benchmarks or apps. Always use `flutter run` or `flutter test`.
- **First Android build** compiles Rust for each ABI — can take several minutes.
- **Melos bootstrap** required after cloning: `dart pub get && dart run melos bootstrap`.

## **CI**

`.github/workflows/ci.yml` runs on `ubuntu-latest`: melos bootstrap → per-package analyze → per-package test → Rust video test. No native build step in CI (Dart-only checks).