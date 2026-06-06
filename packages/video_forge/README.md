# video_forge

[![pub package](https://img.shields.io/pub/v/video_forge.svg)](https://pub.dev/packages/video_forge)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

> Open-source project maintained by the community. Found a bug or want to contribute? [PRs and issues are welcome](https://github.com/iamudesharma/mediaforge/issues).

High-performance Rust video processing engine for Flutter — hardware-accelerated transcoding, frame-accurate previews, audio mixing, and fast thumbnail generation. Powered by native FFmpeg with platform codecs (MediaCodec, VideoToolbox).

> [!NOTE]
> This is a **low-level engine** — raw FFI bindings to Rust + FFmpeg. Provides hardware-accelerated transcoding, frame-accurate previews, audio mixing, and thumbnail generation.

---

## Platform Support

| Platform | Status |
|---|---|
| Android | Tested (SDK 24+, MediaCodec) |
| iOS | Tested (13.0+, VideoToolbox) |
| macOS | Tested (10.15+, VideoToolbox) |
| Windows | In progress |
| Linux | In progress |
| Web | Not supported |

---

## Quick Start

```dart
import 'package:video_forge/video_forge.dart';

// Call once at app startup
await initialize();

// Probe video metadata
final info = await getMediaInfo(path: '/path/to/video.mp4');
print('${info.width}x${info.height} ${info.durationMs}ms');

// Compress with progress stream
final progress = startCompress(options: CompressOptions(
  inputPath: '/path/to/video.mp4',
  outputPath: '/path/to/output.mp4',
));
await for (final event in progress) {
  print('${event.phase}: ${event.fps} fps');
}

// Extract a thumbnail
final thumbPath = await thumbnail(options: ThumbnailOptions(
  inputPath: '/path/to/video.mp4',
  positionMs: 1500,
  outputPath: '/path/to/thumb.jpg',
));
```

---

## What You Can Do

- **Video transcoding** — Async compression with hardware acceleration (MediaCodec, VideoToolbox). Phase-based progress reporting with FPS and ETA.
- **Metadata probing** — Fast MP4 inspection (mp4parse) with FFmpeg fallback. Dimensions, duration, framerate, codecs, rotation, Dolby Vision markers.
- **Thumbnails & filmstrips** — Frame-accurate single/batch extraction with optimized GOP seek. Output to files or in-memory byte arrays.
- **Frame-accurate previews** — Decode frames to raw RGBA or Apple zero-copy `CVPixelBuffer`. No temp files.
- **Audio mixing** — Mix external audio tracks with source video. Per-track offsets, durations, and volume.
- **Overlay burn-in** — Composite PNG overlays (watermarks, stickers) onto video frames with fade transitions.
- **Playback sessions** — Decoder-driven playback with seek, play/pause, and custom frame-rate ticks.
- **Buffer pool** — Recycled byte vectors to eliminate allocations during scrub sessions.

For the full API, see the [Dart API reference](https://pub.dev/documentation/video_forge/latest/).

---

## Pros & Cons

| Pros | Cons |
|---|---|
| Hardware-accelerated video processing | No web support |
| Async jobs with progress updates | FFmpeg libraries add significant app size |
| Android, iOS, macOS (Windows & Linux in progress) | FFmpeg setup can be involved (especially macOS VT) |
| Frame-accurate previews without temp files | FFmpeg is LGPL — requires license notice in your app |
| Built-in audio mixing for timeline editors | Needs native build toolchain, not pure Dart |
| Fast thumbnail and filmstrip generation | Large binary from bundled video codecs |

---

## App Size

The package includes native Rust code plus external FFmpeg libraries:

| Component | Est. Size |
|---|---|
| Rust engine (transcoding, preview, thumbnails, audio mix) | **~5–8 MB** |
| FFmpeg libraries (libavcodec, libavformat, libavfilter, libswscale) | **~15–30 MB** |
| **Total** | **~20–38 MB** |

FFmpeg is the dominant cost. The Rust engine itself is modest — most of the weight comes from video/audio codec libraries. Android uses App Bundles, so users only download their device's ABI.

---

## Installation

```bash
flutter pub add video_forge
```

**Prerequisites:**

- [Rust toolchain](https://rustup.rs) on your development machine
- **FFmpeg** libraries (`libavcodec`, `libavformat`, `libavfilter`, `libswscale`) on your linker path
- **macOS with VideoToolbox**: Build FFmpeg with VT support
- **Android**: NDK configured in `local.properties`; install Android Rust targets:
  ```bash
  rustup target add aarch64-linux-android armv7-linux-androideabi \
    x86_64-linux-android i686-linux-android
  ```

---

## More Examples

### Batch thumbnails (filmstrip)
```dart
final result = await batchThumbnails(options: BatchThumbnailOptions(
  inputPath: '/path/to/video.mp4',
  positionsMs: [0, 5000, 10000, 15000],
  outputDir: '/tmp/thumbs',
));

// Or in-memory for UI display
final frames = await batchThumbnailBytes(options: BatchThumbnailBytesOptions(
  inputPath: '/path/to/video.mp4',
  positionsMs: [0, 5000, 10000, 15000],
));
```

### Frame-accurate preview decode
```dart
final frame = await decodePreviewFrameRgba(
  inputPath: '/path/to/video.mp4',
  positionMs: BigInt.from(4200),
  maxEdge: 720,
);
// frame.width, frame.height, frame.data (RGBA bytes)
```

### Cancel a running job
```dart
final jobId = /* from startCompress */;
await cancelJob(jobId: jobId);
print('Active jobs: ${await activeJobCount()}');
```

---

## Build & Test

```bash
# Rust unit tests
cd packages/video_forge && cargo test -p video_forge

# Dart analyzer
dart run melos exec --scope=video_forge -- flutter analyze

# Run example app
cd packages/video_forge/example && flutter run -d macos
```

---

## Contributing

This package is part of the [MediaForge monorepo](https://github.com/iamudesharma/mediaforge). Issues and pull requests are welcome on [GitHub](https://github.com/iamudesharma/mediaforge/issues).

---

## Links

- [GitHub Repository](https://github.com/iamudesharma/mediaforge)
- [Issue Tracker](https://github.com/iamudesharma/mediaforge/issues)
