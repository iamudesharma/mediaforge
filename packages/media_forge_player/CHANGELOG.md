# Changelog

## Unreleased

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
