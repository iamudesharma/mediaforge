## Unreleased

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
