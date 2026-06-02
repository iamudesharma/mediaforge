## 2.1.0

### Performance
- **Demuxer/decoder LRU cache** (default-on). Repeated `thumbnail`,
  `batch_thumbnails`, and `decodePreviewFrameRgba` calls on the same
  input now reuse the open `AVFormatContext` and decoder. The default
  config keeps 4 entries with a 30 s idle TTL and a ~256 MB working-set
  cap. The cache is a no-op when disabled via
  `setDecoderCacheConfig(disabled)`. Use `clearDecoderCache()` from Dart
  in low-memory warnings or when a project is closed.
- **`wait_for_job` no longer polls.** The 50 ms `std::thread::sleep`
  poll in `JobRegistry::wait_result` was replaced with a per-record
  `parking_lot::Condvar`; `complete` now calls `notify_all` so waiters
  wake in single-digit ms instead of up to 50 ms. Tested with a
  `wait_result_wakes_immediately_on_complete` regression that asserts
  < 100 ms (CI budget for scheduling jitter).

### Public API
- `clearDecoderCache() -> int` (sync FFI; was `#[frb(sync)]`).
- `decoderCacheStats() -> DecoderCacheStatsDto` (sync FFI; new struct).
- Dart-side helpers `readDecoderCacheStats()` and `dropDecoderCache()`
  in `lib/src/decoder_cache.dart` (re-exported from
  `package:video_forge/video_forge.dart`).

### Tests
- 5 new `cache::tests::*` unit tests (LRU key normalization, stats,
  clear, config).
- 4 new `jobs::registry::tests::*` unit tests (immediate wake, not
  found, timeout, active count).
- 4 new `DecoderCacheStats` Dart tests (hit ratio math, toString,
  wrapper shape).

## 2.2.0

### Thumbnail reliability on non-keyframes
- **Two-tier seek** in `decode_one_segmented_target`:
  `seek_stream_two_tier` first tries `AVSEEK_FLAG_BACKWARD` (current
  behavior), then falls back to `AVSEEK_FLAG_ANY` for the exact PTS
  before erroring out. The previous "retry from seek_ms=0" path is
  now a third-tier fallback for the rare case where both seeks fail.
- **Graceful-degrade replaces the silent "use last frame for every
  missing target" fill.** New `DecodeStatus` (Exact / NearestKeyframe
  / Failed) per `BatchTarget`, surfaced in the new
  `BatchThumbnailResult.decodedStatus` and
  `BatchThumbnailBytesResult.decodedStatus` fields. Only targets whose
  `positionMs > lastDecodedPts` are filled; the rest remain `Exact`.
  Each affected target now logs a `warn!` so users can grep for the
  fallback in production.
- **Parallel batch decode** (opt-in, feature flag). New
  `BatchThumbnailOptions.parallelDecoderCount` /
  `BatchThumbnailBytesOptions.parallelDecoderCount` field. 0 (default)
  = single-demuxer (current behavior). `Some(n > 0)` opens up to `n`
  parallel demuxer instances. Useful for long-GOP iPhone HEVC
  filmstrip batches where the demuxer open + first-frame decode is
  the bottleneck. (Implementation is a no-op wrapper for now; the
  parallel-shard decoder lands in a follow-up PR — the field is added
  so consumers can wire it without a breaking change later.)

### Public API
- New enum `ThumbnailDecodeStatus { exact, nearestKeyframe }`.
- `BatchThumbnailResult` gains `decodedStatus: List<ThumbnailDecodeStatus>`.
- `BatchThumbnailBytesResult` gains the same field.
- `BatchThumbnailOptions` + `BatchThumbnailBytesOptions` gain
  `parallelDecoderCount: Option<u8>`.

### Internal
- New helpers `seek_stream_any` + `seek_stream_two_tier` +
  `SeekOutcome` enum in `ffmpeg::thumbnail_seek`.
- `fill_remaining_targets_with_nearest_keyframe` replaces
  `fill_remaining_targets_from_last_rgb`.
- `frame_pts_ms` defensive against a zero time_base (no NaN).

### Tests
- 4 new `pipeline::thumbnail::tests::*` unit tests (graceful-degrade
  only fills past-PTS targets, no-fill when all matched, DTO mapping,
  zero time_base).
- 4 new `ffmpeg::thumbnail_seek::tests::*` (ms_to_stream_ts basic,
  zero time_base, microsecond scale, SeekOutcome equality).
- 3 new `data_classes_test.dart` cases (decoded_status round-trip,
  ThumbnailDecodeStatus variants, equality with mixed statuses).

## 2.0.0

### Breaking
- **Renamed `VideoProcessorError` → `VideoForgeError`** to match the package name.
  Affected classes (also renamed): `VideoProcessorError_*` → `VideoForgeError_*`.
  One-release shim: a `pub type VideoProcessorError = VideoForgeError;` is kept
  in Rust and a `typedef VideoProcessorError = VideoForgeError;` in Dart
  (imported via `package:video_forge/video_forge.dart`); both emit
  deprecation warnings and will be removed in 2.1.0.

### Cleanup / packaging
- Removed stale `android/src/main/jniLibs/arm64-v8a/libvideo_processor_core.so`
  (leftover from the pre-1.0 `video_processor_core` package).
- Removed stale IDE module files (`flutter_video_processor_android.iml`,
  `melos_video_processor_core_example.iml`).
- Added `target/` and `build/` to the package `.gitignore`.
- iOS framework `CFBundleIdentifier` switched to reverse-DNS
  `dev.iamudesharma.video_forge` (was `dev.video_forge`, which clashed with
  the macOS framework when both were linked into the same app).
- macOS Flutter `CodeAsset` hook now **fails the build** when `cargo build`
  cannot produce the cdylib, instead of silently producing no asset and
  leaving the user to discover the failure at runtime.
- `NativeLibraryLoader` collapses the 13 candidate search paths into 3
  ordered tiers and logs which one matched (`[NativeLibraryLoader] matched=`).
  Final error message now includes the last concrete exception per tier.

### CI / tests
- Added a `flutter test test/` step for `video_forge` in both
  `test_all.sh` and `.github/workflows/ci.yml` (was previously
  covered only for `video_forge_kit`).

## 1.0.0

- **Renamed from `video_processor_core` to `video_forge`** — a proper pub.dev package name.
- Initial pub.dev release: Rust video processing engine for Flutter.
- FFmpeg-based compress, transcode, thumbnails, audio mixing.
- FRB bindings for all Rust APIs. Zero Flutter-package dependencies.
- Breaking change: package import path changed from `package:video_processor_core` to `package:video_forge`.

## 0.2.0

- Split from monolithic `video_forge_kit` as engine-only package (FRB + FFmpeg hook).
- Android hook: stop preferring stale `android/src/main/jniLibs` (fixes FRB content-hash mismatch vs Dart).
- `decodePreviewFrameRgba` — single-frame RGBA preview decode for texture upload (Sprint V1.1).
- `decodePreviewFramePixelBuffer` / `releasePreviewPixelBuffer` — Apple VideoToolbox → BGRA `CVPixelBuffer` (Sprint V1.4).

## 0.1.0

- Initial release as part of `video_forge_kit` monolith.
