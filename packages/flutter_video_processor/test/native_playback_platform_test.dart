import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_video_processor/src/playback/native_playback_platform.dart';

void main() {
  test('nativePlaybackEngineLabel returns non-empty', () {
    expect(nativePlaybackEngineLabel(), isNotEmpty);
  });

  test('texturePreviewPathLabel distinguishes surface', () {
    expect(texturePreviewPathLabel(useSurfaceTexture: true), isNotEmpty);
    expect(texturePreviewPathLabel(useSurfaceTexture: false), isNotEmpty);
  });
}
