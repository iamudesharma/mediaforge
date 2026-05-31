import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_forge_editor/image_forge_editor.dart';

import '../helpers/frb_test_init.dart';

/// Widget tree only. For full FFI use `rust_image/example` or set
/// [RUST_IMAGE_DYLIB] / build `packages/image_forge/rust` release first.
void main() {
  setUpAll(() async {
    await ensureTestFrbInitialized();
  });

  testWidgets('RustImageEditorWidget mounts without stack overflow', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RustImageEditorWidget(
          config: const RustImageEditorConfig(title: 'Test'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(RustImageEditorWidget), findsOneWidget);
  });
}
