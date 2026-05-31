import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_forge_editor/src/editor/editor_session.dart';
import 'package:image_forge_editor/src/editor/panels/blank_canvas_sheet.dart';
import 'package:image_forge_editor/src/editor/theme/app_theme.dart';

void main() {
  testWidgets('BlankCanvasSheet does not overflow in dialog constraints', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480, maxHeight: 640),
              child: BlankCanvasSheet(session: EditorSession()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Create blank canvas'), findsOneWidget);
  });
}
