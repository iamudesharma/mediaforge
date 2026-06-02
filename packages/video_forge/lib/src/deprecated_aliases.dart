// Deprecated Dart-side alias for the renamed error type.
//
// The Rust enum was renamed from `VideoProcessorError` to `VideoForgeError`
// in `video_forge` 2.0.0 (the new name matches the package). The generated
// `VideoForgeError` and its `VideoForgeError_*` variant classes are now
// the canonical names. This file keeps a one-release shim so apps that
// still match on `VideoProcessorError` keep compiling with a deprecation
// warning. The Rust-side `pub type VideoProcessorError` alias will be
// removed in 2.1.0 and this file will be deleted at the same time.
//
// New code: import `package:video_forge/video_forge.dart` and use
// `VideoForgeError` / `VideoForgeError_*` directly.

// ignore_for_file: deprecated_member_use_from_same_package, lines_longer_than_80_chars

import 'frb_generated/error.dart';

/// Deprecated alias for [VideoForgeError]. Will be removed in 2.1.0.
@Deprecated(
  'Use VideoForgeError instead. The package and its types are now named '
  'video_forge / VideoForgeError. This alias will be removed in 2.1.0.',
)
typedef VideoProcessorError = VideoForgeError;
