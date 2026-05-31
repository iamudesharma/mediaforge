import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_forge_kit/src/compositor/video_overlay_item.dart';

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

    test('opacityAt applies fade in and out', () {
      const item = VideoOverlayItem(
        id: 'b',
        startMs: 0,
        endMs: 1000,
        anchor: Offset(0, 0),
        child: SizedBox.shrink(),
        fadeInMs: 200,
        fadeOutMs: 200,
      );
      expect(item.opacityAt(0), closeTo(0, 0.01));
      expect(item.opacityAt(100), closeTo(0.5, 0.05));
      expect(item.opacityAt(500), closeTo(1, 0.01));
      expect(item.opacityAt(900), closeTo(0.5, 0.05));
      expect(item.opacityAt(999), closeTo(0, 0.05));
    });
  });
}
