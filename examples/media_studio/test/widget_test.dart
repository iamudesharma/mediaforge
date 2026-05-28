import 'package:flutter_test/flutter_test.dart';
import 'package:media_studio/main.dart';

void main() {
  testWidgets('Media Studio app smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MediaStudioApp());

    // Verify that the title "Media Studio" is present.
    expect(find.text('Media Studio'), findsOneWidget);
  });
}
