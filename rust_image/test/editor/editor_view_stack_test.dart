import 'dart:typed_data';

import 'package:flutter/material.dart' hide ImageInfo;
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_image/src/editor/editor_screen.dart';
import 'package:rust_image/src/editor/widgets/live_preview.dart';
import 'package:rust_image/src/editor/widgets/editor_tool_rail.dart';
import 'package:rust_image/src/editor/editor_session.dart';
import 'package:rust_image/src/editor/layout/editor_layout.dart';
import 'package:rust_image/src/editor/models/layer_transform.dart';
import 'package:rust_image/src/editor/models/overlay_layer.dart';
import 'package:rust_image/src/editor/rust_image_editor_config.dart';
import 'package:rust_image/src/rust/api/image.dart';
import 'package:rust_image/src/rust_image_editor.dart';

void main() {
  testWidgets('RustImageEditorView mobile layout with image does not overflow', (tester) async {
    final session = EditorSession();
    final rgba = RgbaImageBuffer(
      width: 400,
      height: 300,
      pixels: Uint8List(400 * 300 * 4),
    );
    session
      ..imageInfo = const ImageInfo(width: 400, height: 300, format: 'jpeg')
      ..previewRgba = rgba
      ..useRgbaPreview = true
      ..sourceBytes = Uint8List(8)
      ..displayBytes = Uint8List(8);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: RustImageEditorView(
          config: const RustImageEditorConfig(
            title: 'Test',
            layoutMode: EditorLayoutMode.immersive,
          ),
          session: session,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    session.notifyLayerChanged();
    await tester.pump();
    session.notifyPreviewChanged();
    await tester.pump();

    // Open stickers tool (bottom nav).
    await tester.tap(find.text('Stickers'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    session.layerStack.add(
      EmojiLayer(
        id: 'e1',
        transform: const LayerTransform(centerX: 200, centerY: 150),
        glyph: '😀',
        fontSize: 48,
      ),
    );
    session.notifyLayerChanged();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('mobile tool sheet keeps preview visible without full-screen scrim', (tester) async {
    final session = EditorSession();
    session
      ..imageInfo = const ImageInfo(width: 400, height: 300, format: 'jpeg')
      ..sourceBytes = Uint8List(8)
      ..displayBytes = Uint8List(8);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: MediaQuery(
          data: const MediaQueryData(size: Size(390, 844)),
          child: RustImageEditorView(
            config: const RustImageEditorConfig(
              title: 'Test',
              layoutMode: EditorLayoutMode.immersive,
              showMobileMetaOverlay: true,
            ),
            session: session,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byKey(LivePreview.widgetKey), findsOneWidget);
    expect(find.text('Import'), findsOneWidget);

    await tester.tap(find.text('Filters'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(LivePreview.widgetKey), findsOneWidget);
    expect(find.text('Original'), findsOneWidget);

    await tester.tap(find.text('Filters'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Re-tap same tool collapses/expands sheet — preview still present.
    expect(find.byKey(LivePreview.widgetKey), findsOneWidget);

    await tester.tap(find.text('Adjust'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(find.byKey(LivePreview.widgetKey), findsOneWidget);
  });

  testWidgets('RustImageEditorView wide rail does not overflow with default tools', (tester) async {
    final session = EditorSession();
    session
      ..imageInfo = const ImageInfo(width: 400, height: 300, format: 'jpeg')
      ..sourceBytes = Uint8List(8)
      ..displayBytes = Uint8List(8);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: MediaQuery(
          data: const MediaQueryData(size: Size(1000, 640)),
          child: RustImageEditorView(
            config: const RustImageEditorConfig(
              title: 'Test',
              layoutMode: EditorLayoutMode.sidebar,
            ),
            session: session,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    expect(find.byKey(EditorToolRail.railKey), findsOneWidget);
  });
}
