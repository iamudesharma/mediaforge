## 0.2.0

- **V1.7:** `MediaRuntimeMetrics` + `MediaRuntimePerf` (ROADMAP scenarios I/J/K); example **Preview** tab; studio status timings.
- Split: native engine moved to `video_processor_core`; disk cache to `video_thumbnail_cache`.
- Federated plugin: FFI hook lives in `video_processor_core`.
- **V1.1:** `MediaRuntime`, `VideoTexturePool`, `VideoPreviewSurface`; `VideoProcessor.decodePreviewFrameRgba`; video studio scrub on GPU texture.
- **V1.2:** `FrameQueue`, `PreviewFrame`, `MediaRuntime.scheduleScrub` with queue flush before decode.
- **V1.3:** `PlaybackClock`, `MediaRuntime.play()` / `pause()`; decoder-driven loop (PTS advances timeline); studio play/pause within trim.
- **V1.4:** Apple VideoToolbox preview → `CVPixelBuffer` + `GpuTextureRegistry.presentPixelBuffer` (zero-copy texture); RGBA fallback on failure.
- **V1.5:** `VideoCompositorCanvas` + `VideoOverlayItem` timeline overlays over texture preview; studio demo.
- **V1.6:** Android MediaCodec → `SurfaceTexture` zero-copy preview (`decodePreviewToSurface`); RGBA fallback when source &gt; `previewMaxEdge`.

## 0.1.0

- Monolithic plugin under `rust video/`.
