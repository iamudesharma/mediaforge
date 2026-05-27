import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_video_processor/flutter_video_processor.dart';

void main() {
  test('MediaRuntime exposes texture availability flag', () {
    expect(MediaRuntime.isTexturePreviewAvailable, isA<bool>());
  });

  test('VideoTexturePool default handle', () {
    expect(VideoTexturePool.defaultHandle, 9001);
  });
}
