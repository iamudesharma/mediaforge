# GPU Video Enhancement (experimental)

Optional GPU upscaling / detail enhancement for `media_forge_player`.

**Default is off. Nothing changes for existing callers.** The whole feature is
additive: no constructor signature changed, no existing method changed
behaviour, and an unsupported device simply keeps the current render path.

## Why it exists

Hardware decoders hand back a frame at (or near) the encoded resolution. When
the display is larger, the compositor stretches it with a cheap filter. The
enhancement stage replaces that with a GPU pass that does the scaling and
detail work deliberately, on the same surface the decoder produced.

## Architecture

```
FFmpeg / media_forge decode
  → VideoToolbox hardware frame (CVPixelBuffer / IOSurface, BGRA)
  → Metal compute pass        ← the only new stage
  → IOSurface-backed presentation surface
  → pixel_surface (Flutter Texture, zero-copy adopt)
  → Flutter
```

* The decoded `CVPixelBuffer` is imported as a GPU texture via
  `CVMetalTextureCache`. No CPU pixel copy, no RGBA round-trip.
* The pass writes into another IOSurface-backed `CVPixelBuffer` that
  `pixel_surface`'s Darwin plugin adopts directly, exactly like the decoder's
  own frames. All textures are `bgra8unorm`, so the shader works in logical
  RGBA and no channel swizzle is needed.
* Enhancement is **never** implemented in Dart and **not** an FFmpeg CPU
  filter. Dart only routes a pointer.
* A source that cannot be enhanced safely (unsupported device, unusable
  format, deadline pressure) is presented untouched. Playback never fails
  because of enhancement.

Code layout:

| Layer | File |
| --- | --- |
| Modes, backend trait, capabilities | `pixel_surface/rust/src/enhance/mod.rs` |
| Resolution-aware target planning | `pixel_surface/rust/src/enhance/plan.rs` |
| Deadline-aware quality ladder | `pixel_surface/rust/src/enhance/policy.rs` |
| Metal/wgpu backend | `pixel_surface/rust/src/enhance/metal.rs` |
| Compute kernels | `pixel_surface/rust/src/enhance/shaders/enhance.wgsl` |
| Engine bridge + FRB API | `media_forge/rust/src/video_enhance.rs`, `media_forge/rust/src/api/runtime.rs` |
| Public player API | `media_forge_player/lib/src/video_enhancement.dart` |

## Modes

| Mode | GPU work | Intended for |
| --- | --- | --- |
| `off` | none | everything (default) |
| `sharp` | 1 pass: contrast-adaptive unsharp at native size | sources already close to display resolution |
| `enhanced` | 2 passes: separable Catmull-Rom upscale, then adaptive sharpen + dither | 480p/720p on a 1080p display |
| `highQuality` | 2 passes: separable Lanczos-3 upscale, then adaptive sharpen + dither | 720p/1080p on a 4K display |

Scaling is always separable (horizontal then vertical), so `highQuality` costs
6 taps per axis instead of 36 per pixel.

Sharpening is a contrast-adaptive unsharp mask, not a fixed kernel: the amount
is gated by the local 3×3 luminance range, so smooth areas get the full detail
lift while already-contrasty edges are left alone. That is what keeps film
grain from turning into noise and avoids halos on hard edges.

"Debanding" here means **triangular dither** applied at 8-bit output. It
suppresses quantization banding in smooth gradients; it is not a gradient-
domain deband filter, and the docs say so on purpose.

**No AI super-resolution in this phase.**

## Resolution-aware behaviour

| Source height | Behaviour |
| --- | --- |
| ≤ 576 (480p) | upscale toward the display, strongest sharpening (0.62) |
| ≤ 800 (720p) | high-quality upscale, moderate sharpening (0.55) |
| ≤ 1200 (1080p) | upscales only if the display asks for more; light sharpening (0.45) |
| > 1200 (1440p/4K) | never upscaled; minimal sharpening (0.28–0.36), bypassed entirely when the display is smaller than the source |

Targets are clamped to the display box (reported by `MediaForgeVideo` in device
pixels), preserving the source aspect ratio, never scaling below the source,
and capped per mode (`enhanced` ≤ 1920 longest edge, `highQuality` ≤ 3840).
Upscales below a 1.06× ratio skip the scaling passes and run the sharpen pass
only.

## Performance protection

Playback stability outranks picture quality.

* The enhancement stage is measured against the **source frame interval**,
  derived from decoded PTS deltas (smoothed, seek-aware).
* One frame is in flight: the stage waits for GPU completion before returning.
  It can therefore never build a backlog, and the measured time is real.
* The quality ladder steps down on pressure: 3 consecutive frames over 75 % of
  the deadline, or a single frame over the deadline, drop one mode
  (`highQuality → enhanced → sharp → off`). At most one step down per second,
  and reaching `off` latches a `deadline_exceeded` reason.
* It steps back up only after 20 s with no misses, one step at a time, never
  above the requested mode — so it cannot oscillate.
* Five consecutive backend failures disable enhancement for that source and
  latch `enhancement_unavailable`; playback continues normally.
* GPU errors are logged and counted instead of panicking. Playback is never
  interrupted by an enhancement failure.

Enhancement never seeks, never reopens media, never flushes queues, and never
touches the clock, so it cannot affect buffering, A/V sync, network behaviour
or torrents.

With `off` (the default) the presenter has no enhancement hook installed at
all: the hot path is byte-for-byte the pre-existing one, with no extra bridge
call, no extra texture and no extra GPU surface.

## Public API

Everything an external app (e.g. PeerStream) needs is exported from
`package:media_forge_player/media_forge_player.dart`.

```dart
final controller = MediaForgePlayerController();

// Once, during settings/app init (creates the GPU pipeline).
final caps = await controller.probeVideoEnhancement();
if (caps.supported) {
  // Live: applies to the next presented frame, no reopen.
  await controller.setVideoEnhancementMode(VideoEnhancementMode.enhanced);
}

// Diagnostics.
final status = controller.videoEnhancementStatus;
debugPrint('${status?.activeMode} ${status?.resolutionLabel} '
    '${status?.lastFrameMs}ms/${status?.deadlineMs}ms '
    'misses=${status?.deadlineMisses} ${status?.path}');
```

| Member | Purpose |
| --- | --- |
| `VideoEnhancementMode` | `off` / `sharp` / `enhanced` / `highQuality` |
| `controller.videoEnhancementMode` | requested mode (`value.videoEnhancementMode` too) |
| `controller.setVideoEnhancementMode(mode)` | live change, returns `false` if refused |
| `controller.probeVideoEnhancement()` | device capability probe |
| `controller.enhancementCapabilities` | `ValueNotifier<VideoEnhancementCapabilities?>`, fires when the probe lands |
| `controller.supportsVideoEnhancement` | capability query |
| `controller.supportedVideoEnhancementModes` | UI gating |
| `controller.videoEnhancementStatus` | active mode, path, resolutions, timings, misses, fallback reason |
| `controller.setVideoEnhancementViewport(w, h)` | display box in device pixels (called by `MediaForgeVideo`) |
| `controller.setVideoEnhancementMaxOutputEdge(edge)` | hard output cap |
| `MediaForgeDiagnostics.videoEnhancement*` | same data in the periodic snapshot |

`VideoSettingsPanel` already renders an **Experimental** section with the four
modes and a live readout, and hides itself entirely when the device reports no
backend.

## Capability handling

`VideoEnhancementCapabilities.supported` is the honest device answer:

* Apple target **and** `pixel_surface/gpu` compiled in **and** a Metal adapter
  with `BGRA8UNORM_STORAGE` **and** the same `MTLDevice` wgpu selected.
* Any failure returns `supported == false` with a `reason` string
  (`no Metal adapter available`, `Metal adapter does not expose
  BGRA8UNORM_STORAGE`, `no MTLDevice named …`, …).

The engine creates the GPU device **lazily** on the first probe or mode
request, so an app that never enables enhancement never pays for a device, and
constructing a player never touches the GPU.

## Tests

| Area | Where |
| --- | --- |
| Target planning, resolution policy, aspect/rounding | `pixel_surface/rust/src/enhance/plan.rs` (`#[cfg(test)]`) |
| Quality ladder, hysteresis, stall/oscillation rules | `pixel_surface/rust/src/enhance/policy.rs` (`#[cfg(test)]`) |
| Real GPU passes, pixel readback, surface recycling, invalid input | `pixel_surface/rust/tests/enhance_metal.rs` |
| Engine bridge, fallback ladder, viewport, ownership | `media_forge/rust/src/video_enhance.rs` (`#[cfg(test)]`) |
| Public API, live mode change, no-reopen, identity, seek/audio/subtitle/fullscreen, cleanup, paused behaviour, settings UI | `media_forge_player/test/video_enhancement_test.dart` |

```sh
cd packages/pixel_surface/rust && cargo test --features gpu
cd packages/media_forge/rust && cargo test
cd packages/media_forge_player && flutter test
```

## Benchmarks

### Enhancement stage (measured)

The stage alone, on real hardware, with the source textures pre-warmed:

```sh
cd packages/pixel_surface/rust
cargo run --release --features gpu --bin enhance_bench -- --frames 200
```

Measured on **Apple M1, macOS 26.6, `--release`, 200 frames/case** (mean of the
enhance stage: input import + passes + GPU completion wait):

| mode | source → display | planned output | path | passes | mean | p50 | p95 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| sharp | 854×480 → 1080p | 854×480 | metal_cas | 1 | 1.39 ms | 1.34 | 1.38 |
| enhanced | 854×480 → 1080p | 1920×1080 | metal_catmull_cas | 3 | 4.07 ms | 3.92 | 5.23 |
| highQuality | 854×480 → 1080p | 1920×1080 | metal_lanczos_cas | 3 | 4.23 ms | 3.93 | 5.38 |
| sharp | 1280×720 → 1080p | 1280×720 | metal_cas | 1 | 1.44 ms | 1.39 | 1.52 |
| enhanced | 1280×720 → 1080p | 1920×1080 | metal_catmull_cas | 3 | 4.62 ms | 4.30 | 6.41 |
| highQuality | 1280×720 → 1080p | 1920×1080 | metal_lanczos_cas | 3 | 4.78 ms | 5.12 | 6.51 |
| sharp | 1280×720 → 4K | 1280×720 | metal_cas | 1 | 1.36 ms | 1.32 | 1.37 |
| enhanced | 1280×720 → 4K | 1920×1080 (mode cap) | metal_catmull_cas | 3 | 4.99 ms | 5.14 | 6.71 |
| highQuality | 1280×720 → 4K | 3840×2160 | metal_lanczos_cas | 3 | 7.94 ms | 7.76 | 9.02 |
| sharp | 1920×1080 → 4K | 1920×1080 | metal_cas | 1 | 1.84 ms | 1.33 | 2.68 |
| enhanced | 1920×1080 → 4K | 1920×1080 (mode cap) | metal_cas | 1 | 2.74 ms | 2.64 | 2.88 |
| highQuality | 1920×1080 → 4K | 3840×2160 | metal_lanczos_cas | 3 | 9.07 ms | 9.02 | 9.44 |

Because the planner caps `enhanced` at a 1920 longest edge, a 720p/1080p source
on a 4K display is served by `highQuality`; the `enhanced` rows above show the
capped (and therefore cheaper) path. `passes` is the real pass count reported
by the backend.

Interpretation, not a claim: on this machine the stage fits a 30 fps budget
(33.3 ms) with a large margin in every configuration, and fits a 60 fps budget
(16.7 ms) for everything except `highQuality` 1080p→4K, which the ladder will
step down from if it ever misses.

### Playback matrix (not yet measured)

The full spec matrix — 480p→1080p, 720p→1080p, 720p→4K, 1080p→4K across H.264
and HEVC at 24/30/60 fps — measures GPU ms/frame **plus** CPU, memory, dropped
frames, A/V drift and energy for the whole player. That requires a physical
device and real media, so it is not reproducible in CI and **no numbers are
claimed here**.

Protocol:

1. Build/run the player app on the target Apple Silicon device.
2. Open each H.264/HEVC clip, set `VideoEnhancementMode.off`, play 60 s, and
   record the baseline from `MediaForgeDiagnostics` (CPU via Instruments/`powermetrics`,
   memory via `vmmap`, dropped frames, `avDriftMs`, energy via `powermetrics --samplers energy`).
3. Repeat with `sharp`, `enhanced`, `highQuality`, each for 60 s.
4. Record `videoEnhancementFrameMs`, `videoEnhancementDeadlineMs`,
   `videoEnhancementDeadlineMisses`, `videoEnhancementPath`,
   `videoEnhancementOutputWidth/Height` from the same snapshots.
5. Report the active path per row; a row that silently fell back to a lower
   mode must say so.

Record the results in a new table here only once they are measured.
