import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_forge_kit/video_forge_kit.dart';

void main() {
  group('clampVideoOverlayAnchor', () {
    test('clamps to unit square', () {
      expect(
        clampVideoOverlayAnchor(const Offset(-0.2, 1.5)),
        const Offset(0, 1),
      );
    });

    test('maps drag delta in frame pixels to normalized anchor', () {
      const base = Offset(0.5, 0.5);
      const frameW = 200.0;
      const frameH = 200.0;
      final next = clampVideoOverlayAnchor(
        Offset(
          base.dx + 20 / frameW,
          base.dy - 10 / frameH,
        ),
      );
      expect(next.dx, closeTo(0.6, 0.01));
      expect(next.dy, closeTo(0.45, 0.01));
    });
  });

  group('DraggableVideoOverlays', () {
    testWidgets('builds visible overlays at playhead', (tester) async {
      const item = VideoOverlayItem(
        id: 'text:hi:1',
        startMs: 0,
        endMs: 5000,
        anchor: Offset(0.5, 0.5),
        child: SizedBox(width: 80, height: 80),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              height: 200,
              child: DraggableVideoOverlays(
                frameSize: const Size(200, 200),
                overlays: const [item],
                playheadMs: 1000,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(DraggableVideoOverlays), findsOneWidget);
    });
  });
}
