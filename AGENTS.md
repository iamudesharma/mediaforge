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

Background audio in `examples/media_studio` is **not** played by a second Flutter audio player during preview.

| Layer | Role |
| ----- | ---- |
| `video_creator_flow.dart` | Timeline UI, play/pause, seeks; calls preview mux when overlay tracks exist |
| `preview_playback_mux.dart` | Builds a temporary MP4 via `VideoProcessor.compressJob` (same mix path as export) |
| `video_forge` → `audio_mix.rs` | FFmpeg mix: original video audio + timeline `AudioTrackInput` lanes → one AAC stream |
| `NativePlaybackController` | Single `video_player` instance plays either the source file or the muxed preview file |

**Design rule (CapCut / Instagram style):** one playback clock, one mixed soundtrack for preview — not `video_player` + `just_audio` fighting for the macOS audio session.

When using the **Rust backend** (`_useRustBackend = true`), overlays are mixed in real-time by `media_forge`'s cpal callback — no preview mux is needed. The `syncOverlayTracks()` method on `RustBackend` adds/removes overlay tracks directly.

**After changing Rust in `audio_mix.rs` or transcode:** hot restart is **not** enough. Rebuild native video core and re-run the app (e.g. `./scripts/run-video-macos.sh`). Old `preview_*.mp4` files in cache may have been built with a previous buggy encoder; delete `~/Library/Caches/.../preview_mux/` or add a new track to force a fresh mux.

**After changing Rust in `media_forge/rust/src/api/runtime.rs`:** rebuild the native media core and re-run (e.g. `./scripts/run-rust-media-macos.sh`).

See also: `docs/VIDEO_MEDIA_RUNTIME.md` (audio roadmap A-2/A-3).

## **Debugging overlay audio preview (layered checklist)**

When the user reports "added audio track does not play", work **top to bottom**. Do not assume the bug is in Dart playback until the file and player state are verified.

### Step 1 — Confirm timeline state (Dart)

- Non-muted clip exists: `_exportAudioTracks()` is non-empty.
- `muteOriginalAudio` matches the UI ("Mute original video audio").
- Playhead is inside the clip window (`timelineStartMs` … `timelineEndMs`); outside range → no audio by design.

### Step 2 — Confirm mux ran (Dart logs) — Native backend only

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

### Step 2b — Confirm Rust backend audio mixing (Rust logs) — Rust backend

When using the Rust backend (`_useRustBackend = true`), overlay audio is mixed in real-time by the cpal callback. Look for:

```
[AudioRuntime] Added overlay id=N path=... vol=... start=...ms dur=...ms source_start=...ms
[AudioRuntime] cpal audio stream started successfully: rate=... channels=...
[OverlayDemuxer] id=N initial seek to ...ms succeeded (master=...ms)
[OverlayDecoder] id=N started
```

If overlays are present but source audio is silent while overlay audio plays:
1. Check `[AudioRuntime] Muted=...` — if `true`, source audio is deliberately muted (user toggle or bug).
2. Check `[AudioDecoder] Decoded N audio frames` — if 0, the source audio decoder is not producing frames.
3. Check source `FrameQueue` fullness — if always empty, the audio decoder thread may be starved by CPU contention (many overlay threads).
4. Check the cpal callback mixer — source audio `current_frame` should not be `None` for extended periods during playback.

### Step 3 — Confirm player handoff (Dart logs) — Native backend only

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

### Step 4 — Verify the mux file outside Flutter (required before more Dart changes) — Native backend only

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
| FFmpeg loud, AVPlayer silent | Classic "decodeable but AVFoundation-hostile" container — fix Rust mux, not Flutter |

### Step 5 — What we fixed once (do not reintroduce)

| Wrong approach | Why it failed |
| -------------- | ------------- |
| Second `VideoPlayerController` or `just_audio` for BGM | macOS audio session conflicts; `ProcessingState.completed` at pos 0 on broken files |
| `just_audio` + drift seeks on Apple Silicon | Position stuck at 0 → endless re-seek → silent playback |
| Muting original video whenever overlay exists | User hears nothing if overlay path fails |
| AAC stream added in `add_aac_output_stream` **before** `avcodec_open2` | MP4 missing proper AAC extradata; FFmpeg plays, AVPlayer often silent |
| Per-sample per-overlay Mutex locking in cpal callback | Priority inversion with 8+ overlay tracks: real-time audio callback blocked by decoder thread contention → source audio dropouts |

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

## **CI**

`.github/workflows/ci.yml` runs on `ubuntu-latest`: melos bootstrap → per-package analyze → per-package test → Rust video test. No native build step in CI (Dart-only checks).
