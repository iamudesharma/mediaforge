import 'dart:typed_data';

import 'package:flutter/material.dart' hide ImageInfo;
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_image/src/editor/draw_placement.dart';
import 'package:rust_image/src/editor/models/layer_stack.dart';
import 'package:rust_image/src/editor/widgets/live_preview.dart';
import 'package:rust_image/src/rust/api/image.dart';
import 'package:rust_image/src/rust_image_editor.dart';

void main() {
  testWidgets(
    'placement ListenableBuilder survives TransformationController updates',
    (tester) async {
      final placement = DrawPlacementController();
      placement.syncImageSize(400, 300);
      final rgba = RgbaImageBuffer(
        width: 400,
        height: 300,
        pixels: Uint8List(400 * 300 * 4),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 800,
              child: LivePreview(
                bytes: null,
                previewRgba: rgba,
                useRgbaPreview: true,
                compareBytes: null,
                showCompare: false,
                processing: false,
                placement: placement,
                layerStack: LayerStack(),
                showLayerOverlay: true,
                layerInteractionEnabled: true,
                paintMode: false,
                imageWidth: 400,
                imageHeight: 300,
                onLayerStackChanged: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final viewer = find.byType(InteractiveViewer);
      expect(viewer, findsOneWidget);
      final center = tester.getCenter(viewer);

      // Pan/zoom updates [TransformationController] — must not nest overlays.
      for (var i = 0; i < 25; i++) {
        await tester.drag(viewer, Offset(8.0 * (i % 5), 6.0 * (i % 7)), warnIfMissed: false);
        await tester.pump();
      }
      await tester.tapAt(center);
      await tester.pump();

      expect(find.byType(LivePreview), findsOneWidget);
    },
  );
}
