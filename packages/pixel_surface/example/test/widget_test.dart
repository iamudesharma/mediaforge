import 'package:flutter_test/flutter_test.dart';

import 'package:pixel_surface_example/main.dart';

void main() {
  testWidgets('GpuTextureDemo smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const GpuTextureDemoApp());
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(GpuTextureDemoApp), findsOneWidget);
  });
}
