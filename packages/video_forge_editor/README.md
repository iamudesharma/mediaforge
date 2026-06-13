# video_forge_editor

CapCut-style Flutter video editor — single-import drop-in widget with timeline, overlays, BGM remix preview, and export.

## Quick start

```dart
import 'package:video_forge_editor/video_forge_editor.dart';

await VideoForgeEditor.ensureInitialized();

VideoForgeEditorWidget(
  config: VideoForgeEditorConfig(
    title: 'Studio',
    initialVideoPath: pickedPath,
    onExport: (result) => debugPrint('Exported: ${result.outputPath}'),
  ),
)
```

## Run the example (macOS)

From repo root — **do not** use plain `flutter run` on first launch; native libs must be built first:

```bash
# One-time: VideoToolbox FFmpeg (recommended)
bash scripts/build-ffmpeg-macos-vt.sh

# Build video_forge + media_forge and run the editor example
bash scripts/run-video-editor-macos.sh
```

Subsequent runs (native already built):

```bash
bash scripts/run-video-editor-macos.sh --no-rebuild
```

The example disables App Sandbox in debug (same as `media_studio`) so FFmpeg dylibs can load from Homebrew or `FFMPEG_DIR`.

## Architecture

| Layer | Package |
|-------|---------|
| Processing (compress, thumbs, burn-in) | `video_forge_kit` |
| Real-time playback + overlay audio mix | `media_forge` |
| Editor UI | `video_forge_editor` (this package) |

`video_forge_kit` remains usable without this package for compress/thumbnail-only apps.

## Native rebuild

After changing Rust in `media_forge` or `video_forge`:

```bash
bash scripts/run-video-editor-macos.sh
```
