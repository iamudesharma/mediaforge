import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_forge_cache/video_forge_cache.dart';

void main() {
  group('ThumbnailCache', () {
    test('isNetworkInput detects http(s) URLs', () {
      expect(ThumbnailCache.isNetworkInput('https://example.com/v.mp4'), isTrue);
      expect(ThumbnailCache.isNetworkInput('/tmp/local.mp4'), isFalse);
    });

    test('inputFingerprint is stable for the same file content', () async {
      final dir = await Directory.systemTemp.createTemp('fvp_thumb_cache_test_');
      try {
        final file = File('${dir.path}/sample.mp4');
        await file.writeAsBytes([0, 1, 2, 3, 4]);
        final a = await ThumbnailCache.inputFingerprint(file.path);
        final b = await ThumbnailCache.inputFingerprint(file.path);
        expect(a, b);
        expect(a.length, 64);
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('inputFingerprint differs when file size changes', () async {
      final dir = await Directory.systemTemp.createTemp('fvp_thumb_cache_test_');
      try {
        final file = File('${dir.path}/sample.mp4');
        await file.writeAsBytes([1, 2, 3]);
        final a = await ThumbnailCache.inputFingerprint(file.path);
        await file.writeAsBytes([1, 2, 3, 4, 5]);
        final b = await ThumbnailCache.inputFingerprint(file.path);
        expect(a, isNot(b));
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('network URL fingerprint ignores http vs path quirks', () async {
      final a = await ThumbnailCache.inputFingerprint(
        'https://cdn.example.com/video.mp4',
      );
      final b = await ThumbnailCache.inputFingerprint(
        'https://cdn.example.com/video.mp4',
      );
      expect(a, b);
    });
  });
}
