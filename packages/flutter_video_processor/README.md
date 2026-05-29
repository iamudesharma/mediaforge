# flutter_video_processor

App-facing video SDK: compress, transcode, thumbnails, job queue.

Native engine: [`video_processor_core`](../video_processor_core/). Disk filmstrip cache: [`video_thumbnail_cache`](../video_thumbnail_cache/) (included by default).

## Quick start

```yaml
dependencies:
  flutter_video_processor: ^0.2.0
  path_provider: ^2.1.5
```

```dart
import 'package:flutter_video_processor/flutter_video_processor.dart';

await VideoProcessor.initialize();
final info = await VideoProcessor.getMediaInfo('/path/to/video.mp4');
```

### Native playback preview (recommended for watch / timeline play)

```dart
final player = NativePlaybackController(loopPlayback: false);
await player.open('/path/to/iphone_hevc.mov');
await player.play();
player.pause();
await player.seekTo(const Duration(seconds: 5));

NativeVideoCanvas(
  controller: player,
  overlays: [/* VideoOverlayItem … */],
);
```

Uses platform players (`video_player` → **AVPlayer** on Apple, **ExoPlayer** on Android) for hardware decode, HDR/Dolby Vision, and smooth frame timing. Pair with `VideoProcessor` for thumbnails, frame extraction, and export.

HUD helper: `nativePlaybackEngineLabel()` from `native_playback_platform.dart`.

**Android:** Same Dart API as iOS/macOS. Run Media Studio with `./scripts/run-media-studio-android.sh` (NDK prebuild + `VFP_USE_PREBUILT_JNI=1`). Overlay export requires software encoders (`libx264`/`libx265`) in the FFmpeg build when present; otherwise use export without overlays or rebuild native libs.

### Texture preview (Sprint V1.1 — editing / benchmarks)

```dart
final runtime = MediaRuntime(previewMaxEdge: 720);
await runtime.open('/path/to/video.mp4');
await runtime.seekTo(const Duration(seconds: 5)); // immediate
runtime.scheduleScrub(const Duration(seconds: 12)); // debounced scrub (280 ms)

await runtime.play(); // decoder-clock playback within trim (V1.3)
runtime.pause();

// Preview only:
VideoPreviewSurface(runtime: runtime);

// V1.5 — texture + timeline overlays (Flutter Stack, no Rust compositor):
VideoCompositorCanvas(
  runtime: runtime,
  overlays: [
    VideoOverlayItem.text(
      id: 'caption',
      startMs: 0,
      endMs: 5000,
      anchor: Offset(0.1, 0.9),
      label: 'Hello',
    ),
  ],
);
```

Uses [`rust_gpu_texture`](../rust_gpu_texture/) on macOS / iOS / Android. **Apple:** VideoToolbox → `presentPixelBuffer` for H.264 / HEVC without Dolby Vision. **iPhone Dolby Vision HEVC** (`.mov`, `MediaInfo.hasDolbyVision`): software decode + RGBA texture upload (stable scrub). **Android:** MediaCodec → `SurfaceTexture` when longest edge ≤ `previewMaxEdge`; else RGBA upload. `VFP_DISABLE_HW_PREVIEW=1` forces RGBA for all assets. Design: [VIDEO_MEDIA_RUNTIME.md](../../docs/VIDEO_MEDIA_RUNTIME.md).

| Preview source | Apple path | Notes |
|----------------|------------|--------|
| H.264 / HEVC 8-bit | `texture_pixel_buffer` (GPU) | Zero-copy when VT seek succeeds |
| Dolby Vision HEVC | `texture_rgba` (CPU upload) | Auto-detected; same as thumbnails |
| VT failure mid-session | SW fallback | Rust reopens decoder; Dart retries RGBA |

Full API and platform setup: see [`rust video/README.md`](../../rust%20video/README.md) (legacy doc hub) or run the [example](example/).

**macOS demo** (from repo root):

```bash
./scripts/run-video-macos.sh
```

## Optional: API-only / no disk cache

Depend only on `video_processor_core` for FRB, or `flutter_video_processor` without pulling cache-only APIs — see [VIDEO_PACKAGE_SPLIT.md](../../docs/VIDEO_PACKAGE_SPLIT.md).
