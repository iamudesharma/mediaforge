## 0.2.0

- **Hybrid playback:** `NativePlaybackController` + `NativeVideoCanvas` — smooth preview via `video_player` (AVPlayer / ExoPlayer). Use for timeline play and scrub preview; keep `MediaRuntime` for frame-accurate texture benchmarks and `VideoProcessor` for thumbnails, export, and effects.
- **Export burn-in:** overlay export forces software decode/encode (libx264/libx265), allocates scaler output frames, and maps clearer FFmpeg errors (fixes generic `Unknown error occurred` on macOS with overlays).
- **Android parity:** `nativePlaybackEngineLabel()` (ExoPlayer HUD); example studio preview menu (Native vs `MediaRuntime` texture / MediaCodec surface); Media Studio manifest permissions for video pick.
- **Android overlay export:** burn-in falls back to `h264_mediacodec` / `hevc_mediacodec` when libx264/libx265 are absent; overlays composite on YUV420P then convert to NV12 before MediaCodec encode (fixes `Generic error in an external library`).
- **Preview:** iPhone Dolby Vision HEVC (`.mov`) uses **software decode** on Apple — avoids broken VideoToolbox seek (`POC` / `videotoolbox_vld` errors). `MediaInfo.hasDolbyVision` from full FFmpeg probe (no fast-probe skip on `.mov`). Scrub uses clean decoder reopen + downscaled `swscale` (~720p) for faster RGBA upload; optional stateless scrub path for HEVC `.mov`.
- **V1.7:** `MediaRuntimeMetrics` + `MediaRuntimePerf` (ROADMAP scenarios I/J/K); example **Preview** tab; studio status timings; `decodeMs` / `uploadMs` wired during scrub.
- Split: native engine moved to `video_forge`; disk cache to `video_forge_cache`.
- Federated plugin: FFI hook lives in `video_forge`.
- **V1.1:** `MediaRuntime`, `VideoTexturePool`, `VideoPreviewSurface`; `VideoProcessor.decodePreviewFrameRgba`; video studio scrub on GPU texture.
- **V1.2:** `FrameQueue`, `PreviewFrame`, `MediaRuntime.scheduleScrub` with queue flush before decode.
- **V1.3:** `PlaybackClock`, `MediaRuntime.play()` / `pause()`; decoder-driven loop (PTS advances timeline); studio play/pause within trim.
- **V1.4:** Apple VideoToolbox preview → `CVPixelBuffer` + `GpuTextureRegistry.presentPixelBuffer` (zero-copy texture); RGBA fallback on failure.
- **V1.5:** `VideoCompositorCanvas` + `VideoOverlayItem` timeline overlays over texture preview; studio demo.
- **V1.6:** Android MediaCodec → `SurfaceTexture` zero-copy preview (`decodePreviewToSurface`); RGBA fallback when source &gt; `previewMaxEdge`.

## 0.1.0

- Monolithic plugin under `rust video/`.
