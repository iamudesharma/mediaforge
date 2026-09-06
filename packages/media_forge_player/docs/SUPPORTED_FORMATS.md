# Supported codecs / containers / platforms

Engines: FFmpeg demux + decode inside `media_forge`; presentation via
`pixel_surface`. This table describes v1 reality, not aspirations.

## Containers (FFmpeg demux — all via `openFile(path-or-URL)`)

| Container | File | HTTP(S) + Range | HLS (`m3u8`) |
| --- | --- | --- | --- |
| MP4 / MOV / M4V | ✅ (boosted probe) | ✅ FFmpeg reads URL directly | ➖ relayed to FFmpeg; needs R1 verification |
| MKV | ✅ | ✅ | n/a |
| WebM | ✅ | ✅ | n/a |
| Others FFmpeg supports | ✅ best-effort | ✅ best-effort | ➖ unverified |

## Video codecs

| Codec | macOS | iOS | Android | Fallback |
| --- | --- | --- | --- | --- |
| H.264 | ✅ VideoToolbox (`h264_videotoolbox`, zero-copy adopt) | ✅ VideoToolbox | ➖ SW today; MediaCodec streaming path = R4 | SW FFmpeg RGBA |
| HEVC/H.265 | ✅ VT when `readyForHevcHw`, else SW | ✅ VT where device allows | ➖ SW today; R4 | SW FFmpeg RGBA |
| AV1 | ➖ SW | ➖ SW | ➖ SW | SW FFmpeg RGBA |
| VP9 | ➖ SW | ➖ SW | ➖ SW | SW FFmpeg RGBA |

Probe with `MediaForgeCapabilities.probe()`; kill-switches
`VFP_DISABLE_HW_DECODE=1`, `MEDIA_DISABLE_VT_ZERO_COPY=1` are honoured.

## Audio / subtitles

* Audio decode: best-stream selection (AAC/MP3/FLAC/Opus/Vorbis/PCM
  preferred, else first audio) → cpal mix, audio-master clock.
* Multiple audio tracks: API exists (`audioTracks`, `selectAudioTrack`);
  engine switching needs R2.
* Subtitles: API exists (`subtitleTracks`, `selectSubtitleTrack`,
  `addExternalSubtitle`); rendering needs R2.
* Volume: `setVolume` retained; v1 maps to mute switches (R3 adds gain).

## Platforms

| Platform | Status |
| --- | --- |
| macOS | ✅ primary (VT zero-copy + RGBA fallback) |
| iOS | ✅ (VT path; device-dependent HEVC) |
| Android | ✅ file + HTTP via SW/RGBA; MediaCodec zero-copy = R4 |
| Windows / Linux | 🔜 API is platform-neutral; engine FFI plugin already declares both — needs native FFmpeg/cpal validation |
| Web | ❌ no FFI; out of scope for v1 |
