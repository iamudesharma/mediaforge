# video_forge

Rust `video_forge` cdylib + Flutter FRB bindings + FFmpeg native hook.

**No** `VideoProcessor` facade or disk thumbnail cache — use [`video_forge_kit`](../video_forge_kit/) or [`video_forge_cache`](../video_forge_cache/).

## Use (FRB directly)

```dart
import 'package:video_forge/video_forge.dart';

await NativeBindings.ensureInitialized();
final info = await getMediaInfo(path: '/path/to/video.mp4');
```

## Build Rust

```bash
cd ..  # packages/video_forge
cargo build --release -p video_forge
```

FFmpeg builds: [`tools/ffmpeg`](../../tools/ffmpeg).

See [VIDEO_PACKAGE_SPLIT.md](../../docs/VIDEO_PACKAGE_SPLIT.md).
