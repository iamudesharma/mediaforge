# media_forge — acceptance checklist

Manual verification on macOS after a full native rebuild (`bash scripts/run-rust-media-macos.sh`).

## Phase 0 — Hardware decode

- [ ] `[Phase0] hevc_videotoolbox=true ready_for_hevc_hw=true`
- [ ] UI badge: **HW HEVC OK** (not SW DECODE)
- [ ] `[VideoDecoder] Hardware decode (VideoToolbox): ...`

## Phase 1–3 — Sync, presenter, catch-up

- [ ] `[PresenterRuntime] Starting paced presenter interval_ms=16`
- [ ] No `[HardResync]` to EOF immediately after scrubbing the timeline
- [ ] `[PresenterRuntime] presented pts=...` every ~2s while playing
- [ ] `[CatchUp] mode=skip-non-key` when drift 500–1500 ms
- [ ] `[HardResync] drift=...` when drift > 2s, then demuxer seek succeeds
- [ ] After hard resync: `[VideoDecoder] Post-seek pipelines ready`
- [ ] No sustained `Scaler run error: Input changed`

## Phase 4 — Dart presentation hot path

- [ ] `[VideoDecoder] … VT→CVPixelBuffer (zero-copy UI)` on Apple HW open
- [ ] `[MediaPresenter] vt pts=…` (not every-frame `rgba`) during 4K HEVC play
- [ ] `[MediaGpuTexture] texture ready` once after open
- [ ] Video updates smoothly without UI jank (no `setState` per frame in hot loop)
- [ ] `MediaVideoSurface` shows picture (not placeholder) within 1–2s of play

Disable zero-copy (RGBA fallback): `MEDIA_DISABLE_VT_ZERO_COPY=1`

## Phase 5 — Automated tests

```bash
cd packages/media_forge/rust && cargo test
cd packages/media_forge && flutter test
```

## Healthy playback (automated + dashboard)

During play of iPhone 4K HEVC:

| Metric | Healthy |
|--------|---------|
| `drift` (audio − decoded) | < 500 ms |
| `VQ` (video frame queue) | ≥ 1 |
| `healthy=true` in `[Status]` log | yes |

## Known limits

- Software-only FFmpeg on 4K HEVC will still trigger catch-up / hard resync; use VT-enabled FFmpeg.
- Simulated gradient mode does not stress A/V sync.
