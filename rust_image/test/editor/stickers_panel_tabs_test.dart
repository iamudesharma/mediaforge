import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_image/src/editor/editor_session.dart';
import 'package:rust_image/src/editor/panels/stickers_panel.dart';

void main() {
  testWidgets('StickersPanel desktop tab row updates tab index', (tester) async {
    final session = EditorSession();
    var tab = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: StickersPanel(
              session: session,
              tabIndex: tab,
              onTabChanged: (i) => tab = i,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Stickers'), findsWidgets);
    await tester.tap(find.text('Text').last);
    await tester.pump();
    expect(tab, 2);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: StickersPanel(
              session: session,
              tabIndex: tab,
              onTabChanged: (i) => tab = i,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Caption'), findsOneWidget);
  });
}
