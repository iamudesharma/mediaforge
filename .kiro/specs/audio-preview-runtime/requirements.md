# Requirements Document

## Introduction

This document captures the requirements for `AudioPreviewRuntime`, a new Dart class that replaces the five flat audio-preview state fields in `_VideoCreatorFlowState` (`_audioPreview`, `_audioPreviewSyncGen`, `_audioPreviewBusy`, `_audioStartInFlight`, `_lastAudioDriftCorrectionMs`) with a single encapsulated object.

The runtime uses `just_audio` (preferred) or `VideoPlayerController` as a fallback for audio-only playback, manages a `Map<String, player>` keyed by clip ID for multi-track support, and exposes a clean interface (`play`, `pause`, `seekTo`, `maintainDrift`, `stop`, `dispose`) to `_VideoCreatorFlowState`. The gen-counter and in-flight guard logic are managed internally per track.

This feature directly addresses the known limitation documented in the `audio-track-preview-fix` design: `VideoPlayerController` is heavyweight for audio-only playback (~100–500 ms startup, high memory, video backend overhead). It also lays the architectural foundation for multiple simultaneous audio tracks, overlapping clips, volume ducking, and per-track effects.

---

## Glossary

- **AudioPreviewRuntime**: The new Dart class defined in `examples/media_studio/lib/services/audio_preview_runtime.dart` that owns all audio preview state and logic.
- **TrackPlayer**: A single audio player instance (backed by `just_audio` `AudioPlayer` or `VideoPlayerController`) managed by `AudioPreviewRuntime` for one clip ID.
- **TrackState**: The per-track bookkeeping held inside `AudioPreviewRuntime`: the `TrackPlayer`, its sync-gen counter, and its in-flight flag.
- **SyncGen**: An integer generation counter per track, incremented when a track is stopped or replaced. Used to detect stale in-flight initialisation operations.
- **InFlightFlag**: A per-track boolean that is `true` if and only if the track's initialisation coroutine is currently executing.
- **BusyFlag**: A per-track reentrancy guard that prevents concurrent start and drift-correction operations on the same track.
- **DriftThreshold**: The minimum A/V offset (in milliseconds) that triggers a corrective seek during `maintainDrift`. Default: 1000 ms.
- **DriftCooldown**: The minimum time (in milliseconds) between consecutive corrective seeks for the same track. Default: 900 ms.
- **VolumeDucking**: Automatically lowering the volume of background-music tracks when a voiceover track is playing.
- **VideoCreatorFlowState**: The Flutter `State` class `_VideoCreatorFlowState` in `examples/media_studio/lib/video_creator_flow.dart`.
- **just_audio**: The `just_audio` Flutter package — a lightweight audio-only player with fast startup and precise seeking.
- **TimelineMs**: A position on the master video timeline, measured in milliseconds from the start of the composition.

---

## Requirements

### Requirement 1: AudioPreviewRuntime class and file location

**User Story:** As a developer, I want all audio preview state and logic encapsulated in a single class, so that `_VideoCreatorFlowState` is not cluttered with audio bookkeeping and the audio subsystem can be tested and evolved independently.

#### Acceptance Criteria

1. THE AudioPreviewRuntime SHALL be defined in a new file at `examples/media_studio/lib/services/audio_preview_runtime.dart`.
2. THE AudioPreviewRuntime SHALL expose the following public methods: `play(int timelineMs, List<AudioTimelineClip> clips)`, `pause()`, `seekTo(int timelineMs, List<AudioTimelineClip> clips)`, `maintainDrift(int timelineMs, List<AudioTimelineClip> clips)`, `stop()`, and `dispose()`.
3. THE AudioPreviewRuntime SHALL manage a `Map<String, TrackState>` keyed by clip ID, where each entry owns one `TrackPlayer` and its associated `SyncGen` counter and `InFlightFlag`.
4. WHEN `_VideoCreatorFlowState` is updated to use `AudioPreviewRuntime`, THE VideoCreatorFlowState SHALL replace the five flat fields (`_audioPreview`, `_audioPreviewSyncGen`, `_audioPreviewBusy`, `_audioStartInFlight`, `_lastAudioDriftCorrectionMs`) with a single `AudioPreviewRuntime _audioRuntime` field.
5. THE AudioPreviewRuntime SHALL NOT expose any internal `TrackState`, `SyncGen`, or `InFlightFlag` fields as part of its public API.

---

### Requirement 2: Audio player backend selection

**User Story:** As a developer, I want the runtime to use `just_audio` for audio-only playback when available, so that startup latency is reduced and memory overhead is lower than `VideoPlayerController`.

#### Acceptance Criteria

1. WHERE `just_audio` is listed as a dependency in `examples/media_studio/pubspec.yaml`, THE AudioPreviewRuntime SHALL use `just_audio` `AudioPlayer` as the `TrackPlayer` implementation.
2. WHERE `just_audio` is not available, THE AudioPreviewRuntime SHALL fall back to `VideoPlayerController` as the `TrackPlayer` implementation, preserving all existing behaviour.
3. THE AudioPreviewRuntime SHALL initialise a `TrackPlayer` for a given clip only once per clip ID per play session; subsequent calls to `play` or `maintainDrift` for the same clip ID SHALL reuse the existing initialised player.
4. WHEN a `TrackPlayer` is initialised using `just_audio`, THE AudioPreviewRuntime SHALL call `AudioPlayer.setFilePath(clip.sourcePath)` and await the returned `Duration` before marking the player as ready.
5. WHEN a `TrackPlayer` initialisation fails (any exception), THE AudioPreviewRuntime SHALL dispose the failed player, remove its entry from the internal map, and log the error without crashing.

---

### Requirement 3: play — start or resume all active tracks

**User Story:** As a user, I want all non-muted audio tracks to start playing at the correct timeline position when I press play, so that background music and voiceover are in sync with the video from the first frame.

#### Acceptance Criteria

1. WHEN `play(timelineMs, clips)` is called, THE AudioPreviewRuntime SHALL, for each non-muted clip whose time range contains `timelineMs`, initialise (if needed) and start a `TrackPlayer` seeked to `clip.sourceStartMs + (timelineMs - clip.timelineStartMs)`.
2. WHEN `play(timelineMs, clips)` is called, THE AudioPreviewRuntime SHALL stop and dispose any `TrackPlayer` whose clip ID is no longer present in `clips` or whose clip is now muted.
3. WHEN a `TrackPlayer` is already initialised and playing the correct clip, THE AudioPreviewRuntime SHALL seek it to the correct source position and resume playback without reinitialising the player.
4. WHEN `play` is called while a `TrackPlayer` initialisation is already in flight for a given clip ID (i.e. `InFlightFlag` is `true`), THE AudioPreviewRuntime SHALL not start a second initialisation for that clip.
5. WHEN `timelineMs` is outside the time range of a clip, THE AudioPreviewRuntime SHALL not start a `TrackPlayer` for that clip and SHALL pause any existing player for that clip.

---

### Requirement 4: pause — suspend all active tracks

**User Story:** As a user, I want all audio tracks to pause immediately when I pause the video, so that audio does not continue playing after the video stops.

#### Acceptance Criteria

1. WHEN `pause()` is called, THE AudioPreviewRuntime SHALL call pause on every active `TrackPlayer` without disposing the players or incrementing any `SyncGen` counter.
2. WHEN `pause()` is called while a `TrackPlayer` initialisation is in flight, THE AudioPreviewRuntime SHALL allow the initialisation to complete but SHALL NOT call play on the player once it is ready.
3. WHEN `pause()` is called and no `TrackPlayer` instances are active, THE AudioPreviewRuntime SHALL return without error.

---

### Requirement 5: seekTo — reposition all tracks without starting playback

**User Story:** As a user, I want scrubbing the timeline to reposition audio tracks silently, so that when I resume playback the audio starts at the correct position.

#### Acceptance Criteria

1. WHEN `seekTo(timelineMs, clips)` is called, THE AudioPreviewRuntime SHALL seek each initialised `TrackPlayer` whose clip contains `timelineMs` to `clip.sourceStartMs + (timelineMs - clip.timelineStartMs)` without calling play.
2. WHEN `seekTo(timelineMs, clips)` is called and `timelineMs` is outside a clip's range, THE AudioPreviewRuntime SHALL pause the `TrackPlayer` for that clip if one exists.
3. WHEN `seekTo` is called while no `TrackPlayer` instances are initialised, THE AudioPreviewRuntime SHALL return without error.

---

### Requirement 6: maintainDrift — correct A/V drift during playback

**User Story:** As a developer, I want the runtime to periodically correct audio drift during playback, so that audio stays in sync with the video even after long playback sessions.

#### Acceptance Criteria

1. WHEN `maintainDrift(timelineMs, clips)` is called and a `TrackPlayer` for a given clip is playing but its actual position deviates from the expected position by more than `DriftThreshold` milliseconds, THE AudioPreviewRuntime SHALL seek that player to the expected position, subject to `DriftCooldown`.
2. WHEN `maintainDrift` is called and a `TrackPlayer` for a given clip is not yet initialised AND `InFlightFlag` is `false` for that clip, THE AudioPreviewRuntime SHALL initiate player initialisation and start playback.
3. WHEN `maintainDrift` is called and `InFlightFlag` is `true` for a given clip, THE AudioPreviewRuntime SHALL skip that clip without starting a second initialisation.
4. WHEN `maintainDrift` is called and a `TrackPlayer` is initialised but not playing (and the clip is active and non-muted), THE AudioPreviewRuntime SHALL call play on that player.
5. WHEN `maintainDrift` is called and `BusyFlag` is `true` for a given clip, THE AudioPreviewRuntime SHALL skip that clip to prevent reentrancy.
6. THE AudioPreviewRuntime SHALL NOT increment any `SyncGen` counter from within `maintainDrift` or any path called exclusively from `maintainDrift`.

---

### Requirement 7: stop — halt all tracks and release controllers

**User Story:** As a developer, I want a `stop()` call to halt all audio and release all player resources, so that pausing or stopping the video preview leaves no zombie controllers running.

#### Acceptance Criteria

1. WHEN `stop()` is called, THE AudioPreviewRuntime SHALL pause and dispose every `TrackPlayer` in the internal map and clear the map.
2. WHEN `stop()` is called, THE AudioPreviewRuntime SHALL increment the `SyncGen` counter for every active track before disposing, so that any in-flight initialisation detects the generation mismatch and aborts without calling play.
3. WHEN `stop()` is called while no `TrackPlayer` instances are active, THE AudioPreviewRuntime SHALL return without error.
4. WHEN a `TrackPlayer` disposal throws an exception during `stop()`, THE AudioPreviewRuntime SHALL catch the exception, log it, and continue disposing the remaining players.

---

### Requirement 8: dispose — release all resources from widget dispose

**User Story:** As a developer, I want `dispose()` to release all audio resources safely when the widget is torn down, so that there are no memory leaks or dangling callbacks.

#### Acceptance Criteria

1. WHEN `dispose()` is called, THE AudioPreviewRuntime SHALL call `stop()` to halt and release all `TrackPlayer` instances.
2. WHEN `dispose()` is called, THE AudioPreviewRuntime SHALL set an internal `_disposed` flag to `true` so that any subsequently completing async operations are silently ignored.
3. WHEN `dispose()` is called while a `TrackPlayer` initialisation is in flight, THE AudioPreviewRuntime SHALL rely on the `SyncGen` mismatch (set by `stop()`) to abort the in-flight operation without calling play.
4. WHEN `VideoCreatorFlowState.dispose()` is called, THE VideoCreatorFlowState SHALL call `_audioRuntime.dispose()` using `unawaited()` to make the fire-and-forget intent explicit.

---

### Requirement 9: per-track gen-counter and in-flight guard

**User Story:** As a developer, I want each track to have its own generation counter and in-flight flag, so that stopping one track does not interfere with the initialisation of another track.

#### Acceptance Criteria

1. THE AudioPreviewRuntime SHALL maintain a separate `SyncGen` integer for each clip ID in the internal map.
2. WHEN a `TrackPlayer` initialisation completes for a given clip, THE AudioPreviewRuntime SHALL compare the captured gen value against the current `SyncGen` for that clip; IF they differ, THEN THE AudioPreviewRuntime SHALL dispose the newly initialised player and return without calling play.
3. WHEN `stop()` or `dispose()` increments the `SyncGen` for a track, THE AudioPreviewRuntime SHALL NOT increment the `SyncGen` counters of other tracks.
4. THE AudioPreviewRuntime SHALL set `InFlightFlag` to `true` before beginning a `TrackPlayer` initialisation and SHALL clear it in a `finally` block after the initialisation completes or fails.
5. THE AudioPreviewRuntime SHALL set `BusyFlag` to `true` before entering any start or drift-correction operation for a given track and SHALL clear it in a `finally` block.

---

### Requirement 10: volume control and ducking

**User Story:** As a user, I want each audio track to play at its configured volume, and background music to be lowered automatically when a voiceover is playing, so that speech is always intelligible.

#### Acceptance Criteria

1. WHEN a `TrackPlayer` is started or resumed, THE AudioPreviewRuntime SHALL set its volume to `clip.volume` (range 0.0–1.0).
2. WHEN a clip's `muted` flag is `true`, THE AudioPreviewRuntime SHALL set the `TrackPlayer` volume to `0.0` rather than pausing or disposing the player.
3. WHERE volume ducking is enabled and a voiceover clip (clip ID prefixed with `"vo:"`) is actively playing, THE AudioPreviewRuntime SHALL reduce the volume of all non-voiceover `TrackPlayer` instances to `clip.volume * 0.3`.
4. WHEN the voiceover clip stops or is paused, THE AudioPreviewRuntime SHALL restore non-voiceover `TrackPlayer` volumes to their configured `clip.volume`.
5. WHERE volume ducking is not enabled, THE AudioPreviewRuntime SHALL play all tracks at their configured `clip.volume` without modification.

---

### Requirement 11: multi-track simultaneous playback

**User Story:** As a user, I want background music and voiceover to play simultaneously during preview, so that I can hear the full audio mix before exporting.

#### Acceptance Criteria

1. WHEN `play(timelineMs, clips)` is called with multiple non-muted clips whose ranges contain `timelineMs`, THE AudioPreviewRuntime SHALL start a `TrackPlayer` for each such clip.
2. WHEN two clips overlap on the timeline, THE AudioPreviewRuntime SHALL play both `TrackPlayer` instances concurrently without one cancelling the other.
3. WHEN a clip ends (its `timelineEndMs` is reached) while other clips are still playing, THE AudioPreviewRuntime SHALL pause and dispose only the `TrackPlayer` for the ended clip without affecting other active players.
4. THE AudioPreviewRuntime SHALL support at least two simultaneous `TrackPlayer` instances without error.

---

### Requirement 12: integration with VideoCreatorFlowState

**User Story:** As a developer, I want `_VideoCreatorFlowState` to delegate all audio preview operations to `AudioPreviewRuntime`, so that the state class is free of audio bookkeeping and the audio subsystem can be replaced or extended without touching the UI layer.

#### Acceptance Criteria

1. WHEN `_togglePlayback` initiates playback, THE VideoCreatorFlowState SHALL call `_audioRuntime.play(_playheadTimelineMs, _timeline.audioClips)` instead of `_startAudioPreview()`.
2. WHEN `_togglePlayback` pauses playback, THE VideoCreatorFlowState SHALL call `_audioRuntime.stop()` instead of `_stopAudioPreview()`.
3. WHEN `_onPlayerUpdated` fires during playback, THE VideoCreatorFlowState SHALL call `_audioRuntime.maintainDrift(_playheadTimelineMs, _timeline.audioClips)` instead of `_maintainAudioPreviewDrift()`.
4. WHEN `_advancePastClipEndIfNeeded` triggers a clip jump, THE VideoCreatorFlowState SHALL call `_audioRuntime.play(nextClip.timelineStartMs, _timeline.audioClips)` to restart audio at the new position.
5. WHEN the user scrubs the timeline while paused, THE VideoCreatorFlowState SHALL call `_audioRuntime.seekTo(_playheadTimelineMs, _timeline.audioClips)` to reposition audio silently.
6. WHEN `_onTimelineUpdated` fires (e.g. mute toggle, volume change), THE VideoCreatorFlowState SHALL call `_audioRuntime.maintainDrift(_playheadTimelineMs, _timeline.audioClips)` if playback is active, so that volume changes take effect immediately.

---

### Requirement 13: error handling and resilience

**User Story:** As a developer, I want the runtime to handle all player errors gracefully, so that a failure in one audio track does not crash the app or block other tracks.

#### Acceptance Criteria

1. IF a `TrackPlayer` initialisation throws an exception, THEN THE AudioPreviewRuntime SHALL catch the exception, log it with the clip ID and error message, dispose the failed player, and remove the entry from the internal map.
2. IF a `TrackPlayer` seek or play call throws an exception, THEN THE AudioPreviewRuntime SHALL catch the exception, log it, and continue processing other tracks.
3. IF `dispose()` is called and a `TrackPlayer` disposal throws an exception, THEN THE AudioPreviewRuntime SHALL catch the exception, log it, and continue disposing remaining players.
4. WHEN the `_disposed` flag is `true`, THE AudioPreviewRuntime SHALL silently ignore all calls to `play`, `pause`, `seekTo`, `maintainDrift`, and `stop` without throwing.

---

### Requirement 14: round-trip position accuracy

**User Story:** As a developer, I want the expected audio position calculation to be invertible, so that seeking to a timeline position and reading back the player position yields the original timeline position within a small tolerance.

#### Acceptance Criteria

1. THE AudioPreviewRuntime SHALL compute the expected source position for a clip as `clip.sourceStartMs + (timelineMs - clip.timelineStartMs)`.
2. FOR ALL valid `timelineMs` values within a clip's range, the computed source position SHALL satisfy `sourceStartMs <= sourcePos < sourceEndMs`.
3. FOR ALL valid `timelineMs` values within a clip's range, converting the source position back to a timeline position using `clip.timelineStartMs + (sourcePos - clip.sourceStartMs)` SHALL yield the original `timelineMs` exactly (round-trip property).
4. WHEN `timelineMs` equals `clip.timelineStartMs`, THE AudioPreviewRuntime SHALL compute a source position equal to `clip.sourceStartMs`.
5. WHEN `timelineMs` equals `clip.timelineEndMs - 1`, THE AudioPreviewRuntime SHALL compute a source position equal to `clip.sourceEndMs - 1`.
