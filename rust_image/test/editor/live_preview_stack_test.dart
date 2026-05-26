import 'dart:typed_data';

import 'package:flutter/material.dart' hide ImageInfo;
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_image/src/editor/editor_session.dart';
import 'package:rust_image/src/editor/models/layer_transform.dart';
import 'package:rust_image/src/editor/models/overlay_layer.dart';
import 'package:rust_image/src/editor/widgets/live_preview.dart';
import 'package:rust_image/src/rust/api/image.dart';
import 'package:rust_image/src/rust_image_editor.dart';

void main() {
  testWidgets('LivePreview with layer editor and stickers does not overflow', (tester) async {
    final session = EditorSession();
    final rgba = RgbaImageBuffer(
      width: 200,
      height: 150,
      pixels: Uint8List(200 * 150 * 4),
    );
    session
      ..imageInfo = const ImageInfo(width: 200, height: 150, format: 'png')
      ..previewRgba = rgba
      ..useRgbaPreview = true
      ..layerStack.add(
        StickerLayer(
          id: 's1',
          transform: const LayerTransform(centerX: 100, centerY: 75),
          userBytes: Uint8List.fromList([0x89, 0x50, 0x4e, 0x47]), // invalid but non-empty
        ),
      );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 600,
            child: LivePreview(
              bytes: null,
              previewRgba: rgba,
              useRgbaPreview: true,
              compareBytes: null,
              showCompare: false,
              processing: false,
              layerStack: session.layerStack,
              showLayerOverlay: true,
              layerInteractionEnabled: true,
              paintMode: false,
              imageWidth: 200,
              imageHeight: 150,
              onLayerStackChanged: session.notifyLayerChanged,
              activePaintStrokeListenable: session.activePaintStrokeListenable,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
  });
}
