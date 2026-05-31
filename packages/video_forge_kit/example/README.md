# video_forge_kit example

Demo app for the [`video_forge_kit`](../packages/video_forge_kit) plugin.

> [!TIP]
> **Looking for the main unified product demo?**
> We have built a unified product experience combining both the video stack and the image editor in `examples/media_studio`. It showcases a cohesive workflow: import, trim, add text/emoji overlays, edit poster frames, and export. Check it out at [examples/media_studio](../../../examples/media_studio)!

## Run on a phone (Android / iOS)

### Android (required native build once)

From the **repository root** (USB device connected, `adb devices` shows it):

```bash
chmod +x scripts/run-android.sh
./scripts/run-android.sh              # first connected device
./scripts/run-android.sh M2007J17I    # or pass device id
```

This runs **`scripts/package-video-android.sh`** (NDK + FFmpeg → `packages/video_forge/android/src/main/jniLibs`), clears the hook cache, `flutter clean`, then **`flutter run`** with `VFP_USE_PREBUILT_JNI=1`.

If you see **content hash … Dart … different from Rust**, do **not** hot-reload — run this script again (rebuilds a fresh `.so`).

Emulator / all ABIs: `./scripts/run-android.sh --all`

### Preview perf matrix (V1.7)

After loading a video, open the **Preview** tab and tap **Run perf matrix (I, J, K)**. Studio also shows live `scrub_p95` / `fps` in the status line while playing.

Prerequisites: Android NDK (via Android Studio SDK Manager), Rust Android target, and FFmpeg for Android.

**Do not** use the placeholder path `<your-ndk-version>`. Either unset a bad value or set the real folder:

```bash
unset ANDROID_NDK_HOME   # if you copied the docs placeholder by mistake
./tools/ffmpeg/android.sh   # once, ~30+ min (no OpenSSL — file/http only)
```

The default Android FFmpeg build does **not** require OpenSSL on your Mac. To enable `https://` inputs, set `VFP_FFMPEG_OPENSSL=1` and place cross-compiled `libssl.a` / `libcrypto.a` under `tools/ffmpeg/dist/android/<abi>/openssl/` (optional; most demos use local files).

Or explicitly (your machine has `28.2.13676358`):

```bash
export ANDROID_NDK_HOME="$HOME/Library/Android/sdk/ndk/28.2.13676358"
./tools/ffmpeg/android.sh
```

Or only the device ABI: `./scripts/package-video-android.sh` (default). All ABIs: `./scripts/package-video-android.sh --all`

### iOS (rebuild native after Rust changes)

```bash
./scripts/run-ios.sh
```

The **Benchmark** tab shows `pipeline_mode` on compress rows (`vt_gpu_scale` / `vt_zero_copy` = P3 active). `flutter run` alone may keep an older `video_forge.framework`.

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
| **Studio** | [video_trimmer](https://github.com/sbis04/video_trimmer)-style flow using **only** `video_forge_kit`: load video → cached filmstrip → draggable range → scrub preview → **compress** export (Instagram / WhatsApp / … presets) |
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

[packages/video_forge_kit/README.md](../packages/video_forge_kit/README.md)
