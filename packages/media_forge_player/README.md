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

## Player UI (`player_ui/`)

A complete VLC-grade player experience that consumes only the public
controller/value/diagnostics APIs:

```dart
MediaPlayerScreen(
  controller: controller,
  title: 'Big Buck Bunny',
  onPickExternalSubtitle: pickSrtFile, // app file picker, optional
  torrentStats: peerStreamStats,        // ValueListenable, optional
  onPrevious: playPrevious,             // playlist hooks, optional
  onNext: playNext,
  onToggleFullscreen: toggleFullscreen,
  onPictureInPicture: enterPip,
)
```

* Immersive auto-hiding chrome (top bar + timeline + transport).
* Center play/pause/±10s, double-tap seek, tap to show/hide, horizontal
  drag scrub with preview, right-side vertical drag volume, mouse-wheel
  volume, right-click context menu (desktop).
* VLC/mpv shortcuts: Space, ←/→/J/L seek, ↑/↓ volume, M mute, F
  fullscreen, S subtitles toggle, A audio panel, +/− speed, Home/End,
  Esc.
* Settings (bottom sheet / side panel): speed presets, repeat, fit
  (fit/fill/stretch/1:1), display rotation, A/V drift readout, full
  audio-track list with metadata, subtitle tracks + delay + appearance
  (size/bold/background/position), detected video info.
* Media information panel: source, video/audio/subtitle details,
  playback stats (FPS, dropped, queues, buffered, drift, bytes,
  bitrate, render path) plus an optional app-provided swarm section.
* Streaming states: loading, buffering/seeking spinners, error card
  with retry, end-of-stream replay.

Every control maps to a real engine capability. Deliberately absent
(no engine support): audio delay, brightness, cast, container/chapter/
thumbnail metadata (chapters + thumbnails are optional app-injected
hooks instead), HDR/pixel-format metadata.

## Network design (PeerStream)

FFmpeg inside `media_forge` reads HTTP URLs directly via `openUrl` with
`NetworkOptions` (headers, user-agent, timeout, reconnect, HLS-friendly
protocol whitelist), so seeking issues HTTP Range requests against
localhost torrent servers. Dart never fetches bytes or pushes them over
FFI.

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
* `video_forge`: MediaCodec `hw_device_ctx` + `get_format` + `JNI_OnLoad`
  pattern informed the Android HW path in `media_forge`.

New in the engine (`media_forge`, this branch):

* `openUrl(url, NetworkOptions)` — headers, user-agent, timeout, reconnect,
  redirect/HLS-friendly options; direct FFmpeg reads (Range preserved).
* `listStreams()` — video/audio/subtitle table (codec, language, title,
  bitrate, dimensions, channels/rate, default/forced).
* `selectAudioStream` / `selectVideoStream` — live switching via params +
  decoder epoch + re-seek through the normal Flush machinery.
* Embedded subtitle worker (text/ASS → cues, bitmap timing only) +
  `selectSubtitleStream(-1 = off)`, `setSubtitleDelayMs`,
  `setSubtitlesEnabled`, `pollSubtitleText`.
* `openExternalSubtitle` / `closeExternalSubtitle` sidecar sessions.
* Engine master `setVolume`/`getVolume` gain in the cpal mixer.
* Android MediaCodec `hw_device_ctx` decode (H.264/HEVC/VP9/AV1) with
  transfer-to-SW presentation + `av_jni_set_java_vm` registration.
* Extended `DiagnosticsSnapshot`: bytes read, read bitrate, buffered
  duration, dropped frames, active decoder + HW flag, cue backlog,
  selected indices.

New in this package:

* `MediaForgeMedia` source abstraction (file/network/asset, timeout,
  reconnect, user-agent).
* `MediaForgePlayerController` (`ValueNotifier<MediaForgePlayerValue>`,
  play/pause/stop/seek/rate/volume/mute, live track + subtitle APIs,
  vsync loop, 500 ms diagnostics, events + diagnostics streams).
* `MediaForgeVideo` fullscreen-friendly widget with caption overlay.
* `MediaForgeTexturePresenter` (stable handle, `resizeTexture` in place,
  zero-copy first, BGRA-ready, pool flush on memory pressure).
* `MediaForgeCapabilities` (probe + fallback flags) and
  `MediaForgeDiagnostics` (drift, FPS, dropped, queue depth, buffered,
  decoder, HW/SW, stream bytes).

## Remaining gaps (honest)

1. Android MediaCodec path is compiled in with soft SW fallback but needs
   on-device validation (no Android CI device in this environment).
2. Bitmap subtitles (dvd/vobsub, pgssub) report timing with empty text —
   no bitmap rendering yet.
3. `bytesRead` counts demuxed container bytes, not socket bytes; per-host
   bandwidth accounting is not reported.
4. True zero-copy Android presentation (Java MediaCodec → SurfaceTexture)
   is future work; the current path uploads decoded frames.
5. Benchmark numbers are not claimed — see `docs/BENCHMARKS.md`.

See `docs/ARCHITECTURE.md`, `docs/SUPPORTED_FORMATS.md`,
`docs/BENCHMARKS.md`.
