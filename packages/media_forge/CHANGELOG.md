## Unreleased

Subtitle fixes (sidecar files and text tracks were silent):

* Real sidecar subtitles: the static FFmpeg build now enables the `srt`,
  `webvtt` and `ass` **demuxers** (only their decoders were enabled, so a
  `.srt`/`.vtt`/`.ass` file could never be opened) and the build script fails
  fast if any of them goes missing again.
* Cues are no longer dropped in the external session: the decoded display
  window is read before `avsubtitle_free` (which memsets it, yielding `0..0`),
  and subtitle decoder contexts now carry the stream's packet time base so
  libavcodec derives `end_display_time` from the packet duration — without it
  every text cue (srt/webvtt/mov_text) was discarded as degenerate. Both
  external and embedded workers go through one `take_subtitle` helper.
* Captions show the dialogue text only: text decoders (and the Matroska ASS
  path) deliver a full `readorder,layer,style,…` payload in the ASS rect, so
  `ass_rect_text` strips the leading fields instead of rendering them.

GPU video enhancement API (experimental, additive):

* `MediaPlaybackEngine.setVideoEnhancementMode` / `videoEnhancementStatus` /
  `videoEnhancementCapabilities` / `setVideoEnhancementViewport` /
  `setVideoEnhancementMaxOutputEdge` / `enhancePixelBuffer`
  (`PixelBufferHandoff` in and out). The decoded frame's `+1` retain is
  consumed on success, so the caller presents the returned surface instead.
* New `VideoEnhancementMode`, `VideoEnhancementCapabilities` and
  `VideoEnhancementStatus` bridge types. The GPU device is created lazily, so
  engines that never enable enhancement never touch the GPU.
* Backed by `pixel_surface::enhance` (Apple Metal via wgpu). Playback is
  unaffected when the device cannot run it.

- Production hardening: byte/duration packet budgets (video 16 MiB/5 s, audio
  4 MiB/5 s, subtitles small), decoded-frame caps (HW 3 / SW 2), frame-ready
  presenter pump (Condvar, no 60/120 Hz polling when idle, parked while
  paused/suspended/disposed), split drop counters (overflow/catch-up/stale),
  fast initial probe + single fallback retry with probe timing, cooperative
  FFmpeg cancellation tied to generation/disposal, suspend/resume, exact
  rendering-path reporting (`videotoolbox_iosurface_zero_copy` only when
  verified, `android_bitmap_upload` until surface path is device-proven),
  native-resolution preservation (8192 ceiling, no auto-reduction under load).
- Build reproducibility (§17): hook strips Homebrew from PKG_CONFIG_PATH,
  FFmpeg script isolates configure from Homebrew + `--disable-xlib`,
  hermeticity verification, pinned FRB 2.13.0 / ffmpeg-next 8.1.0.
- iOS 15 compatible (pixel_surface audit, no action needed).

## 0.1.0

- Initial pub.dev release
- `MediaPlaybackEngine`: FFmpeg demux/decode, cpal audio output, real-time overlay mixing, trim/seek
- Presentation layer: `MediaVideoSurface`, `MediaPlaybackPresenter`, `MediaPlaybackDrive`
- Apple VideoToolbox hardware decode path with CVPixelBuffer zero-copy presentation
- Platforms: Android, iOS, macOS, Linux, Windows (FFI plugin)
