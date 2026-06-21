import 'package:flutter_test/flutter_test.dart';
import 'package:video_forge_kit/video_forge_kit.dart';
import 'package:video_forge_editor/src/utils/clip_transform_preview.dart';

void main() {
  test('ClipTransformPreview evaluates linear scale track', () {
    final effects = ClipEffectsKit.kenBurnsZoomIn(durationMs: 1000);
    final atMid = ClipTransformPreview.atMs(effects, 500);
    expect(atMid.scale, greaterThan(1.0));
    expect(atMid.scale, lessThan(1.35));
  });

  test('ClipEffectsKit.localTimelineMs clamps to clip duration', () {
    const clip = VideoTimelineClip(
      id: 'c1',
      sourcePath: '/v.mp4',
      sourceStartMs: 5000,
      sourceEndMs: 15000,
      timelineStartMs: 2000,
    );
    expect(ClipEffectsKit.localTimelineMs(clip, 0), 0);
    expect(ClipEffectsKit.localTimelineMs(clip, 5000), 3000);
    expect(ClipEffectsKit.localTimelineMs(clip, 20000), 10000);
  });
}
