# video_forge

[![pub package](https://img.shields.io/pub/v/video_forge.svg)](https://pub.dev/packages/video_forge)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20iOS%20%7C%20macOS%20%7C%20Windows%20%7C%20Linux-green.svg)](#platform-matrix)

High-performance Rust video processing and transcoding engine for Flutter, powered by **flutter_rust_bridge** (FRB) v2 and native **FFmpeg**. This package houses the core pipeline interfaces for video compression, frame-accurate previews, audio-track overlays, watermark burn-in, and fast thumbnail generation.

> [!NOTE]
> This is a **low-level engine** package providing native Rust FFI bindings and raw pipeline access. It does **not** include the high-level disk cache or the `VideoProcessor` facade. For the standard developer-friendly SDK, check out [`video_forge_kit`](../video_forge_kit/) and [`video_forge_cache`](../video_forge_cache/).

---

## Platform Matrix

| Platform | Support | Hardware Accel | Notes |
|---|---|---|---|
| **Android** | Yes | Yes (MediaCodec) | Requires minSdk **24+**, NDK, and FFmpeg binary |
| **iOS** | Yes | Yes (VideoToolbox) | Requires iOS **13+**, linked `video_forge.framework` |
| **macOS** | Yes | Yes (VideoToolbox) | Requires macOS **10.15+**, VT-capable FFmpeg build |
| **Linux** | Yes | Optional | Standard CPU transcoding via FFmpeg |
| **Windows** | Yes | Optional | DirectX 12/DirectShow/NVENC options |
| **Web** | No | — | Native FFmpeg linkage and threading not supported |

---

## Key Features

- **Metadata Probing**: Lightning-fast video inspection using an optimized `mp4parse` path (with FFmpeg fallback).
- **Asynchronous Compression**: Spawns Tokio blocking tasks for parallel transcoding, reporting fine-grained phase progress (Probing, Decoding, Encoding, Muxing) and FPS/ETA statistics back to Dart streams.
- **Overlay Burn-in**: Blends and composites raster overlay PNGs (e.g. stickers, watermarks, text boxes) onto decoded video frames at specific intervals with optional fade-in/fade-out transitions.
- **Audio mixing & export**: Mixes external timeline audio tracks (`AudioTrackInput`) with the source video's audio, supporting custom offsets, durations, and per-track volume controls.
- **Segmented GOP Thumbnailing**: Frame-accurate batch thumbnail extraction (filesystem output or in-memory byte arrays) with optimized keyframe seek heuristics (scrubber/filmstrip generation).
- **Frame-Accurate Previews**: Decodes preview frames directly to raw RGBA or Apple zero-copy `CVPixelBuffer` textures without writing temporary files to disk.
- **Decoder-Driven Playback Clock**: Supports playback sessions (`VideoPreviewSession`) driven by custom frame rate tick systems rather than generic media clocks.
- **Buffer Pool Allocator**: Recycles raw preview byte vectors to eliminate memory allocations in interactive scrub loops.

---

## API Reference

### 1. App Initialization & Controls

*   `initialize()` / `init_app()`: Initializes native loggers and verifies FFmpeg linkage.
*   `active_job_count()`: Returns the number of currently executing asynchronous compression pipelines.
*   `cancel_job(jobId)`: Forces cancellation of a running background job.
*   `cleanup_job(jobId)`: Clears completed job stats and deallocates records from the registry.

### 2. Media Metadata & Network Prefetch

*   `get_media_info(path)`: Probe video parameters (dimensions, duration, framerate, rotation, bitrates, Dolby Vision markers, audio/video codecs).
*   `prefetch_remote_input(url, destDir)`: Stream-copies a remote URL to a local cache directory to prevent redundant network connections during scrub sessions.

### 3. Video Transcoding & Compression

*   `start_compress(options, progressSink)`: Starts background compression and returns a unique `jobId`. Emits progress events to Dart.
*   `wait_for_job(jobId)`: Await completion of compression pipelines (returns file size, duration, used hardware accelerator, encoder names, and pipeline mode).

### 4. Thumbnail & Filmstrip Extraction

*   `thumbnail(options)` / `thumbnail_bytes(options)`: Extracts a single frame at `positionMs` as a file or raw bytes.
*   `batch_thumbnails(options)` / `batch_thumbnail_bytes(options)`: Frame-accurately extracts a sequence of timestamps in a single demux pass.

### 5. Interactive Decoders (`VideoPreviewSession`)

A preview session allows scrubbing and playback of video frames directly:
*   `VideoPreviewSession.create(inputPath, maxEdge, preferHw)`: Instantiates a preview session decoder.
*   `next_frame_rgba()` / `next_frame_pixel_buffer()`: Read the next decoded frame.
*   `seek_and_decode_rgba(positionMs)` / `seek_and_decode_pixel_buffer(positionMs)`: Seek and read frame.
*   `start_playback(rate, progressSink)`: Starts streaming playback frames at the requested playback rate.
*   `pause_playback()`: Pauses playback.
*   `set_preview_max_edge(maxEdge)`: Dynamically updates the preview scale bounding box.
*   `close()`: Releases native structures.

### 6. Zero-Allocation Pool

*   `buffer_pool_acquire(minCapacity)` / `buffer_pool_release(buf)` / `buffer_pool_stats()`: Reuses byte arrays for preview frames.

---

## Requirements & Prerequisites

### Build Requirements
- **Rust Toolchain**: [rustup](https://rustup.rs).
- **FFmpeg**: Libraries (`libavcodec`, `libavformat`, `libavfilter`, `libswscale`, etc.) must be installed and visible on your linker path.
  - **macOS (VideoToolbox Accel)**: Requires FFmpeg compiled with VT support (refer to [`scripts/build-ffmpeg-macos-vt.sh`](../../scripts/build-ffmpeg-macos-vt.sh)).
  - **Android (NDK)**: Cross-compiles for Android targets (configured via `local.properties`).

---

## How to Run, Build & Test

### 1. Run Unit/Integration Tests
Verify your FFmpeg linkage and GOP seek code by running:
```bash
cd packages/video_forge
cargo test -p video_forge
```

### 2. Run Dart Analyzer
Check FFI interface bindings for compiler issues:
```bash
dart run melos exec --scope=video_forge -- flutter analyze
```

### 3. Run Sample App
Run the basic FFI probe and transcode demo:
```bash
cd packages/video_forge/example
flutter run -d macos  # or android / ios
```

---

## Future Roadmap

- **Sprint 20: Video Clips & Audio Timeline Editors**
  - Enhanced multi-track timeline split/merge APIs.
  - Real-time CPU/GPU audio mixer integration inside the preview player session.
- **Sprint V1: Video Media Runtime & Texture Preview**
  - **Android Zero-Copy Preview**: Implement zero-copy `SurfaceTexture` rendering using `MediaCodec` direct decoding for resolutions up to 4K.
  - **Scrub Coalescing**: Scrub frame-skipping optimizations to bound preview decoding queues.
  - **Render Graph Integration**: Pluggable render filters (vignette, presets) running directly on the decoded preview texture.

---

## Known Issues & Cleanups

Keep the following items in mind when working on `video_forge`:

1.  **Unused/Dead Code Warnings**:
    *   Unused helper functions inside `src/pipeline/thumbnail.rs` (`downscale_rgb24`, `map_fir_buffer_err`, `map_resize_err`), `src/pipeline/audio_mix.rs` (unused mutability warnings), and `src/ffmpeg/vt_pipeline.rs` (`K_CV_NV12_BIPLANAR_VIDEO`) should be cleaned up.
2.  **Telemetry Unused Fields**:
    *   `started_at` in `JobRecord` (`src/jobs/registry.rs`) and `clip_start_ms` in `VideoTranscoder` (`src/pipeline/transcode.rs`) are defined but never read.
3.  **Rustc cfg checks**:
    *   Attribute macros generate `unexpected cfg condition name: frb_expand` warnings due to updated rustc `check-cfg` rules. These can be safely ignored or resolved by updating compiler rules in `Cargo.toml`.
