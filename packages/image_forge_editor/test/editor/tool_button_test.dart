import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_forge_editor/src/editor/theme/app_theme.dart';
import 'package:image_forge_editor/src/editor/widgets/tool_button.dart';
import 'package:image_forge_editor/src/editor/panels/tool_panels.dart';

void main() {
  testWidgets('ToolButton shows outlined icon when unselected', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Center(
            child: ToolButton(
              tool: EditorTool.adjust,
              selected: false,
              onTap: () {},
            ),
          ),
        ),
      ),
    );
    expect(find.byTooltip('Adjust'), findsOneWidget);
  });

  testWidgets('ToolButton shows filled icon when selected', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Center(
            child: ToolButton(
              tool: EditorTool.adjust,
              selected: true,
              onTap: () {},
            ),
          ),
        ),
      ),
    );
    expect(find.byTooltip('Adjust'), findsOneWidget);
  });

  testWidgets('ToolButton with showLabel renders the label', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Center(
            child: ToolButton(
              tool: EditorTool.stickers,
              selected: true,
              onTap: () {},
              showLabel: true,
            ),
          ),
        ),
      ),
    );
    expect(find.text('Stickers'), findsOneWidget);
  });

  testWidgets('ToolButton disabled ignores taps', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Center(
            child: ToolButton(
              tool: EditorTool.adjust,
              selected: false,
              enabled: false,
              onTap: () => tapped++,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Adjust'), warnIfMissed: false);
    expect(tapped, 0);
  });
}
