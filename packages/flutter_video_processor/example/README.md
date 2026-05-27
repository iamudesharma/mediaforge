# flutter_video_processor example

Demo app for the [`flutter_video_processor`](../packages/flutter_video_processor) plugin.

## Run on a phone (Android / iOS)

### Android (required native build once)

From the **repository root** (USB device connected, `adb devices` shows it):

```bash
./scripts/run-android.sh
```

This builds `libvideo_processor_core.so` for **arm64-v8a**, copies it into the plugin `jniLibs/`, then runs the example.

Prerequisites: Android NDK (via Android Studio SDK Manager), Rust Android target, and FFmpeg for Android.

**Do not** use the placeholder path `<your-ndk-version>`. Either unset a bad value or set the real folder:

```bash
unset ANDROID_NDK_HOME   # if you copied the docs placeholder by mistake
./tools/ffmpeg/android.sh   # once, ~30+ min — auto-detects ~/Library/Android/sdk/ndk/*
```

Or explicitly (your machine has `28.2.13676358`):

```bash
export ANDROID_NDK_HOME="$HOME/Library/Android/sdk/ndk/28.2.13676358"
./tools/ffmpeg/android.sh
```

Or only the device ABI via `package-android.sh` (default). All ABIs: `./tools/release/package-android.sh --all`

### iOS (rebuild native after Rust changes)

```bash
./scripts/run-ios.sh
```

The **Benchmark** tab shows `pipeline_mode` on compress rows (`vt_gpu_scale` / `vt_zero_copy` = P3 active). `flutter run` alone may keep an older `video_processor_core.framework`.

### Picking videos on iOS

**Pick from Photos** uses the photo library (`FileType.video`). On iOS you can also choose **Browse Files** from the sheet (iCloud / On My iPhone). The old `FileType.custom` path only opened the Files app.

### iOS / quick Flutter only (Dart-only edits)

```bash
cd example
flutter pub get
flutter run
```

Or pick a device:

```bash
flutter devices
flutter run -d <device_id>
```

### What the app includes

| Tab | Features |
|-----|----------|
| **Showcase** | **Start here** — product-style demo: why use the package, HTTPS sample, **getMediaInfo**, cached disk filmstrip, trim range + **compressJob** with cancel, export stats, comparison vs OS-only plugins |
| **Status** | **WhatsApp-style** — pick from gallery → **trim & preview** (metadata first, filmstrip, player) → **Post** runs background **WhatsApp** compress (`VideoProcessorQueue`, 2 parallel, trim `startMs`/`endMs`) + demo **Send to chat** |
| **Studio** | [video_trimmer](https://github.com/sbis04/video_trimmer)-style flow using **only** `flutter_video_processor`: load video → cached filmstrip → draggable range → scrub preview → **compress** export (Instagram / WhatsApp / … presets) |
| **Process** | Pick local video, sample network URLs, all **CompressionPreset** values (Instagram, WhatsApp, …), hardware encoder toggle, probe, compress, single/batch thumbnails |
| **Queue** | **VideoProcessorQueue** — enqueue multiple compress jobs (max 2 concurrent) |
| **Benchmark** | **On-device benchmark** — same ops as desktop `vp_bench` (probe, thumb, batch, compress SW/HW); copy results to clipboard |

Outputs on device go to the app **documents** directory (shown under “Output folders” on the Process tab), not the repo `example/output/` folder.

## Run on macOS (desktop)

```bash
./scripts/run-macos.sh
```

## Benchmarks: phone vs desktop

| Where | How |
|-------|-----|
| **Phone / simulator** | Open the app → **Benchmark** tab → select a video on **Process** → **Run full benchmark suite** |
| **Mac / CI** | `./scripts/benchmark.sh` or `bun run tools/benchmark/run.ts --prefer-hardware` |

`vp_bench` is a Rust CLI and does **not** ship inside the Flutter app. The **Benchmark** tab is the mobile equivalent.

For credible comparison with `video_compress`, run the on-device benchmark with **hardware compress** enabled on a physical iPhone or Android device.

## Documentation

[packages/flutter_video_processor/README.md](../packages/flutter_video_processor/README.md)
