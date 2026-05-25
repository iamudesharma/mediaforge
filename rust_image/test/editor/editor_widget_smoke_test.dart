import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_image/rust_image.dart';

/// Full FFI init is covered by [example/integration_test]; this only checks the
/// widget tree mounts (Rust init may log a content-hash warning if the plugin
/// dylib in the test runner cache is older than [frb_generated]).
void main() {
  testWidgets('RustImageEditorWidget mounts without stack overflow', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RustImageEditorWidget(
          config: const RustImageEditorConfig(title: 'Test'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(RustImageEditorWidget), findsOneWidget);
  });
}
