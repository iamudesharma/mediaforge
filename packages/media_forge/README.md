# media_forge

[pub package](https://pub.dev/packages/media_forge)
[License](LICENSE)

Rust-backed **real-time media playback** for Flutter — FFmpeg demux/decode, cpal audio output with overlay mixing, and optional GPU texture presentation via [`pixel_surface`](https://pub.dev/packages/pixel_surface). One playback clock, one mixed soundtrack, no `video_player` + separate audio player fighting for the device session.

---

## Platform Support

| Platform | Video decode | Audio (cpal) | GPU texture |
| -------- | ------------ | ------------ | ----------- |
| macOS | Yes (SW + VideoToolbox HW) | Yes | Yes via `pixel_surface` |
| iOS | Yes (SW + VideoToolbox HW) | Yes | Yes |
| Android | Yes (software) | Yes | Yes |
| Linux | Yes (software) | Yes | CPU/RGBA fallback possible |
| Windows | Yes (software) | Yes | CPU/RGBA fallback possible |
| Web | No (FFI plugin) | No | No |

**Requires:** Rust toolchain, FFmpeg dev libraries at compile time, and [`pixel_surface`](https://pub.dev/packages/pixel_surface) for GPU display. See [Build requirements](#build-requirements) below.

---

## What You Can Build

| Use case | Key APIs |
| -------- | -------- |
| GPU-texture video player (no `video_player`) | `MediaPlaybackEngine` + `MediaVideoSurface` |
| Timeline / editor preview with trim | `setTrimRange`, `seek`, `getMediaTimeMs` |
| Real-time BGM / voice-over mixing | `addOverlayAudio`, `setOverlayVolume`, `setMuted` |
| A/V sync diagnostics dashboard | `getDiagnostics`, `getAvDriftMs`, `PlaybackDiagnostics` |
| Hardware HEVC/H.264 on Apple | VideoToolbox path (VT-enabled FFmpeg required) |
| Custom decode pipeline experiments | `PacketQueue`, `VideoRuntime`, `AudioRuntime` |

**Not included in this package:** image editing (`image_forge`), video transcode/export (`video_forge` / `video_forge_kit`), or disk cache (`video_forge_cache`).

---

## Architecture

```
Flutter app
    │
    ├── Presentation layer (MediaVideoSurface, MediaPlaybackPresenter, MediaPlaybackDrive)
    │       └── pixel_surface GpuTextureView
    │
    └── flutter_rust_bridge
            └── Rust MediaPlaybackEngine
                    ├── FFmpeg demux / decode (SW + Apple VideoToolbox)
                    ├── PresenterRuntime (~30 fps paced display)
                    └── cpal audio output (source + overlay tracks mixed in real time)
```

---

## Installation

```bash
flutter pub add media_forge pixel_surface
```

You also need a **Rust toolchain** (`rustup`) and **FFmpeg** development libraries linked at native build time. The package compiles its Rust core via a build hook on first `flutter run` / `flutter build`.

---

## Quick Start

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_forge/media_forge.dart';
import 'package:pixel_surface/pixel_surface.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  static const _textureHandle = 1;

  MediaPlaybackEngine? _engine;
  late final MediaPlaybackPresenter _presenter;
  late final MediaPlaybackDrive _drive;
  Timer? _presentationTimer;

  @override
  void initState() {
    super.initState();
    _presenter = MediaPlaybackPresenter(textureHandle: _textureHandle);
    _openAndPlay();
  }

  Future<void> _openAndPlay() async {
    final textureId = await GpuTextureRegistry.createTexture(
      handle: _textureHandle,
      width: 1920,
      height: 1080,
    );
    final engine = await MediaPlaybackEngine.newInstance(
      textureId: textureId!,
      maxQueueSize: BigInt.from(32),
      previewMaxEdge: 1080,
    );
    final drive = MediaPlaybackDrive(engine: engine, presenter: _presenter);

    await engine.openFile(path: '/path/to/video.mp4');
    await engine.start();

    _presentationTimer = Timer.periodic(
      const Duration(milliseconds: 33),
      (_) => drive.presentationTick(),
    );

    setState(() {
      _engine = engine;
      _drive = drive;
    });
  }

  @override
  void dispose() {
    _presentationTimer?.cancel();
    _engine?.stop();
    _presenter.dispose();
    GpuTextureRegistry.disposeTexture(handle: _textureHandle);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: MediaVideoSurface(presenter: _presenter),
        ),
      ),
    );
  }
}
```

---

## Overlay Audio (timeline BGM)

Mix additional audio tracks in real time — no preview-mux round-trip:

```dart
final overlayId = await engine.addOverlayAudio(
  path: '/path/to/music.mp3',
  volume: 0.8,
  timelineStartMs: BigInt.zero,       // when overlay starts on the timeline
  durationMs: BigInt.from(60000),     // how long it plays
  sourceStartMs: BigInt.from(5000),   // offset into the source file
);

await engine.setOverlayVolume(id: overlayId, volume: 0.5);
await engine.removeOverlayAudio(id: overlayId);

// Mutes all audio (source + overlays) while keeping the clock in sync:
await engine.setMuted(muted: true);
```

---

## Trim and Seek

```dart
await engine.setTrimRange(
  startMs: BigInt.from(2000),
  endMs: BigInt.from(30000),
);
await engine.seek(timeMs: BigInt.from(10000));
await engine.setRate(rate: 1.0);
```

Playback position uses the **audio device clock** when audio is active for sample-accurate sync.

---

## Diagnostics

```dart
final drive = MediaPlaybackDrive(engine: engine, presenter: presenter);

// Single FRB call — replaces many individual getters:
final diag = await drive.diagnosticsTick();
print('drift=${diag.avDriftMs}ms VQ=${diag.videoFramesInQueue}');

final healthy = drive.isHealthyPlayback(diag, isPlaying: true);
```

Probe FFmpeg / VideoToolbox at startup:

```dart
final caps = await probeDecodeCapabilities();
print('hevc_videotoolbox=${caps.hevcVideotoolbox}');
```

---

## Public API

### Rust engine (via flutter_rust_bridge)

| Symbol | Role |
| ------ | ---- |
| `RustLib.init()` | Initialize FFI (call once at startup) |
| `MediaPlaybackEngine` | Main playback: open, play/pause/seek, trim, overlays, diagnostics |
| `probeDecodeCapabilities()` | Probe linked FFmpeg decoder availability |
| `ensureFfmpegInitialized()` | One-time FFmpeg init |
| `AudioRuntime` / `VideoRuntime` | Lower-level audio/video pipeline control |
| `PlaybackClock` | Master clock and presented PTS tracking |
| `PacketQueue` | Custom packet queue for pipeline experiments |
| `MediaVideoFrame` / `AudioFrame` | Decoded frame data |
| `DiagnosticsSnapshot` | Full runtime snapshot from Rust |
| `PlaybackState` | `idle`, `playing`, `paused`, `seeking`, `ended` |

### Flutter presentation layer

| Symbol | Role |
| ------ | ---- |
| `MediaVideoSurface` | Widget: GPU texture or CPU fallback display |
| `MediaPlaybackPresenter` | Frames → GPU upload or `presentPixelBuffer` zero-copy |
| `MediaPlaybackDrive` | 33 ms presentation tick + diagnostics helpers |
| `MediaGpuTexturePresenter` | Low-level texture upload via `pixel_surface` |
| `PlaybackDiagnostics` | Dart-friendly diagnostics with `int` fields |
| `MediaPlaybackAcceptance` | Healthy-playback thresholds for dashboards |

---

## Build Requirements

### 1. Rust toolchain

Install [rustup](https://rustup.rs/). For Android, add NDK targets:

```bash
rustup target add aarch64-linux-android armv7-linux-androideabi \
  x86_64-linux-android i686-linux-android
```

The package builds `libmedia_forge` via a native asset hook on `flutter run` / `flutter build`.

### 2. FFmpeg development libraries

Linked at compile time (`avcodec`, `avformat`, `avutil`, `swscale`, `swresample`). Set before building:

```bash
export FFMPEG_DIR="/path/to/ffmpeg/prefix"
export PKG_CONFIG_PATH="$FFMPEG_DIR/lib/pkgconfig"
flutter run
```

### 3. Apple VideoToolbox (macOS / iOS, 4K HEVC)

Homebrew FFmpeg **does not** include `hevc_videotoolbox`. For hardware HEVC decode, use a VideoToolbox-enabled FFmpeg build and point `FFMPEG_DIR` at its prefix.

Without VT-enabled FFmpeg, 4K HEVC falls back to software decode and may trigger catch-up / hard resync.

### 4. pixel_surface

Required dependency for GPU texture display:

```bash
flutter pub add pixel_surface
```

### 5. Full native rebuild after Rust changes

Hot reload does **not** pick up Rust changes. Run `flutter clean` and rebuild after editing `rust/`.

### Environment variables

| Variable | Effect |
| -------- | ------ |
| `FFMPEG_DIR` | FFmpeg install prefix for native link |
| `PKG_CONFIG_PATH` | pkg-config search path for FFmpeg |
| `VFP_DISABLE_HW_DECODE=1` | Force software video decode |
| `MEDIA_DISABLE_VT_ZERO_COPY=1` | Disable CVPixelBuffer zero-copy on Apple |

---

## Example App

The [`example/`](example/) app is a full **Rust Media Runtime Dashboard** — file picker, play/pause/seek, diagnostics, and GPU preview.

```bash
cd example
flutter run -d macos   # or ios, android, linux, windows
```

For operator diagnostics (hardware decode logs, catch-up modes, acceptance checklist), see [`example/README.md`](example/README.md) and [`doc/ACCEPTANCE.md`](doc/ACCEPTANCE.md).

---

## Related Packages

| Package | Role |
| ------- | ---- |
| [`pixel_surface`](https://pub.dev/packages/pixel_surface) | GPU texture bridge (required) |
| [`image_forge`](https://pub.dev/packages/image_forge) | Image processing engine |
| [`video_forge`](https://pub.dev/packages/video_forge) | Video transcode / FFmpeg pipeline |

---

## Contributing

Part of the [MediaForge monorepo](https://github.com/iamudesharma/mediaforge). Issues and pull requests welcome on [GitHub](https://github.com/iamudesharma/mediaforge/issues).

---

## Links

- [GitHub Repository](https://github.com/iamudesharma/mediaforge)
- [Issue Tracker](https://github.com/iamudesharma/mediaforge/issues)
- [pixel_surface on pub.dev](https://pub.dev/packages/pixel_surface)
