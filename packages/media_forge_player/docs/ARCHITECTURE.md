# Architecture proposal: media_forge_player

## Goal

A reusable pub.dev-ready player: `video_player`-like usability, `media_kit`
ambition, powered by this repo's engine — not a new decoder, not a
`pixel_surface`-only widget.

## Layers

```
┌────────────────────────────────────────────┐
│ media_forge_player (Dart, this package)    │
│ controller, value, widget, tracks, diag    │
├────────────────────────────────────────────┤
│ media_forge (Rust + FRB)                   │
│ demux, decode, audio-master clock, seek,   │
│ HW accel, diagnostics                      │
├────────────────────────────────────────────┤
│ pixel_surface (native + Dart)              │
│ Flutter Texture bridge, CVPixelBuffer /    │
│ SurfaceTexture, pools                      │
└────────────────────────────────────────────┘
```

## Reused components

| Need | Source | Path |
| --- | --- | --- |
| Engine open/start/pause/stop/seek/rate/mute | `media_forge` | `rust/src/api/runtime.rs` `MediaPlaybackEngine` |
| Audio-master clock, cpal mix | `media_forge` | `AudioRuntime`, `PlaybackClock`, `presenter_runtime` |
| Single-shot diagnostics | `media_forge` | `getDiagnostics()` → `PlaybackDiagnostics` |
| Capability probe | `media_forge` | `probe_decode_capabilities()` |
| VT zero-copy handoff | `media_forge` | `mediaVideoFrameIntoPixelBufferHandoff` |
| Texture create/present/resize/pools/stats | `pixel_surface` | `GpuTextureRegistry`, `PixelBufferPool` |
| Video widget primitive | `pixel_surface` | `GpuTextureView` |
| Backend interface shape | `video_forge_editor` | `playback/playback_backend.dart`, `rust_playback_backend.dart` (patterns only) |
| Android single-frame zero-copy reference | `pixel_surface` | `AndroidPreviewDecoder.kt`, `RustGpuTexturePlugin.kt` |
| Scrub/debounce + adaptive-edge ideas | `video_forge_kit` | `media_runtime.dart`, `frame_queue.dart` (patterns only) |
| Thumbnail disk cache (future posters) | `video_forge_cache` | `thumbnail_cache.dart` |

Nothing was copied; the player depends on `media_forge` + `pixel_surface`.

## Presentation design (vsync, not Timer)

* Old path (example): `Timer(16ms)` presentation + `Timer(33ms)` packet
  feeder + 250 ms diagnostics.
* New path: `SchedulerBinding.scheduleFrameCallback` loop. Each vsync pulls
  the decoder-paced frame (`takeVideoFrame`, already paced by Rust
  `PresenterRuntime` against the audio clock) and presents it, then calls
  `scheduleFrame()`. No Dart Timer drives frames.
* Diagnostics stay on a 500 ms `Timer` (single `getDiagnostics()` call —
  never 11 individual getters, never per-frame `setState`).
* Widget listens to presenter `textureId`/`frameSize`/`cpuImage`, not to
  controller value, so controls don't rebuild per frame.

## Texture strategy

* One stable `textureHandle` per controller (random 31-bit default).
* `createTexture` once; `resizeTexture` on resolution change (no
  dispose/create churn).
* Zero-copy first: `presentPixelBuffer` (VideoToolbox BGRA + IOSurface +
  Metal-compat buffers are adopted pointer-swap, no copy).
* Fallback: `updateTextureRgba` today; BGRA-ready branch so the engine BGRA
  cutover is one line (`updateTextureBgra` = row `memcpy`, no swizzle).
* `flushPools()` on `release()` + `didHaveMemoryPressure`; `debugStats()`
  exposed for overlays/tests.

## Network design

* `MediaForgeMedia.network(url, headers)` → controller resolves to the URL
  string → `engine.openFile(path: url)` → FFmpeg `avformat_open_input`
  reads HTTP directly; `avformat_seek_file` becomes Range requests.
* Never fetch in Dart / push via FFI (no `pushVideoPacket` streaming path).
* `isLoopback` helper flags PeerStream-style servers.
* Headers/timeout/retry/HLS variant selection need engine `open_url` with
  an options dict (Rust work item R1 below).

## Gaps → Rust work items

* **R1 — `open_url`: DONE.** `open_url(url, NetworkOptions{headers,
  user_agent, timeout_ms, reconnect})` → FFmpeg dict (`headers`,
  `user_agent`, `rw_timeout`, `reconnect*`, `protocol_whitelist`,
  boosted probe). `bytesRead` counts demuxed container bytes.
* **R2 — tracks: DONE (text subtitles).** `list_streams()` +
  `select_audio_stream` / `select_video_stream` / `select_subtitle_stream`
  (±sidecar `open/close_external_subtitle`, delay, enable, poll).
  Bitmap subtitle rendering still open.
* **R3 — volume: DONE.** Master gain in the cpal callback (`set_volume`),
  distinct from `setMuted` (all) / `setSourceMuted` (source only).
* **R4 — Android HW: decode DONE, device validation PENDING.**
  MediaCodec `hw_device_ctx` + `get_format` + `transfer_to_sw` (NV12) +
  `JNI_OnLoad` registration, mirroring `video_forge`. Presentation still
  uploads frames; Java MediaCodec → SurfaceTexture zero-copy is future.
* **R5 — telemetry: DONE (demuxed-bytes basis).** Decoder label,
  dropped-frame counters, buffered-ahead, read bitrate, cue backlog,
  selected indices. Socket-level bytes not reported.

## Test strategy

* Pure-Dart unit: sources, value, track API, target resolution.
* Contract: localhost Range server (206/Content-Range/exact bytes).
* Engine-backed (manual, needs built natives): open file → play → seek →
  assert `position` advances, `avDriftMs < 500`, no texture churn.
