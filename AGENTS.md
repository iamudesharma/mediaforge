# AGENTS.md

Instructions for AI agents working in this repository.

## Git workflow (features → PR)

New feature work (not read-only questions, not a one-line scoped fix):

1. Branch off `main` first: `{type}/{feature-name}` in kebab-case (`feat/`, `fix/`, `refactor/`, `docs/`, `chore/`). Example: `feat/video-forge-editor`.
2. Keep all work on that branch. Do not commit unless the user asks; then commit on the feature branch.
3. Push (`git push -u origin HEAD`) and open a PR against `main` when asked or when tested.

Skip branching for read-only exploration, work already on a feature branch, or when the user names a branch.

## Monorepo layout

- Dart workspace managed by `melos` (members listed in root `pubspec.yaml` `workspace:` — source of truth, includes `media_forge_player`, `benchmark`, `examples/`).
- After cloning: `dart pub get && dart run melos bootstrap`.
- Four Rust crate roots — not one Cargo workspace:
  - `packages/image_forge/rust/` (standalone)
  - `packages/image_forge_core/rust/` (standalone)
  - `packages/video_forge/Cargo.toml` (workspace root, member `rust/`)
  - `packages/media_forge/rust/` (standalone; FFmpeg + cpal decode/mix)

| Package | Role | Depends on |
| --- | --- | --- |
| `pixel_surface` | GPU Texture bridge only | — |
| `image_forge` | Full Rust image engine + FRB (face/GPU/presets) | `pixel_surface` |
| `image_forge_core` | Lightweight Rust image engine (no UI/presets) | — |
| `image_forge_editor` | Editor UI (Riverpod) | `image_forge`, `pixel_surface`, `image_forge_camera` |
| `image_forge_camera` | Live camera YUV stream | — |
| `media_forge` | Playback runtime (decode, clock, texture, cpal audio mixing) | `pixel_surface` |
| `media_forge_player` | Production player SDK on `media_forge` + `pixel_surface` | `media_forge` |
| `video_forge` | Video Rust engine + FFmpeg | — |
| `video_forge_editor` | Video editor UI + export | `video_forge`, `media_forge` |
| `video_forge_kit` | Compress/thumbnails SDK | `video_forge`, `pixel_surface`, `video_forge_cache` |
| `video_forge_cache` | Optional disk cache | — |

## Build, test, analyze

Full suite (repo root): `./test_all.sh` (one-time `chmod +x test_all.sh`).
Knobs: `TEST_RUST_FEATURES` (default `gpu,blurhash`; add `avif` only with NASM installed), `RUN_INTEGRATION=1`, `TEST_DEVICE` (default `macos`), `SKIP_NATIVE_SYNC=1`.

| Layer | Command |
| --- | --- |
| Rust image | `cd packages/image_forge/rust && cargo test --features gpu,blurhash` |
| Rust image core | `cd packages/image_forge_core/rust && cargo test --features gpu,blurhash` |
| Rust video | `cd packages/video_forge && cargo test -p video_forge` |
| Rust media | `cd packages/media_forge/rust && cargo test` (not in `test_all.sh` — run manually) |
| Dart (single package) | `cd packages/<name> && flutter test` (editor: `flutter test test/editor/`) |
| Dart integration | `cd examples/image_editor && flutter test integration_test/ -d <device>` |
| Analyze all | `dart run melos analyze` |
| Analyze one | `dart run melos exec --scope=<name> -- flutter analyze --no-fatal-infos` |

Benchmarks: Rust CLI is fastest (`cd packages/image_forge/rust && cargo run --release --features gpu --bin rust_image_benchmark -- --synthetic -n 10`). Dart benchmarks must run under Flutter (`cd benchmark && ./run_dart_benchmark.sh`), never `dart run` — FRB crashes the standalone VM. Same rule for any FRB app: `flutter run` / `flutter test` only.

## FRB codegen

After editing `rust/src/api/*.rs`, regenerate:

| Package | Command | Output (never edit) |
| --- | --- | --- |
| `image_forge` / `image_forge_core` | `cd packages/<pkg> && flutter_rust_bridge_codegen generate` | `lib/src/rust/` |
| `video_forge` / `media_forge` | `cd packages/<pkg> && flutter_rust_bridge_codegen generate` | `lib/src/frb_generated/` |

Config per package: `flutter_rust_bridge.yaml` (`rust_input: crate::api`).
**Version lockstep (currently `2.13.0-beta.6`, verified):** codegen binary (`cargo install flutter_rust_bridge_codegen --version '=2.13.0-beta.6'`), every Rust `flutter_rust_bridge` pin, and every Dart `flutter_rust_bridge: ^2.13.0-beta.6` (including `benchmark/` and `packages/*/example/`) must agree or apps fail with "Rust initialization failed". After upgrading, regenerate all four packages and run each package's `cargo test` + `flutter analyze` + `flutter test`. Codegen 2.13+ deletes unowned `*.freezed.dart` in the output dir — restore via git and re-run `build_runner` if `@freezed` models are still referenced.

## Logging (required on non-trivial changes)

One stable bracket tag per subsystem + milestone (start/success/failure) + decisive fields. Never log in hot loops (per-frame decode, `build()`, 16 ms tickers). Never delete useful logs in a refactor without replacing them.

- Dart: `debugPrint('[PreviewMux] ready ${durationMs}ms → $path');`
- Rust `video_forge`: `log::info!("[preview] seek target_ms={}", t);`
- Rust `media_forge`: `runtime_log!` (eprintln) in `rust/src/api/runtime.rs`.
- Failures are explicit: error + context (input path, stage) in Rust; `$e` + stack in Dart. No secrets/PII.

Key tags: `[PreviewMux]` (`examples/media_studio/lib/services/preview_playback_mux.dart`, `video_creator_flow.dart`), `[NativePlayback]` (`video_forge_kit/.../native_playback_controller.dart`), `[AudioRuntime]` / `[OverlayDemuxer]` / `[MediaPlaybackEngine]` (`media_forge/rust/src/api/runtime.rs`), `[RustBackend]` (`media_studio/.../rust_backend.dart`), `[EditorChrome]` / `[AdjustStrip]` / `[FilterThumb]` (`image_forge_editor`). Rust pipeline logs: `log::` in `packages/video_forge/rust/src/pipeline/`.
Debug by grepping the tag in order — first missing/wrong milestone is the failing layer. If Dart says success but behavior is wrong, verify the artifact (`ffprobe`, file size) before adding UI logic. After Rust changes, rebuild native before trusting logs.

## media_forge audio (hard-earned, do not reintroduce)

`examples/media_studio` uses one Rust-backed path (timeline + status previews each own a `RustBackend`/`MediaPlaybackEngine` with its own texture). No `video_player`/`just_audio` for BGM (macOS session conflicts), no preview-mux round-trip. `video_creator_flow.dart` calls `RustBackend.syncOverlayTracks()` on timeline changes; cpal callback mixes source + overlays in-process.

- cpal callback is real-time: pre-fetch overlay samples once per buffer, never lock per-overlay mutexes per sample (priority inversion → dropouts).
- `add_overlay()` before `start()` falls back to 48000 Hz/stereo — may mismatch the device.
- `setMuted(true)` silences source + overlays (not source-only). Use per-overlay volume.
- `trim_end_ms` silences all audio at the trim end.
- AAC: add the output stream **after** `avcodec_open2` or MP4s lack extradata (FFmpeg plays, AVPlayer silent).
- After touching `media_forge/rust/src/api/runtime.rs`: `bash scripts/build-ffmpeg-macos-vt.sh` (first time, static VideoToolbox FFmpeg) then `bash scripts/run-rust-media-macos.sh`. Static archives are required for sandboxed apps (shared dylibs fail `dlopen`); Homebrew FFmpeg lacks `hevc_videotoolbox`.
- Silent overlay checklist, top to bottom: `_exportAudioTracks()` non-empty + playhead inside clip window → `[AudioRuntime] Added overlay id=N` → `[OverlayDemuxer] id=N ... initial seek ... succeeded` → `[OverlayDecoder] id=N started`. Source-silent-but-overlay-audible: check `[AudioRuntime] Muted=`, `[AudioDecoder] Decoded N audio frames`, source `FrameQueue` fullness (decoder starvation). See `docs/VIDEO_MEDIA_RUNTIME.md`.

## image_forge_editor UI (Lumina Darkroom)

Dark-only, single mint accent. Tokens: `packages/image_forge_editor/lib/src/editor/theme/lumina_tokens.dart` — surfaces via `LuminaTokens.surfaceContainerLow/Container/High` + `canvas`, foreground via `onSurface/Variant/Muted`, accent via `LuminaTokens.accent` (not legacy `primary`), spacing `space1..8`, radius `radiusXs..2xl`, touch target 44, breakpoints `breakpointPhone 600 / Tablet 900 / Desktop 1100 / Large 1440` (never scatter `width >= 900`).

- Reuse: `ValueChipSlider` (all sliders), `ChipPill/Row/Wrap` (choice-of-N), `ToolButton` (44-pt, filled icon when selected via `EditorIcons.filled/outlined`), `FrostedBar`, `InspectorPanel` (desktop right panel), `CategorizedToolRail` (desktop left), `FilterThumbnail` (LRU-32 cache), `AdjustPageViewPanel` (12 adjustments).
- Type: `AppTypography.toolName` (17 w600, sentence case — no `.toUpperCase()`), `sectionCaps` for inspector labels, mono `numericValue`/`sliderValueBubble` for values. Motion `EditorMotion.fast 150 / medium 250 / slow 400`, `Curves.fastOutSlowIn`.
- Layout: mobile (<900) 5 primary tools + "More" sheet + frosted top bar; desktop (≥900) rail + `LivePreview` + inspector (480 px at ≥1440).

## Gotchas

- AVIF needs NASM — default `TEST_RUST_FEATURES=gpu,blurhash` (no avif).
- Android needs `rustup`, not Homebrew rustc (`packages/image_forge/rust/rust-toolchain.toml` auto-installs targets). `can't find crate for core` → `rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android i686-linux-android`. First Android build compiles per ABI (minutes). CargoKit `exec()` patch for Gradle 9+ is already applied.
- `dart run` never works for FRB code — always `flutter run`/`flutter test`.
- `media_forge` macOS needs the VT FFmpeg build (see above); `media_forge/rust && cargo test` is manual.

## CI

- `.github/workflows/ci.yml` (ubuntu): bootstrap → per-package analyze/test → apt FFmpeg → `cargo test -p video_forge`. No native app build.
- `.github/workflows/media_forge_native.yml` (path-filtered): FRB `2.13.0-beta.6` alignment check; macOS release (static FFmpeg build, hermeticity, `cargo build --release -p media_forge`, protocol/codec + HW-probe test, `media_forge_player` Dart tests); iOS 15 target/build check; Android release + MediaCodec path grep.

## Cursor Cloud specific instructions

Cloud Agent setup is defined in `.cursor/environment.json` and `scripts/cloud-agent-install.sh` (Flutter stable, Rust/Android targets, melos bootstrap, FFmpeg dev libs).

**Linux limitations on this branch:**

- `pixel_surface` `gpu` is **Apple-only** today. On Linux, build/test `image_forge` Rust with CPU features only: `cargo test --features blurhash --no-default-features` (omit default `gpu`/`avif`). AVIF needs NASM (`nasm` package) when enabled.
- `examples/image_editor` Linux desktop builds pull `image_forge` default features and fail until GPU is ported to Vulkan on Linux. Use Dart/widget tests and the Rust CLI benchmark instead.

**Quick health checks (Linux cloud agent):**

```bash
bash scripts/cloud-agent-install.sh          # idempotent bootstrap
dart run melos exec --scope=image_forge_editor -- flutter test
cd packages/video_forge && cargo test -p video_forge
cd packages/image_forge/rust && cargo run --release --features blurhash --no-default-features --bin image_forge_benchmark -- --synthetic -n 3
```
