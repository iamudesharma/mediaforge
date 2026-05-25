import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_image/src/editor/crop_controller.dart';
import 'package:rust_image/src/editor/editor_session.dart';
import 'package:rust_image/src/editor/panels/tool_panels.dart';

/// Mounts editor chrome for Crop + Filters without full FFI image load.
void main() {
  testWidgets('Transform panel shows IG aspect chips', (tester) async {
    final crop = CropController()..syncImageSize(1080, 1920);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TransformPanel(
              session: EditorSession(),
              crop: crop,
            ),
          ),
        ),
      ),
    );
    expect(find.text('4:5'), findsOneWidget);
    expect(find.text('9:16'), findsOneWidget);
    expect(find.text('Original'), findsOneWidget);
  });

  testWidgets('Filters panel shows intensity slider when preset selected', (tester) async {
    final session = EditorSession()
      ..sourceBytes = Uint8List.fromList([0, 1, 2, 3, 4, 5, 6, 7]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 400,
              height: 900,
              child: FiltersPanel(session: session),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Filter intensity'), findsNothing);
    await tester.tap(find.text('Neue'));
    await tester.pump();
    expect(find.text('Filter intensity'), findsOneWidget);
  });
}
