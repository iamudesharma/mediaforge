# Benchmarks: media_forge_player vs legacy paths

## What to measure (and where the numbers come from)

| Metric | Source | Healthy |
| --- | --- | --- |
| CPU % (decode + present) | OS monitor during 1080p playback | lower with VT HW + zero-copy |
| Memory (pools) | `GpuTextureRegistry.debugStats()` + Xcode/AS profiler | stable across seeks; `flushPools()` drops backlog |
| Dropped frames | `MediaForgeDiagnostics.droppedFrames` (no new frame while playing) | ~0 on HW, bounded on SW |
| Decoded FPS / presented FPS | `MediaForgeDiagnostics.decodedFps/presentedFps` | presented ≈ display vsync; decoded ≥ content fps |
| Seek latency | time `seek()` → `position` reaches target ±250 ms | p95 ≤ 300 ms local |
| A/V drift | `MediaForgeDiagnostics.avDriftMs` | < 500 ms healthy, > 2000 ms triggers Rust hard resync |

## Baselines to compare against

1. **Legacy `video_player` path** (`video_forge_kit`
   `NativePlaybackController` + preview-mux temp file): measures the old
   mux-then-play round-trip this package replaces.
2. **Raw `media_forge` example** (`Timer(16ms)` presenter + 250 ms
   diagnostics): same engine, old Dart pacing — isolates the vsync +
   stable-texture win.
3. **This package** (vsync loop + `resizeTexture` + zero-copy first).

## Procedure

1. Build VT-capable FFmpeg: `bash scripts/build-ffmpeg-macos-vt.sh`.
2. Run: `bash scripts/run-rust-media-macos.sh` (or the player example).
3. Play the same 1080p H.264 + 4K HEVC fixtures over file and over the
   localhost Range server (`test/range_server_test.dart` is the contract).
4. Record 60 s per fixture: CPU, memory, `droppedFrames`, `presentedFps`,
   5× seek latencies, drift p95.
5. Report table + `debugStats()` before/after seeks.

## v1 status

No numbers are claimed here — fixtures and CI devices vary. The
diagnostics plumbing (`MediaForgeDiagnostics`, `debugStats`, Range
contract test) is the instrumentation this benchmark runs on. Fill the
table below with measured runs before publishing:

| Fixture | Path | CPU | Mem Δ | Dropped | presFps | Seek p95 | Drift p95 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1080p H.264 file | player | — | — | — | — | — | — |
| 1080p H.264 http  | player | — | — | — | — | — | — |
| 4K HEVC file      | player | — | — | — | — | — | — |
| 1080p H.264 file  | legacy | — | — | — | — | — | — |
