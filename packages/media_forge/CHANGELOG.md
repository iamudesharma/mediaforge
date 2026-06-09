## 0.1.0

- Initial pub.dev release
- `MediaPlaybackEngine`: FFmpeg demux/decode, cpal audio output, real-time overlay mixing, trim/seek
- Presentation layer: `MediaVideoSurface`, `MediaPlaybackPresenter`, `MediaPlaybackDrive`
- Apple VideoToolbox hardware decode path with CVPixelBuffer zero-copy presentation
- Platforms: Android, iOS, macOS, Linux, Windows (FFI plugin)
