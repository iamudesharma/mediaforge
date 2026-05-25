import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_image/src/editor/layout/mobile_tool_sheet.dart';
import 'package:rust_image/src/editor/panels/tool_panels.dart';

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
}
