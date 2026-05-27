import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_video_processor/src/compositor/video_overlay_item.dart';

void main() {
  group('VideoOverlayItem', () {
    test('isVisibleAt respects half-open endMs', () {
      const item = VideoOverlayItem(
        id: 'a',
        startMs: 1000,
        endMs: 2000,
        anchor: Offset(0.5, 0.5),
        child: SizedBox.shrink(),
      );
      expect(item.isVisibleAt(999), isFalse);
      expect(item.isVisibleAt(1000), isTrue);
      expect(item.isVisibleAt(1999), isTrue);
      expect(item.isVisibleAt(2000), isFalse);
    });
  });
}
