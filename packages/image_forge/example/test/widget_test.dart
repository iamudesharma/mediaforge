import 'package:flutter_test/flutter_test.dart';
import 'package:image_forge_example/main.dart';

void main() {
  testWidgets('shows pipeline button', (tester) async {
    await tester.pumpWidget(const CoreFilterDemoApp());
    expect(find.text('Run RGBA filter + export'), findsOneWidget);
  });
}
