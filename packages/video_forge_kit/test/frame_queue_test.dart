import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_forge_kit/src/runtime/frame_queue.dart';
import 'package:video_forge_kit/src/runtime/preview_frame.dart';

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

    test('enqueuePlayback drops stale queued frames', () {
      final q = FrameQueue(maxDepth: 4);
      q.enqueue(_frame(100, 1));
      q.enqueue(_frame(200, 2));
      final r = q.enqueuePlayback(_frame(500, 3), minPtsMs: 400);
      expect(r.accepted, isTrue);
      expect(r.dropped.length, 2);
      expect(q.length, 1);
      expect(q.peekLatest()!.ptsMs, 500);
    });

    test('enqueuePlayback rejects incoming stale frame', () {
      final q = FrameQueue(maxDepth: 4);
      final r = q.enqueuePlayback(_frame(100, 1), minPtsMs: 500);
      expect(r.accepted, isFalse);
      expect(r.rejectedIncoming, isTrue);
      expect(q.isEmpty, isTrue);
    });

    test('enqueuePlayback latestOnlyWhenFull replaces queue', () {
      final q = FrameQueue(maxDepth: 2);
      q.enqueuePlayback(_frame(0, 1), minPtsMs: 0);
      q.enqueuePlayback(_frame(100, 2), minPtsMs: 0);
      final r = q.enqueuePlayback(_frame(300, 3), minPtsMs: 0);
      expect(r.dropped.length, 2);
      expect(q.length, 1);
      expect(q.peekLatest()!.ptsMs, 300);
    });

    test('takeLatestForPlayback returns dropped intermediates', () {
      final q = FrameQueue(maxDepth: 4);
      q.enqueue(_frame(0, 1));
      q.enqueue(_frame(100, 2));
      q.enqueue(_frame(200, 3));
      final snap = q.takeLatestForPlayback();
      expect(snap.dropped.length, 2);
      expect(snap.frame!.ptsMs, 200);
      expect(q.isEmpty, isTrue);
    });

    test('enqueuePlayback uses wall playhead for stale reject', () {
      final q = FrameQueue(maxDepth: 4);
      final r = q.enqueuePlayback(
        _frame(100, 1),
        minPtsMs: 0,
        wallPlayheadMs: 200,
      );
      expect(r.accepted, isFalse);
      expect(r.rejectedIncoming, isTrue);
    });

    test('enqueuePlayback flushes queue when behind wall playhead', () {
      final q = FrameQueue(maxDepth: 4);
      q.enqueuePlayback(_frame(100, 1), minPtsMs: 0, wallPlayheadMs: 100);
      final r = q.enqueuePlayback(
        _frame(250, 2),
        minPtsMs: 0,
        wallPlayheadMs: 400,
        driftCatchUpThresholdMs: 100,
      );
      expect(r.accepted, isTrue);
      expect(r.dropped.length, 1);
      expect(q.length, 1);
      expect(q.peekLatest()!.ptsMs, 250);
    });
  });
}
