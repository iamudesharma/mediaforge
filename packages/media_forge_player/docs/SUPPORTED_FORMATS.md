# Supported codecs / containers / platforms

Engines: FFmpeg demux + decode inside `media_forge`; presentation via
`pixel_surface`. This table describes v1 reality, not aspirations.

## Containers (FFmpeg demux — all via `openFile(path-or-URL)`)

| Container | File | HTTP(S) + Range | HLS (`m3u8`) |
| --- | --- | --- | --- |
| MP4 / MOV / M4V | ✅ (boosted probe) | ✅ `openUrl` + headers/timeout/reconnect | ➖ options plumbed; playback verified per-fixture, not claimed here |
| MKV | ✅ | ✅ | n/a |
| WebM | ✅ | ✅ | n/a |
| Others FFmpeg supports | ✅ best-effort | ✅ best-effort | ➖ unverified |

## Video codecs

| Codec | macOS | iOS | Android | Fallback |
| --- | --- | --- | --- | --- |
| H.264 | ✅ VideoToolbox (`h264-videotoolbox`, zero-copy adopt) | ✅ VideoToolbox | ✅ MediaCodec `hw_device_ctx` (device validation pending) | SW FFmpeg RGBA |
| HEVC/H.265 | ✅ VT when `readyForHevcHw`, else SW | ✅ VT where device allows | ✅ MediaCodec `hw_device_ctx` (device validation pending) | SW FFmpeg RGBA |
| AV1 | ➖ SW | ➖ SW | ✅ MediaCodec attempt, SW fallback | SW FFmpeg RGBA |
| VP9 | ➖ SW | ➖ SW | ✅ MediaCodec attempt, SW fallback | SW FFmpeg RGBA |

Probe with `MediaForgeCapabilities.probe()`; kill-switch
`VFP_DISABLE_HW_DECODE=1` is honoured. The active pipeline is reported
per-session as `activeVideoDecoder` (e.g. `hevc-videotoolbox`) with
`hwDecodeActive`.

## Audio / subtitles

* Audio decode: best-stream selection (AAC/MP3/FLAC/Opus/Vorbis/PCM
  preferred, else first audio) → cpal mix, audio-master clock.
* Multiple audio tracks: `listStreams` + live `selectAudioStream`
  (decoder reopen + re-seek resync).
* Multiple video tracks: `selectVideoStream` (pipeline reopen on Flush).
* Subtitles: embedded text/ASS decode → cue queue → `pollSubtitleText`
  (renders in `MediaForgeVideo` caption overlay); sidecar files/URLs via
  `openExternalSubtitle`; `setSubtitleDelayMs`, `setSubtitlesEnabled`.
  Bitmap subtitles (dvd/vobsub, pgssub) report timing with empty text.
* Volume: engine-side master gain (`setVolume`) + `setMuted` (all) +
  `setSourceMuted` (source only) + per-overlay volume.

## Platforms

| Platform | Status |
| --- | --- |
| macOS | ✅ primary (VT zero-copy + RGBA fallback) |
| iOS | ✅ (VT path; device-dependent HEVC) |
| Android | ✅ file + HTTP; MediaCodec HW decode compiled in with SW fallback (on-device validation pending) |
| Windows / Linux | 🔜 API is platform-neutral; engine FFI plugin already declares both — needs native FFmpeg/cpal validation |
| Web | ❌ no FFI; out of scope for v1 |
