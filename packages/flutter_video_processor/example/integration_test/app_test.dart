import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flutter_video_processor_example/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('demo app smoke test', (tester) async {
    await tester.pumpWidget(const VideoProcessorDemoApp());
    await tester.pumpAndSettle();
    expect(find.text('Video Processor Demo'), findsOneWidget);
    expect(find.text('Pick video (MP4, MOV, …)'), findsOneWidget);
  });
}
