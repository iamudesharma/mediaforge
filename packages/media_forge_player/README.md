# media_forge_player

Polished Flutter video-player SDK on top of this monorepo's engine:

```
Flutter Player API (this package)
→ media_forge playback engine (FFmpeg demux, HW/SW decode, audio-master clock)
→ FFmpeg demux → HW/SW video decode → audio playback + clock
→ pixel_surface GPU rendering → Flutter Video widget
```

`pixel_surface` is presentation only. `media_forge` is the engine.
This package is the public player (à la `video_player` / `media_kit`).

## Quick start

```dart
final controller = MediaForgePlayerController();
await controller.open(
  MediaForgeMedia.network('http://127.0.0.1:8080/stream', headers: {}),
);
await controller.play();
await controller.seek(const Duration(minutes: 20));
```

```dart
MediaForgeVideo(controller: controller, fit: BoxFit.contain)
```

Sources: `MediaForgeMedia.file(...)`, `.network(...)`, `.asset(...)`.

## Network design (PeerStream)

FFmpeg inside `media_forge` reads HTTP URLs directly, so seeking issues
HTTP Range requests against localhost torrent servers. Dart never fetches
bytes or pushes them over FFI. Custom headers are stored on the source and
logged; header forwarding lands with the engine `open_url` work item below.

## What is reused vs new

Reused (depend, do not copy):

* `media_forge`: `MediaPlaybackEngine`, `PlaybackClock`, `presenter_runtime`
  (audio-master clock), `getDiagnostics`, `probeDecodeCapabilities`,
  VideoToolbox path, `mediaVideoFrameIntoPixelBufferHandoff`.
* `pixel_surface`: `GpuTextureRegistry` (`createTexture`, `presentPixelBuffer`,
  `updateTextureRgba/Bgra`, `resizeTexture`, `flushPools`, `debugStats`),
  `GpuTextureView`.
* `video_forge_editor`: `PlaybackBackend` interface patterns (open/play/pause/
  seek/trim/mute/rate) informed the controller shape.

New in this package:

* `MediaForgeMedia` source abstraction (file/network/asset).
* `MediaForgePlayerController` (`ValueNotifier<MediaForgePlayerValue>`,
  play/pause/stop/seek/rate/volume/mute, track selection, vsync loop,
  500 ms diagnostics, events + diagnostics streams).
* `MediaForgeVideo` fullscreen-friendly widget.
* `MediaForgeTexturePresenter` (stable handle, `resizeTexture` in place,
  zero-copy first, BGRA-ready, pool flush on memory pressure).
* `MediaForgeCapabilities` (probe + fallback flags) and
  `MediaForgeDiagnostics` (drift, FPS, dropped, queue depth, buffered,
  decoder, HW/SW).

## Current gaps (engine work items, tracked in docs/ARCHITECTURE.md)

1. Engine `open_url(url, headers, timeout)` with HTTP options/HLS headers.
2. Stream listing + `select_audio/subtitle_track` in Rust (multi-audio,
   embedded/external subtitles, HLS variants).
3. Master `set_volume` gain in the cpal callback (v1 maps volume→mute).
4. Socket stats (`networkBytesRead`) + buffered-duration from the demuxer.
5. Android MediaCodec→SurfaceTexture zero-copy in the `media_forge` path
   (today: Apple VT zero-copy + RGBA fallback; Android continuous playback
   still uploads frames — port the `video_forge_kit`/`pixel_surface`
   `decodePreviewToSurface` single-frame path to a streaming path).
6. Per-stream decoder labels in diagnostics (v1 infers from capabilities).

See `docs/ARCHITECTURE.md`, `docs/SUPPORTED_FORMATS.md`,
`docs/BENCHMARKS.md`.
