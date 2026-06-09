# media_forge example

Dashboard for demux → decode → queue → audio clock → GPU texture preview.

## Phase 0 — verify hardware decode (required once per native change)

**Do not hot-reload** after Rust changes. Run a full native rebuild:

```bash
# from repo root
bash scripts/run-rust-media-macos.sh
```

Or manually:

```bash
cd packages/media_forge
flutter_rust_bridge_codegen generate
cd rust && cargo build --release
cd ../example && flutter clean && flutter run -d macos
```

### Console checklist

| Log | Meaning |
|-----|---------|
| `[Phase0] ... hevc_videotoolbox=true ready_for_hevc_hw=true` | Linked FFmpeg has VideoToolbox HEVC |
| `[Phase0] hevc_videotoolbox missing...` | Rebuild with `FFMPEG_DIR` (see below) — 4K will lag audio |
| `[VideoDecoder] Hardware decode (VideoToolbox): ...` | HW path active |
| `[VideoDecoder] Software decoder: 3840x2160 -> ...` | SW path — may need `[HardResync]` on 4K |
| `[PresenterRuntime] presented pts=... clock=...` | Paced ~30 fps display (Phase 2) |
| `[HardResync] drift=... → seek demuxer` | Phase 1: demuxer rewound to audio clock |
| `[Status] drift=...ms VQ: N/32` | `drift < 500` and `N > 0` during play = healthy |

### Phase 1 — hard resync

When **audio** leads **presented** video by more than **2s** while playing, the engine seeks the demuxer to the audio clock (cooldown 3s). Fixes stuck catch-up when the demuxer prefilled to EOF but decode could not keep up.

### Phase 2 — PresenterRuntime

A Rust thread presents at most one frame every **33ms** (~30 fps). Dart `takeVideoFrame()` reads the paced display frame instead of draining the decode queue every UI tick (reduces bursts/jitter).

### Phase 3 — decode catch-up

| Lag (audio − decoded) | Behavior |
|----------------------|----------|
| > 500 ms | Skip non-keyframes (`[CatchUp] mode=skip-non-key`) |
| > 1500 ms | Keyframes only |
| > 2000 ms | Hard resync (demuxer seek) |

After **seek / hard resync**, decoders and scalers are **reopened** (fixes `Scaler run error: Input changed` and empty `VQ` after flush).

### Phase 4 — Dart presentation hot path

The example uses `MediaVideoSurface` + `MediaPlaybackPresenter` from the package (not `decodeImageFromPixels` / per-frame `setState`):

- Presentation timer: 33ms → `MediaPlaybackDrive.presentationTick()`
- Diagnostics timer: 250ms → queue stats + logs

Reuse in apps:

```dart
final presenter = MediaPlaybackPresenter(textureHandle: handle);
final drive = MediaPlaybackDrive(engine: engine, presenter: presenter);
// ...
MediaVideoSurface(presenter: presenter)
```

### Phase 5 — tests and acceptance

```bash
cd packages/media_forge/rust && cargo test
cd packages/media_forge && flutter test
```

See `../doc/ACCEPTANCE.md` for the manual macOS checklist.

### FFmpeg with VideoToolbox (required for iPhone 4K HEVC)

Homebrew FFmpeg **does not** include `hevc_videotoolbox` decoders. Build once:

```bash
# from repo root — takes ~30–60 min
bash scripts/build-ffmpeg-macos-vt.sh
bash scripts/run-rust-media-macos.sh
```

Install lands in **`~/.cache/rust_image/ffmpeg-macos-vt`** (no spaces — required because FFmpeg breaks on paths like `Gym app/...`).

Or set paths manually (one command per line — no inline `#` comments):

```bash
export FFMPEG_DIR="${HOME}/.cache/rust_image/ffmpeg-macos-vt"
export PKG_CONFIG_PATH="$FFMPEG_DIR/lib/pkgconfig"
cd packages/media_forge/example
flutter clean && flutter run -d macos
```

Disable HW for A/B test: `VFP_DISABLE_HW_DECODE=1 flutter run -d macos`
