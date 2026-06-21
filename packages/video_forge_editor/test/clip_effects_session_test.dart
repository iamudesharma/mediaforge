import 'package:flutter_test/flutter_test.dart';
import 'package:video_forge_editor/src/services/clip_effects_session.dart';
import 'package:video_forge_kit/video_forge_kit.dart';

void main() {
  test('ClipEffectsSession preview defers timeline commit', () async {
    final timeline = TimelineController();
    timeline.loadPrimaryVideo(sourcePath: '/v.mp4', durationMs: 5000);
    var commitCount = 0;
    final session = ClipEffectsSession(
      timeline: timeline,
      onCommitted: () => commitCount++,
    );
    addTearDown(session.dispose);

    final fx = ClipEffectsKit.copyWithBase(
      ClipEffectsKit.identity(),
      scale: 1.8,
    );
    session.previewEffects('clip_0', fx);
    expect(session.isLiveEditing, isTrue);
    expect(ClipEffectsKit.forClip(timeline.videoClips.first).base.scale, 1.0);
    expect(session.effectsForClip(timeline.videoClips.first).base.scale, 1.8);

    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(commitCount, 1);
    expect(ClipEffectsKit.forClip(timeline.videoClips.first).base.scale, 1.8);
    expect(session.isLiveEditing, isFalse);
  });

  test('ClipEffectsSession commitNow writes immediately', () {
    final timeline = TimelineController();
    timeline.loadPrimaryVideo(sourcePath: '/v.mp4', durationMs: 5000);
    final session = ClipEffectsSession(timeline: timeline);
    addTearDown(session.dispose);

    session.commitNow(
      'clip_0',
      ClipEffectsKit.withSpeed(ClipEffectsKit.identity(), 2.0),
    );
    expect(ClipEffectsKit.forClip(timeline.videoClips.first).speed, 2.0);
  });
}
