import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_forge_editor/src/editor/editor_session.dart';
import 'package:image_forge_editor/src/editor/layout/mobile_tool_sheet.dart';
import 'package:image_forge_editor/src/editor/models/layer_transform.dart';
import 'package:image_forge_editor/src/editor/models/overlay_layer.dart';
import 'package:image_forge_editor/src/editor/panels/layers_panel.dart';
import 'package:image_forge_editor/src/editor/panels/tool_panels.dart';

void main() {
  testWidgets('MobileToolSheet scrolls panel body independently of sheet drag', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: MediaQuery(
          data: const MediaQueryData(size: Size(390, 700)),
          child: SizedBox(
            height: 280,
            child: MobileToolSheet(
              tool: EditorTool.stickers,
              onClose: () {},
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < 20; i++)
                    SizedBox(
                      height: 48,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Panel row $i'),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final scrollable = find.descendant(
      of: find.byType(MobileToolSheet),
      matching: find.byType(Scrollable),
    );
    expect(scrollable, findsOneWidget);

    final before = tester.getTopLeft(find.text('Panel row 0')).dy;
    await tester.drag(scrollable, const Offset(0, -160));
    await tester.pumpAndSettle();
    final after = tester.getTopLeft(find.text('Panel row 0')).dy;
    expect(after, lessThan(before));
  });

  testWidgets('MobileToolSheet fits compact LayersPanel at peek height', (tester) async {
    final session = EditorSession();
    for (var i = 0; i < 4; i++) {
      session.layerStack.add(
        EmojiLayer(
          id: 'e$i',
          transform: const LayerTransform(centerX: 100, centerY: 100),
          glyph: '🙂',
        ),
        select: false,
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: MediaQuery(
          data: const MediaQueryData(size: Size(390, 700)),
          child: SizedBox(
            height: 238,
            child: MobileToolSheet(
              tool: EditorTool.layers,
              onClose: () {},
              child: LayersPanel(session: session, compact: true),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Duplicate', skipOffstage: false), findsNothing);
    expect(find.byTooltip('Duplicate'), findsOneWidget);
  });
}
