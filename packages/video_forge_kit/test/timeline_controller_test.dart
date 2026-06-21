import 'package:flutter_test/flutter_test.dart';
import 'package:video_forge_kit/src/models/clip_effects.dart';
import 'package:video_forge_kit/src/timeline/timeline_controller.dart';
import 'package:video_forge/video_forge.dart';

void main() {
  group('TimelineController', () {
    late TimelineController controller;

    setUp(() {
      controller = TimelineController();
      controller.loadPrimaryVideo(sourcePath: '/v.mp4', durationMs: 60_000);
    });

    test('splitVideoAt creates two adjacent clips', () {
      expect(controller.videoClips.length, 1);
      final ok = controller.splitVideoAt(20_000);
      expect(ok, isTrue);
      expect(controller.videoClips.length, 2);
      expect(controller.videoClips[0].durationMs, 20_000);
      expect(controller.videoClips[1].durationMs, 40_000);
      expect(controller.videoClips[0].sourceEndMs, 20_000);
      expect(controller.videoClips[1].sourceStartMs, 20_000);
    });

    test('mergeWithNext combines contiguous clips', () {
      controller.splitVideoAt(15_000);
      final left = controller.videoClips.first.id;
      expect(controller.mergeWithNext(left), isTrue);
      expect(controller.videoClips.length, 1);
      expect(controller.videoClips.first.durationMs, 60_000);
    });

    test('seekTargetAt maps timeline to source', () {
      controller.splitVideoAt(10_000);
      final target = controller.seekTargetAt(25_000);
      expect(target, isNotNull);
      expect(target!.sourceMs, 25_000);
      expect(target.sourcePath, '/v.mp4');
    });

    test('exportRangeForPrimarySource spans all clips', () {
      controller.splitVideoAt(20_000);
      final range = controller.exportRangeForPrimarySource();
      expect(range, isNotNull);
      expect(range!.startMs, 0);
      expect(range.endMs, 60_000);
    });

    test('audio clip does not extend timeline duration', () {
      expect(controller.durationMs, 60_000);
      controller.addAudioClip(
        sourcePath: '/song.mp3',
        sourceDurationMs: 180_000,
        videoDurationMs: 60_000,
      );
      expect(controller.durationMs, 60_000);
      final audio = controller.audioClips.single;
      expect(audio.durationMs, 60_000);
      expect(audio.timelineStartMs + audio.durationMs, lessThanOrEqualTo(60_000));
    });

    test('updateVideoClip stores per-clip effects independently', () {
      controller.splitVideoAt(30_000);
      final left = controller.videoClips[0];
      final right = controller.videoClips[1];
      final zoomed = ClipEffectsKit.copyWithBase(
        ClipEffectsKit.identity(),
        scale: 2.0,
      );
      controller.updateVideoClip(left.copyWith(effects: zoomed));
      expect(ClipEffectsKit.forClip(controller.videoClips[0]).base.scale, 2.0);
      expect(ClipEffectsKit.forClip(controller.videoClips[1]).base.scale, 1.0);
      expect(right.id, isNot(left.id));
    });

    test('updateVideoClipEffects does not relayout timeline offsets', () {
      controller.splitVideoAt(30_000);
      final before = controller.videoClips.map((c) => c.timelineStartMs).toList();
      final fx = ClipEffectsKit.copyWithBase(
        ClipEffectsKit.identity(),
        scale: 1.5,
      );
      controller.updateVideoClipEffects(controller.videoClips[0].id, fx);
      final after = controller.videoClips.map((c) => c.timelineStartMs).toList();
      expect(after, before);
      expect(ClipEffectsKit.forClip(controller.videoClips[0]).base.scale, 1.5);
    });

    test('updateAudioClip enforces timeline_start + duration <= video', () {
      final clip = controller.addAudioClip(
        sourcePath: '/song.mp3',
        sourceDurationMs: 120_000,
        timelineStartMs: 50_000,
        videoDurationMs: 60_000,
      );
      controller.updateAudioClip(clip.copyWith(timelineStartMs: 55_000));
      final updated = controller.audioClips.single;
      expect(updated.timelineStartMs + updated.durationMs, lessThanOrEqualTo(60_000));
    });
  });
}
