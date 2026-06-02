// PR #5: tests for [ReleaseToken] and the
// `bufferPoolAcquireWithToken` / `bufferPoolReleaseByToken` FFI
// exports.
//
// These tests are pure-Dart (no native decoding). They verify
// the construction / detach / zero-token contract of
// [ReleaseToken]. The FFI surface itself is exercised manually
// in the example app and in the kit integration tests — the
// pure-Dart VM has no `dylib` to load so the FFI calls would
// fail `RustLib.init()`.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_forge/video_forge.dart';

void main() {
  group('ReleaseToken', () {
    test('fromBytes constructs without error', () {
      final raw = Uint8List(32);
      final tok = ReleaseToken.fromBytes(bytes: raw, token: BigInt.one);
      expect(tok.token, BigInt.one);
      expect(tok.bytes.length, 32);
    });

    test('detach is safe to call and is idempotent', () {
      final tok = ReleaseToken.fromBytes(
        bytes: Uint8List(16),
        token: BigInt.two,
      );
      expect(() => tok.detach(), returnsNormally);
      expect(() => tok.detach(), returnsNormally);
    });

    test('zero token does not attach a Finalizer (no error)', () {
      // The Finalizer is intentionally not attached when the
      // token is 0 (reserved for "no token") to avoid
      // best-effort-release spam on tokens we never gave a real
      // meaning to.
      final tok = ReleaseToken.fromBytes(
        bytes: Uint8List(8),
        token: BigInt.zero,
      );
      expect(tok.token, BigInt.zero);
    });
  });
}
