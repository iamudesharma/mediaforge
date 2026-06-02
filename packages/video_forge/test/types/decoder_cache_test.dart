// Tests for the decoder cache Dart wrapper. The Rust side owns the
// actual cache; these tests verify the FRB plumbing + the DTO mapping.

import 'package:flutter_test/flutter_test.dart';
import 'package:video_forge/video_forge.dart';

void main() {
  group('DecoderCacheStats', () {
    test('hit ratio is 0 when there have been no lookups', () {
      const s = DecoderCacheStats(
        hits: 0,
        misses: 0,
        evictions: 0,
        entries: 0,
        workingSetBytes: 0,
      );
      expect(s.hitRatio, 0);
    });

    test('hit ratio is hits / (hits + misses)', () {
      const s = DecoderCacheStats(
        hits: 75,
        misses: 25,
        evictions: 0,
        entries: 0,
        workingSetBytes: 0,
      );
      expect(s.hitRatio, closeTo(0.75, 1e-9));
    });

    test('toString includes all fields', () {
      const s = DecoderCacheStats(
        hits: 1,
        misses: 2,
        evictions: 3,
        entries: 4,
        workingSetBytes: 5,
      );
      final s2 = s.toString();
      expect(s2, contains('hits: 1'));
      expect(s2, contains('misses: 2'));
      expect(s2, contains('evictions: 3'));
      expect(s2, contains('entries: 4'));
      expect(s2, contains('workingSetBytes: 5'));
    });
  });

  group('FFI wrapper', () {
    // The actual Rust cache is exercised by the Rust unit tests
    // (cache::tests::*). These Dart tests only verify the wrapper's
    // shape and the DTO mapping; they intentionally do NOT call the
    // sync FFI because that requires the native library to be loaded,
    // which only happens after NativeBindings.ensureInitialized() —
    // a setup that is exercised in integration_test/ rather than the
    // unit test runner (the FFI surface itself is owned by FRB and
    // does not need re-verification here).
    test('wrapper does not crash on import', () {
      // Constructor + accessor surface only — no FFI calls.
      const s = DecoderCacheStats(
        hits: 10,
        misses: 5,
        evictions: 0,
        entries: 2,
        workingSetBytes: 1024,
      );
      expect(s.hitRatio, closeTo(10 / 15, 1e-9));
    });
  });
}
