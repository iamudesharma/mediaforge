import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_video_processor/flutter_video_processor.dart';

void main() {
  test('VideoOverlayItem.text carries textSpec and rebuilds child', () {
    const style = VideoTextOverlayStyle(
      fontSize: 24,
      color: Colors.red,
      maxWidth: 200,
    );
    final item = VideoOverlayItem.text(
      id: 'text:Hello:1',
      startMs: 0,
      endMs: 1000,
      anchor: Offset.zero,
      label: 'Hello',
      style: style,
    );
    expect(item.textSpec?.label, 'Hello');
    expect(item.textSpec?.style.fontSize, 24);
    expect(item.isTextOverlay, isTrue);

    final updated = item.withTextSpec(
      const VideoTextOverlaySpec(
        label: 'Hi',
        style: VideoTextOverlayStyle(fontSize: 40),
      ),
    );
    expect(updated.textSpec?.label, 'Hi');
    expect(updated.child, isA<VideoTextOverlayContent>());
  });

  test('resolvedTextSpec parses legacy id', () {
    const legacy = VideoOverlayItem(
      id: 'text:Legacy:99',
      startMs: 0,
      endMs: 1000,
      anchor: Offset.zero,
      child: SizedBox.shrink(),
    );
    expect(legacy.resolvedTextSpec?.label, 'Legacy');
  });
}
