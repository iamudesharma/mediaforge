# video_forge_cache

Optional disk LRU cache for video thumbnail JPEG/WebP files (filmstrip UIs).

Depends on [`video_forge`](../video_forge/) for encode-on-miss.

## Use

```yaml
dependencies:
  video_forge_cache: ^0.2.0
  video_forge_kit: ^0.2.0  # or core only + this package
```

```dart
import 'package:video_forge_cache/video_forge_cache.dart';

final file = await ThumbnailCache.getOrCreate(
  input: '/path/to/video.mp4',
  position: const Duration(seconds: 2),
  width: 320,
);
// Image.file(File(file.path))
```

`video_forge_kit` re-exports this package and keeps `VideoProcessor.thumbnailPathCached` for compatibility.
