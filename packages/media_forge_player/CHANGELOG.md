# Changelog

## Unreleased

Subtitle fixes:

* `addExternalSubtitle` sends `file:`/bare URIs to the engine as plain paths
  (`/tmp/a.srt`, never `file:///tmp/a.srt`); http(s) URLs stay verbatim.
* One shared gate for cue delivery — `MediaForgePlayerValue
  .hasActiveSubtitles` (enabled + a selected track) is used by
  `subtitleTextAt`, `PlayerCaptionOverlay` and `MediaForgeVideo`'s overlay.
  Selecting **Off** now actually clears the selection (previously
  `copyWith(selectedSubtitleTrackId: null)` kept the old track) and hides an
  open sidecar session deterministically; `closeExternalSubtitles()` tears the
  session down. The cue cache is dropped on selection/enable/source changes.
* A fresh source auto-selects the embedded track flagged forced or default
  (`_refreshTracks`), so flagged subtitles show without a manual pick. An
  explicit Off, or subtitles switched off, is never overridden; sidecar tracks
  are cleared with the source that owned them.
* `SubtitleTracksPanel` reports external-subtitle load failures (SnackBar
  instead of a silent no-op).

Experimental GPU video enhancement (additive, off by default):

* `VideoEnhancementMode` (`off` / `sharp` / `enhanced` / `highQuality`) plus
  `MediaForgePlayerController.setVideoEnhancementMode` — a live setting that
  applies to the next presented frame with no media reopen, no decoder restart
  and no queue flush. `MediaForgePlayerValue.videoEnhancementMode` /
  `videoEnhancementActive` / `videoEnhancementFallbackReason` carry the state.
* `MediaForgePlayerController.probeVideoEnhancement()`,
  `enhancementCapabilities` (ValueNotifier), `supportsVideoEnhancement`,
  `supportedVideoEnhancementModes` and `videoEnhancementStatus` expose
  capabilities and live diagnostics (active mode, path, input/output
  resolution, GPU ms/frame, deadline misses, fallback reason).
  `MediaForgeDiagnostics` gains matching `videoEnhancement*` fields.
* The stage runs entirely in the native GPU path (VideoToolbox
  `CVPixelBuffer` → Metal compute pass → presentation surface →
  `pixel_surface` → Flutter): no CPU pixel copies, no RGBA round-trip, no
  CPU resize/sharpen filters, no Dart-side image processing.
  `MediaForgeVideo` reports its device-pixel size so the target can follow the
  display.
* Unsupported devices keep the existing render path and playback never fails
  because of enhancement. A deadline-aware quality ladder steps the mode down
  under load (and back up only after a long clean window) so the stage cannot
  cause rebuffering, A/V drift or dropped frames.
* `VideoSettingsPanel` gains an **Experimental** "Video enhancement" section
  (mode picker + live readout), shown only when the device reports a backend.
* See `docs/VIDEO_ENHANCEMENT.md` for the architecture, resolution policy and
  measured GPU timings.

Buffered ranges + built-in fullscreen (backward-compatible):

* `MediaForgeBufferedRange` (generic time ranges, never torrent/libtorrent
  types) + `normalizeBufferedRanges` / `mergeBufferedRanges` /
  `contiguousBufferedPosition` / `bufferedAhead` + `MediaForgeBufferState`.
* `MediaForgePlayerValue`: `bufferedPosition`, `bufferedRanges`,
  `bufferedAhead`, `isRebuffering` vs `isPreloading`, `packetBufferedDuration`
  / `packetBufferedBytes`, `decodedVideoFrames` / `decodedFrameMemoryBytes`
  (legacy `buffered`/`isBuffering` preserved and kept in sync).
* Controller derives honest buffering from real engine state
  (decoded-ahead + compressed packet window capped by the byte/duration
  budgets): files report full availability, HTTP(S) only the genuinely
  demuxed window — never the full Content-Length. Paused read-ahead grows
  the packet window to backpressure without preloading decoded frames.
  Dedicated `bufferState` notifier keeps timeline updates off the video
  texture. `setExternalBufferedRanges` / `clearExternalBufferedRanges`
  merge host cache (union, no double-count).
* `PlayerTimeline`: multi-range buffered rendering (visible while paused),
  legacy single-point fallback, external-range merge, hover/thumbnails and
  chapter markers preserved.
* `MediaForgeFullscreenController` (`enter/exit/toggle/isFullscreen`) +
  `MediaPlayerScreen` built-in immersive fullscreen (button visible by
  default, `Enter fullscreen` / `Exit fullscreen` tooltips, `F` toggles,
  `Esc` exits, shortcuts preserved, same controller/session throughout,
  mobile SystemChrome/orientation restore on exit/dispose, desktop host
  callback escape hatch). Legacy `onToggleFullscreen`/`isFullscreen`
  preserved. Bottom-right order: speed, subtitles, audio, fullscreen,
  settings (responsive).
* Tests: `buffered_range_test.dart`, `fullscreen_controller_test.dart`.

Production native-resolution hardening (backward-compatible):

* `MediaForgePlayerConfiguration` with `MediaForgeDecodeResolution.native`
  (explicit enum, never a magic sentinel) + packet-queue budgets
  (video 16 MiB/5 s, audio 4 MiB/5 s), decoded-frame budgets (HW ~3 / SW ~2),
  diagnostics cadence and `MediaForgeNetworkProfile`.
* `MediaForgeNetworkProfile`: `torrentLocalhost` (60 s, reconnect, Range),
  `directHttp` (30 s, caller headers/reconnect), `cachedFile` (file open).
* Frame-ready presentation pump: exactly one frame callback per presentable
  frame; no bridge calls while paused/completed/backgrounded/disposed.
* True drop accounting: empty polls never count; overflow/catch-up/decoder
  drops + presented/bridge counts observable.
* Events: `firstFramePresented`, `seekStarted`/`seekSettled` with monotonic
  generations; first-frame/seek latencies in diagnostics. Stale seeks rejected.
* Lifecycle `suspend()`/`resume()` (background parks pump/diag/subtitles).
* Subtitle efficiency: no bridge poll when disabled/untracked; same-position
  cache behind `subtitlePollMinimumInterval`.
* Deterministic idempotent `release()` (ordered, single future) +
  `resourceCountersForTest()` for zero-verification.
* Diagnostics expansion (§16, all additive): first-decoded/presented,
  latencies, presented/bridge counts, split drops, queue bytes/durations,
  frame memory, probe duration, rendering path, native/presented dims,
  retained buffer/texture counts, suspension flag.
* Docs: `NATIVE_TOOLCHAIN.md`, `PRODUCTION_VALIDATION.md`;
  `media_forge_production_test.dart` coverage (§20).

Player UI (`lib/src/player_ui`, exported from the package barrel):

* `MediaPlayerScreen`: immersive auto-hiding player (top bar, timeline,
  transport, state layers, gestures, keyboard shortcuts, context menu).
* `PlayerTimeline`: buffered range, chapter markers, drag scrub, desktop
  hover timestamp + optional async thumbnail hook.
* Settings panels: speed, audio tracks, subtitles (+delay/appearance),
  video display + detection readout; bottom sheet / dialog responsive.
* `MediaInformationPanel`: source, tracks, playback stats, optional
  app-provided swarm (`MediaPlayerTorrentStats`) section.
* Controller additions: `videoTracks` + `selectVideoTrack`,
  selections cleared on `open`.
* `MediaForgeTexturePresenter.dispose` no longer disposes its
  `ValueNotifier`s (survives controller release while mounted).

## 0.1.0

Initial release:

* `MediaForgeMedia` file/network/asset sources.
* `MediaForgePlayerController` + `MediaForgePlayerValue`.
* `MediaForgeVideo` widget.
* Vsync presentation loop, stable texture handle, `resizeTexture`.
* Buffering + diagnostics (`MediaForgeDiagnostics`).
* Audio/subtitle track API surface (engine switching pending).
* Localhost HTTP Range integration test.
* Docs: architecture, supported formats, benchmarks.
