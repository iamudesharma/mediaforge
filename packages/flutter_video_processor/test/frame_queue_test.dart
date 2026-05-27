import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_video_processor/src/runtime/frame_queue.dart';
import 'package:flutter_video_processor/src/runtime/preview_frame.dart';

PreviewFrame _frame(int pts, int id) => PreviewFrame(
      ptsMs: pts,
      width: 2,
      height: 2,
      rgba: Uint8List.fromList([id, id, id, 255]),
    );

void main() {
  group('FrameQueue', () {
    test('drops oldest when at max depth', () {
      final q = FrameQueue(maxDepth: 3);
      q.enqueue(_frame(0, 1));
      q.enqueue(_frame(100, 2));
      q.enqueue(_frame(200, 3));
      expect(q.length, 3);

      q.enqueue(_frame(300, 4));
      expect(q.length, 3);
      expect(q.takeOldest()!.ptsMs, 100);
      expect(q.peekLatest()!.ptsMs, 300);
    });

    test('flush clears queue', () {
      final q = FrameQueue();
      q.enqueue(_frame(0, 1));
      q.flush();
      expect(q.isEmpty, isTrue);
      expect(q.peekLatest(), isNull);
    });

    test('minPtsMs rejects stale frames', () {
      final q = FrameQueue(maxDepth: 3);
      q.enqueue(_frame(500, 1), minPtsMs: 400);
      expect(q.length, 1);
      q.enqueue(_frame(300, 2), minPtsMs: 400);
      expect(q.length, 1);
      expect(q.peekLatest()!.ptsMs, 500);
    });

    test('takeLatest drains newest only', () {
      final q = FrameQueue();
      q.enqueue(_frame(0, 1));
      q.enqueue(_frame(100, 2));
      final latest = q.takeLatest();
      expect(latest!.ptsMs, 100);
      expect(q.length, 1);
      expect(q.peekLatest()!.ptsMs, 0);
    });
  });
}
