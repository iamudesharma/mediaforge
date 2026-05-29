# Requirements Document

## Introduction

This document captures the requirements for fixing audio track playback in the `media_studio` example app. Added audio tracks do not play during video preview due to a race condition between `_startAudioPreview()` and `_maintainAudioPreviewDriftInner()` in `_VideoCreatorFlowState`. The drift maintenance path can clear `_audioPreviewBusy` and re-enter `_startAudioPreview`, incrementing `_audioPreviewSyncGen` and causing the original in-flight start to see a generation mismatch and bail before ever calling `preview.play()`.

The fix introduces three targeted changes:
1. An `_audioStartInFlight` boolean flag managed in `_startAudioPreview`'s try/finally block.
2. An early-return guard in `_maintainAudioPreviewDriftInner` that skips re-entry when a start is already in flight.
3. Wrapping `_stopAudioPreview()` in `unawaited()` inside `dispose()` to make the fire-and-forget intent explicit.

## Glossary

- **AudioPreview**: The subsystem within `_VideoCreatorFlowState` responsible for initialising and playing a `VideoPlayerController` for the background audio track during video preview.
- **DriftMaintainer**: The `_maintainAudioPreviewDrift` / `_maintainAudioPreviewDriftInner` path, called on every native player tick to keep audio in sync with video.
- **StartPath**: The `_startAudioPreview` / `_startAudioPreviewInner` path, called once per play action to initialise and start the audio controller.
- **SyncGen** (`_audioPreviewSyncGen`): An integer generation counter incremented exclusively by `_stopAudioPreview()`. Used to detect stale in-flight operations.
- **InFlightFlag** (`_audioStartInFlight`): A boolean that is `true` if and only if `_startAudioPreviewInner` is currently executing.
- **BusyFlag** (`_audioPreviewBusy`): A reentrancy guard shared by both the StartPath and the DriftMaintainer.
- **VideoCreatorFlowState**: The Flutter `State` class `_VideoCreatorFlowState` in `examples/media_studio/lib/video_creator_flow.dart`.

---

## Requirements

### Requirement 1: Audio track plays on video preview start

**User Story:** As a user, I want added audio tracks to play when I press play, so that I can preview my video with background music.

#### Acceptance Criteria

1. WHEN the user initiates playback and a non-muted audio track exists in the timeline and the playhead is within the audio track's time range, THE AudioPreview SHALL call `preview.play()` within the same play action.
2. WHEN `_startAudioPreview` is called and `_audioPreviewBusy` is already `true`, THE AudioPreview SHALL return immediately without starting a second initialisation.
3. WHEN `_startAudioPreviewInner` completes (whether normally or via an exception), THE AudioPreview SHALL set `_audioPreviewBusy` to `false` in a `finally` block.
4. WHEN no non-muted audio track exists in the timeline, THE AudioPreview SHALL not attempt to initialise a `VideoPlayerController`.
5. WHEN the playhead is outside all audio track time ranges, THE AudioPreview SHALL pause any active audio controller rather than playing it.

---

### Requirement 2: Race condition prevention between StartPath and DriftMaintainer

**User Story:** As a developer, I want the drift maintenance path to never interfere with an in-flight audio start, so that the generation counter is not incremented mid-initialisation and `preview.play()` is always reached.

#### Acceptance Criteria

1. WHILE `_startAudioPreviewInner` is executing, THE AudioPreview SHALL keep `_audioStartInFlight` set to `true`.
2. WHEN `_startAudioPreview` exits (normally or via exception), THE AudioPreview SHALL set `_audioStartInFlight` to `false` in a `finally` block.
3. WHEN `_maintainAudioPreviewDriftInner` detects that the audio controller is not ready AND `_audioStartInFlight` is `true`, THE DriftMaintainer SHALL return immediately without calling `_startAudioPreview`.
4. WHEN `_maintainAudioPreviewDriftInner` detects that the audio controller is not ready AND `_audioStartInFlight` is `false`, THE DriftMaintainer SHALL clear `_audioPreviewBusy` and call `_startAudioPreview` to recover.
5. THE DriftMaintainer SHALL NOT call `_stopAudioPreview()` or increment `_audioPreviewSyncGen` directly.
6. IF `_audioPreviewSyncGen` is incremented during `_startAudioPreviewInner` execution (e.g. by an external `_stopAudioPreview` call), THEN THE AudioPreview SHALL detect the generation mismatch after `_ensureAudioPreviewController` returns and bail without calling `preview.play()`.
7. WHEN the DriftMaintainer calls `_stopAudioPreview()` while `_startAudioPreviewInner` is executing, THE AudioPreview SHALL rely on the generation mismatch detection to abort the in-flight start rather than blocking the `_stopAudioPreview` call.

---

### Requirement 3: Correct resource cleanup on dispose

**User Story:** As a developer, I want the widget's `dispose()` method to release the audio controller without causing analyzer warnings or silent Future discards, so that the cleanup intent is explicit and lint-clean.

#### Acceptance Criteria

1. WHEN `dispose()` is called, THE VideoCreatorFlowState SHALL invoke `_stopAudioPreview()` wrapped in `unawaited()` so the returned `Future` is explicitly discarded.
2. WHEN `dispose()` is called while `_startAudioPreviewInner` is in flight, THE AudioPreview SHALL detect the generation mismatch (incremented by `_stopAudioPreview`) and abort without calling `preview.play()`.
3. WHEN `dispose()` completes, THE VideoCreatorFlowState SHALL have cancelled `_progressSub`, removed the timeline listener, disposed `_playheadNotifier`, and torn down the native player.
4. WHERE cleanup operations (such as tearing down the native player or stopping audio) are triggered outside of `dispose()` (e.g. on track removal or explicit stop), THE VideoCreatorFlowState SHALL allow those operations to proceed independently without requiring a `dispose()` call.

---

### Requirement 4: Regression — pause and resume

**User Story:** As a user, I want audio to restart correctly after pausing and resuming playback, so that the audio stays in sync with the video across multiple play/pause cycles.

#### Acceptance Criteria

1. WHEN the user pauses playback, THE AudioPreview SHALL call `_stopAudioPreview()`, incrementing `_audioPreviewSyncGen` and disposing the audio controller.
2. WHEN the user resumes playback after a pause, THE AudioPreview SHALL reinitialise the audio controller and call `preview.play()` at the correct offset.
3. WHEN rapid play/pause toggling occurs, THE AudioPreview SHALL eventually return `_audioPreviewBusy` to `false` and SHALL NOT leave it permanently `true`.

---

### Requirement 5: Regression — seek then play

**User Story:** As a user, I want audio to start at the correct position after I seek to a new point and press play, so that audio and video remain in sync.

#### Acceptance Criteria

1. WHEN the user seeks to a timeline position within an audio track's range and then initiates playback, THE AudioPreview SHALL seek the audio controller to `track.sourceStartMs + (playheadTimelineMs - track.timelineStartMs)` before calling `preview.play()`.
2. WHEN the user seeks to a timeline position outside all audio track ranges and then initiates playback, THE AudioPreview SHALL seek the audio controller to the corresponding timeline position and SHALL NOT call `preview.play()`.

---

### Requirement 6: Regression — audio track removal while playing

**User Story:** As a user, I want removing an audio track while the video is playing to stop the audio cleanly, so that there are no crashes or zombie controllers left running.

#### Acceptance Criteria

1. WHEN an audio track is removed from the timeline while playback is active, THE AudioPreview SHALL call `_stopAudioPreview()`, disposing the audio controller and setting `_audioPreview` to `null`.
2. WHEN `_startAudioPreviewInner` is in flight at the moment the track is removed, THE AudioPreview SHALL detect the generation mismatch — caused specifically by the `_stopAudioPreview()` call triggered by track removal — after `_ensureAudioPreviewController` returns and abort without calling `preview.play()`.
3. IF the audio controller initialisation throws an exception, THEN THE AudioPreview SHALL dispose the controller, set `_audioPreview` to `null`, and return without crashing.

---

### Requirement 7: Regression — mute and unmute while playing

**User Story:** As a user, I want muting or unmuting an audio track while playing to take effect immediately without restarting the controller, so that the audio experience is seamless.

#### Acceptance Criteria

1. WHEN an audio track is muted while the audio controller is playing, THE AudioPreview SHALL set the controller volume to `0` without disposing or reinitialising the controller.
2. WHEN an audio track is unmuted while the audio controller is playing, THE AudioPreview SHALL restore the controller volume to the track's configured volume without disposing or reinitialising the controller.
3. WHEN a second audio track is added while the first is playing, THE AudioPreview SHALL continue playing the first non-muted track and SHALL NOT crash.
