import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_video_processor_example/main.dart';

void main() {
  testWidgets('demo renders', (tester) async {
    await tester.pumpWidget(const VideoProcessorDemoApp());
    expect(find.text('Video Processor Demo'), findsOneWidget);
  });
}
