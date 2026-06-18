import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_forge_editor/src/widgets/stories_tool_rail.dart';

void main() {
  testWidgets('StoriesToolRail shows all tool labels', (tester) async {
    StoriesTool? tapped;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StoriesToolRail(
            onToolSelected: (t) => tapped = t,
            hasMusic: true,
            soundMuted: true,
          ),
        ),
      ),
    );

    expect(find.text('Text'), findsOneWidget);
    expect(find.text('Music'), findsOneWidget);
    expect(find.text('Sound'), findsOneWidget);

    await tester.tap(find.text('Music'));
    await tester.pump();
    expect(tapped, StoriesTool.music);
  });
}
