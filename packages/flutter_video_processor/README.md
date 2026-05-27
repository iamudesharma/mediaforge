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

### Texture preview (Sprint V1.1)

```dart
final runtime = MediaRuntime(previewMaxEdge: 720);
await runtime.open('/path/to/video.mp4');
await runtime.seekTo(const Duration(seconds: 5));

// In your widget tree:
VideoPreviewSurface(runtime: runtime);
```

Uses [`rust_gpu_texture`](../rust_gpu_texture/) on macOS / iOS / Android; RGBA fallback elsewhere. Design: [VIDEO_MEDIA_RUNTIME.md](../../docs/VIDEO_MEDIA_RUNTIME.md).

Full API and platform setup: see [`rust video/README.md`](../../rust%20video/README.md) (legacy doc hub) or run the [example](example/).

**macOS demo** (from repo root):

```bash
./scripts/run-video-macos.sh
```

## Optional: API-only / no disk cache

Depend only on `video_processor_core` for FRB, or `flutter_video_processor` without pulling cache-only APIs — see [VIDEO_PACKAGE_SPLIT.md](../../docs/VIDEO_PACKAGE_SPLIT.md).
