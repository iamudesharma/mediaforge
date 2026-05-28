import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_video_processor/src/timeline/timeline_controller.dart';

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
  });
}
