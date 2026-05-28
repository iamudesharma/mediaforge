# Media Studio — Unified capabilities example

A new monorepo example app that showcases editing photos (using `rust_image_editor`) and processing/compositing videos (using `flutter_video_processor`) in a single cohesive product story.

## Capabilities Shown

- **Create Hub**: A single landing page to import photos or videos, try sample media, and view "mock social updates".
- **Video Creator Flow**:
  - Ingestion and probing (`getMediaInfo`).
  - Batch-cached timeline thumbnails (`batchThumbnailPathsCached`).
  - Interactive trimming and live preview via `MediaRuntime` + `VideoCompositorCanvas`.
  - Adding overlay texts and emojis.
  - Video compression using quality presets (`compressJob`) with progress and cancellation.
- **Photo Editor Flow**:
  - Full-screen `RustImageEditorWidget` with cropping, rotation, adjustments, filters, drawing, and face beauty operations.
- **Poster Frame Bridge**:
  - Pause a video → extract playhead frame → edit in photo editor → apply as static overlay.

## Project Boundaries

To follow the package architecture:
- Video packages (`flutter_video_processor`) must not depend on image packages (`rust_image_core`).
- The integration is strictly app-layer, utilizing `rust_gpu_texture` for native preview surfaces.
- Text, emoji, and poster-frame overlays are rasterized in Flutter and burned into export via `CompressOptions.burnInOverlays` (Rust CPU composite during encode).

## Building and Running

Ensure that you have completed native builds for both packages first.

### macOS / iOS

1. Run the native macOS/iOS builds from the repository roots for both the video and image engines.
2. Run from this folder:
   ```bash
   flutter run
   ```

### Android

Use the root script to compile both NDK libraries and run:
```bash
./scripts/run-media-studio-android.sh
```
*(Note: First-time Android compile of both engines takes a few minutes.)*
