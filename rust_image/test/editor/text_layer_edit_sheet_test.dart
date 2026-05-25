import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_image/src/editor/editor_session.dart';
import 'package:rust_image/src/editor/models/layer_stack.dart';
import 'package:rust_image/src/editor/models/layer_transform.dart';
import 'package:rust_image/src/editor/models/overlay_layer.dart';
import 'package:rust_image/src/editor/panels/text_layer_edit_sheet.dart';

void main() {
  testWidgets('TextLayerEditSheet apply updates layer text and style', (tester) async {
    final session = EditorSession();
    final layer = TextLayer(
      id: 't1',
      transform: const LayerTransform(),
      text: 'Hello',
      fontSize: 32,
      color: Colors.white,
    );
    session.layerStack.add(layer);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TextLayerEditSheet(session: session, layer: layer),
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'Updated caption');
    await tester.pump();
    await tester.pump();
    var updated = session.layerStack.layers.whereType<TextLayer>().first;
    expect(updated.text, 'Updated caption');

    await tester.ensureVisible(find.text('Done'));
    await tester.pump();
    await tester.tap(find.text('Done'));
    await tester.pump();

    updated = session.layerStack.layers.whereType<TextLayer>().first;
    expect(updated.text, 'Updated caption');
  });
}
