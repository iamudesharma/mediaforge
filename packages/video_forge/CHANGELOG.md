## 1.0.0

- Initial pub.dev release of `video_forge` — high-performance Rust video processing engine for Flutter powered by FFmpeg.
- Hardware-accelerated transcoding (`CompressOptions` with platform codecs: MediaCodec on Android, VideoToolbox on iOS/macOS), async progress reporting with `ProgressEvent` (phase, fps, ETA).
- Metadata probing: fast MP4 inspection with FFmpeg fallback — dimensions, duration, framerate, codecs, rotation, Dolby Vision markers.
- Thumbnails: single (`thumbnail`) and batch filmstrips (`batchThumbnails` / `batchThumbnailBytes`) with optimized GOP seek; two-tier seek for non-keyframes.
- Frame-accurate previews: `decodePreviewFrameRgba` for raw RGBA, `decodePreviewFramePixelBuffer` for Apple zero-copy `CVPixelBuffer`. No temp files.
- Audio mixing: mix external audio tracks with source video — per-track offsets, durations, and volume.
- Overlay burn-in: composite PNG overlays (watermarks, stickers) onto video frames with fade transitions.
- Playback sessions: decoder-driven playback with seek, play/pause, and custom frame-rate ticks.
- Demuxer/decoder LRU cache: reuses `AVFormatContext` and decoder for repeated `thumbnail` / `batchThumbnails` / `decodePreviewFrameRgba` calls (default 4 entries, 30 s idle TTL, ~256 MB working-set cap). Disable via `setDecoderCacheConfig`, flush via `clearDecoderCache`.
- Output container profiles: `OutputProfile { ProgressiveMp4, FragmentedMp4, Hls }` enum with `effective_output_profile` helper.
- Async remote-input prefetch: `startPrefetchRemoteInput` with `waitForJob` / `cancelJob`. Improved HTTP options (`seekable=1`, `tcp_nodelay=1`, `send_buffer_size=65536`, `listen_timeout=10s`).
- Buffer pool: `bufferPoolAcquire` / `bufferPoolRelease` and token-based `bufferPoolAcquireWithToken` / `bufferPoolReleaseByToken` for zero-allocation render loops. Dart `ReleaseToken` finalizer returns the buffer to the pool on GC.
- Comprehensive error type `VideoForgeError` with 11 variants (`invalidInput`, `fileNotFound`, `unsupportedCodec`, `jobNotFound`, `cancelled`, `ioError`, `ffmpegError`, `queueFull`, `internal`, `cooldownActive`, `recoveryBudgetExhausted`).
- Zero Flutter-package dependencies. Native libraries linked at build time via `flutter_rust_bridge` and FFmpeg.

### Platform support
- Android (SDK 24+, MediaCodec HW encode)
- iOS (13.0+, VideoToolbox HW encode/decode)
- macOS (10.15+, VideoToolbox HW encode/decode)
- Windows / Linux: in progress
- Web: not supported
