# video_processor_core

Rust `video_processor_core` cdylib + Flutter FRB bindings + FFmpeg native hook.

**No** `VideoProcessor` facade or disk thumbnail cache — use [`flutter_video_processor`](../flutter_video_processor/) or [`video_thumbnail_cache`](../video_thumbnail_cache/).

## Use (FRB directly)

```dart
import 'package:video_processor_core/video_processor_core.dart';

await NativeBindings.ensureInitialized();
final info = await getMediaInfo(path: '/path/to/video.mp4');
```

## Build Rust

```bash
cd ..  # packages/video_processor_core
cargo build --release -p video_processor_core
```

FFmpeg builds: [`tools/ffmpeg`](../../tools/ffmpeg).

See [VIDEO_PACKAGE_SPLIT.md](../../docs/VIDEO_PACKAGE_SPLIT.md).
