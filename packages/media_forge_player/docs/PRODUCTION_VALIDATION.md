# Production validation (physical devices)

Baseline: commit `bcf344e` ("center the overlay play cluster"). No benchmark
numbers are claimed here and none are fabricated — fill the tables below
with measured runs from physical devices only. CI validates builds and
protocol/codec presence; it never claims hardware performance (§19).

## Fixtures

* 1080p H.264/AAC 24 fps, 30 fps, 60 fps
* 1080p HEVC
* 4K HEVC 30 fps (hardware-capable devices only)

## Source types

* Local file
* Direct HTTP with headers
* Localhost HTTP Range stream (torrent-streaming equivalent;
  `media_forge_player/test/range_server_test.dart` is the contract)

## Devices

* Physical Mac (Apple Silicon)
* Physical Android device (MediaCodec-capable)
* Physical iPhone (VideoToolbox-capable, iOS 15+)

## Procedure per case

* 20 cold opens (process restart between opens)
* 20 warm opens (same process, `release()` between opens)
* 20 seeks (10 forward, 10 backward, incl. 20-min jump for long media)
* 30-minute steady playback (thermal soak)

## Record per case

First-frame latency, seek latency, decoded FPS, presented FPS, bridge
calls, drops by type (overflow / catch-up / decoder), A/V drift,
CPU, memory, energy, thermal state, queue bytes, frame memory, active
decoder, rendering/copy path, reconnects. Sources:

* `MediaForgeDiagnostics`: `firstFrameLatencyMs`, `lastSeekLatencyMs`,
  `presentedFrameCount`, `bridgeCallCount`, `queueOverflowDrops`,
  `catchupDrops`, `decoderDroppedFrames`, `avDriftMs`, `videoQueueBytes`,
  `audioQueueBytes`, `frameMemoryBytes`, `activeDecoder`, `hwDecode`,
  `renderingPath`, `nativeWidth/Height`, `reconnectCount`, `probeDurationMs`.
* OS profilers for CPU/memory/energy/thermal.

## Acceptance targets

* Presented FPS ≥ 99% of source FPS during steady supported HW playback
* Engine drops < 1% after startup
* A/V drift < 100 ms p95, < 250 ms max outside seek recovery
* Local seek < 300 ms p95; direct HTTP seek < 500 ms p95 excl. server latency
* No per-frame bridge calls while paused/backgrounded
* Bridge calls exceed presented frames by ≤ ~2/sec
* Memory within 10% of post-first-open baseline after 10 open/seek/close cycles
* Retained textures/pixel buffers return to zero after final release
  (`resourceCountersForTest()` all zero; `debugStats()` handleCount 0)

## Reporting

Do not claim Android zero-copy or mobile HW performance until
physical-device logs prove the active rendering path
(`videotoolbox_iosurface_zero_copy` on Apple;
`android_surface_zero_copy` only when the surface path is verified —
today Android reports `android_bitmap_upload`).
