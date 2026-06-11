import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_forge_editor/src/editor/panels/tool_panels.dart';
import 'package:image_forge_editor/src/editor/theme/app_theme.dart';
import 'package:image_forge_editor/src/editor/widgets/inspector_panel.dart';

void main() {
  testWidgets('InspectorPanel renders header and tool name', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Row(
            children: [
              InspectorPanel(
                tool: EditorTool.adjust,
                child: const Text('adjust body'),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Adjust'), findsOneWidget);
    expect(find.text('adjust body'), findsOneWidget);
  });

  testWidgets('InspectorPanel cross-fades when tool changes', (tester) async {
    EditorTool tool = EditorTool.adjust;
    late StateSetter setter;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Row(
            children: [
              StatefulBuilder(
                builder: (context, setState) {
                  setter = setState;
                  return InspectorPanel(
                    tool: tool,
                    child: const Text('body'),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Adjust'), findsOneWidget);
    setter(() => tool = EditorTool.filters);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Filters'), findsOneWidget);
  });

  testWidgets('InspectorPanel Reset and Done buttons fire callbacks',
      (tester) async {
    var resetCount = 0;
    var doneCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Row(
            children: [
              InspectorPanel(
                tool: EditorTool.adjust,
                onReset: () => resetCount++,
                onDone: () => doneCount++,
                child: const Text('body'),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('Reset'));
    await tester.tap(find.text('Done'));
    expect(resetCount, 1);
    expect(doneCount, 1);
  });
}
