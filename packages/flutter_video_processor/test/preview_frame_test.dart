import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_video_processor/src/runtime/preview_frame.dart';

void main() {
  test('PreviewFrame accepts presentedToSurface without pixels', () {
    const frame = PreviewFrame(
      ptsMs: 500,
      width: 1280,
      height: 720,
      presentedToSurface: true,
    );
    expect(frame.presentedToSurface, isTrue);
    expect(frame.rgba, isNull);
    expect(frame.pixelBufferPtr, isNull);
  });
}
