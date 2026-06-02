import 'dart:typed_data';

import 'frb_generated/api.dart';
import 'frb_generated/types.dart';

/// PR #5: stable handle for a buffer the Rust pool owns. The Dart
/// side can hand the underlying `Uint8List` directly to a texture
/// (no copy), and when the parent [ReleaseToken] becomes
/// unreachable, a `Finalizer` returns the buffer to the Rust pool
/// via [bufferPoolReleaseByToken].
///
/// Why a token? The Rust buffer pool is a single shared
/// best-fit free list, so a "raw pointer" would be ambiguous —
/// the same `Vec<u8>` could be sitting in the pool or in
/// someone else's hand. A monotonically increasing token gives the
/// Rust side a stable identifier for telemetry and lets the
/// `Finalizer` fire-and-forget (the token is opaque to Dart, so
/// there's no risk of a misuse causing a wrong-pointer write).
///
/// Use via [ReleaseToken.fromBytes] or [ReleaseToken.fromPreview].
class ReleaseToken {
  ReleaseToken._(this._bytes, this._token);

  final Uint8List _bytes;
  final BigInt _token;

  BigInt get token => _token;

  /// Underlying buffer (zero-copy view into the Rust-owned data).
  Uint8List get bytes => _bytes;

  /// Build a `ReleaseToken` from a [Uint8List] + token. Prefer
  /// [fromPreview] in real code; this constructor exists for tests
  /// and for cases where the buffer comes from a non-preview path.
  factory ReleaseToken.fromBytes({required Uint8List bytes, required BigInt token}) {
    final t = ReleaseToken._(bytes, token);
    if (token != BigInt.zero) {
      _finalizer.attach(t, token, detach: t);
    }
    return t;
  }

  /// Build a `ReleaseToken` from a `PreviewFrameRgbaBuf`. The
  /// `rgba` field's underlying buffer is the Rust-owned data, so
  /// we hand it to the [Finalizer] directly.
  factory ReleaseToken.fromPreview(PreviewFrameRgbaBuf frame) {
    return ReleaseToken.fromBytes(
      bytes: frame.rgba,
      token: frame.releaseToken,
    );
  }

  /// Drop the token without releasing the buffer. After this, the
  /// buffer will be returned to the pool by the next call to
  /// [bufferPoolRelease] / [bufferPoolReleaseByToken] from the
  /// app, or when Rust drops its reference. Use when you want to
  /// keep the buffer alive past the `ReleaseToken`'s lifetime
  /// (e.g. hand it to a worker isolate).
  void detach() {
    _finalizer.detach(this);
  }
}

/// `Finalizer` callback. When the [ReleaseToken] is GC'd, this
/// fires and returns the buffer to the Rust pool. Errors are
/// intentionally swallowed (best-effort telemetry, not a
/// correctness path).
final Finalizer<BigInt> _finalizer = Finalizer((token) {
  try {
    bufferPoolReleaseByToken(token: token);
  } catch (_) {
    // Best-effort. Pool release is a no-op for token 0 anyway.
  }
});
