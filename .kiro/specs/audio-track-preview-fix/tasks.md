# Implementation Plan: Audio Track Preview Fix

## Overview

Three targeted changes to `_VideoCreatorFlowState` in `examples/media_studio/lib/video_creator_flow.dart` to eliminate the race condition that prevents `preview.play()` from being called when an audio track is added to the timeline.

## Tasks

- [ ] 1. Add `_audioStartInFlight` field and update `_startAudioPreview`
  - [ ] 1.1 Declare `_audioStartInFlight` boolean field alongside `_audioPreviewBusy`
    - Add `bool _audioStartInFlight = false;` immediately after the `bool _audioPreviewBusy = false;` field declaration in `_VideoCreatorFlowState`
    - _Requirements: 2.1, 2.2, 2.4_

  - [ ] 1.2 Set and clear `_audioStartInFlight` in `_startAudioPreview`
    - Set `_audioStartInFlight = true;` after `_audioPreviewBusy = true;` and before the `try` block
    - Add `_audioStartInFlight = false;` inside the existing `finally` block (alongside `_audioPreviewBusy = false;`)
    - _Requirements: 2.1, 2.2_

  - [ ]* 1.3 Write property test for `_audioStartInFlight` lifecycle (Property 4)
    - **Property 4: `_audioStartInFlight` accurately reflects execution state**
    - **Validates: Requirements 2.1, 2.2, 2.3**

- [ ] 2. Guard `_maintainAudioPreviewDriftInner` against in-flight start
  - [ ] 2.1 Add early-return guard before the re-entry block in `_maintainAudioPreviewDriftInner`
    - In the `if (preview == null || !_isSamePath(...) || !preview.value.isInitialized)` block, insert `if (_audioStartInFlight) return;` immediately before the existing `_audioPreviewBusy = false;` line
    - The existing `_audioPreviewBusy = false; await _startAudioPreview(); return;` lines remain unchanged after the guard
    - _Requirements: 2.3, 2.4, 2.5_

  - [ ]* 2.2 Write property test for drift path non-interference (Property 3)
    - **Property 3: Drift maintenance does not increment `_audioPreviewSyncGen`**
    - **Validates: Requirements 2.3, 2.5**

  - [ ]* 2.3 Write property test for audio always plays when conditions are met (Property 1)
    - **Property 1: Audio always plays when conditions are met**
    - **Validates: Requirements 1.1, 2.5, 2.6**

- [ ] 3. Checkpoint — verify fixes compile cleanly
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 4. Fix `dispose()` to use `unawaited`
  - [ ] 4.1 Wrap `_stopAudioPreview()` in `unawaited()` inside `dispose()`
    - Change `_stopAudioPreview();` to `unawaited(_stopAudioPreview());` in the `dispose()` method
    - `dart:async` is already imported; no new import needed
    - _Requirements: 3.1, 3.2_

- [ ] 5. Verification
  - [ ] 5.1 Run static analysis on the changed file
    - Run `dart run melos exec --scope=media_studio -- flutter analyze lib --no-fatal-infos --no-fatal-warnings` (or equivalent) and confirm zero new errors or warnings
    - Confirm the `unawaited_futures` lint is satisfied by the `dispose()` change
    - _Requirements: 3.1, 3.3_

  - [ ]* 5.2 Write unit tests for reentrancy guard (Property 2)
    - **Property 2: At most one audio controller initialization in flight**
    - **Validates: Requirements 1.2, 1.3, 2.1, 2.2**

- [ ] 6. Final checkpoint — Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- All three code changes are confined to a single file: `examples/media_studio/lib/video_creator_flow.dart`
- Fix 1 (tasks 1.1–1.2) must be applied before Fix 2 (task 2.1) because the guard reads `_audioStartInFlight`
- Fix 3 (task 4.1) is independent and can be applied in any order relative to Fixes 1 and 2
- Property tests reference the Correctness Properties section of the design document

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1"] },
    { "id": 1, "tasks": ["1.2"] },
    { "id": 2, "tasks": ["1.3", "2.1", "4.1"] },
    { "id": 3, "tasks": ["2.2", "2.3", "5.1"] },
    { "id": 4, "tasks": ["5.2"] }
  ]
}
```
