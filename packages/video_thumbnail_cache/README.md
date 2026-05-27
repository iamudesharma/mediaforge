# video_thumbnail_cache

Optional disk LRU cache for video thumbnail JPEG/WebP files (filmstrip UIs).

Depends on [`video_processor_core`](../video_processor_core/) for encode-on-miss.

## Use

```yaml
dependencies:
  video_thumbnail_cache: ^0.2.0
  flutter_video_processor: ^0.2.0  # or core only + this package
```

```dart
import 'package:video_thumbnail_cache/video_thumbnail_cache.dart';

final file = await ThumbnailCache.getOrCreate(
  input: '/path/to/video.mp4',
  position: const Duration(seconds: 2),
  width: 320,
);
// Image.file(File(file.path))
```

`flutter_video_processor` re-exports this package and keeps `VideoProcessor.thumbnailPathCached` for compatibility.
