import 'package:flutter_test/flutter_test.dart';
import 'package:video_forge_editor/src/editor/video_forge_editor_config.dart';
import 'package:video_forge_editor/src/models/video_export_result.dart';

void main() {
  test('VideoForgeEditorConfig defaults', () {
    const config = VideoForgeEditorConfig(
      initialVideoPath: '/tmp/sample.mp4',
    );
    expect(config.title, 'Video Studio');
    expect(config.previewMaxEdge, 1080);
    expect(config.showDiagnostics, false);
    expect(config.cacheSegment, 'video_forge_editor');
  });

  test('VideoExportResult holds export metadata', () {
    const result = VideoExportResult(
      outputPath: '/tmp/out.mp4',
      thumbPath: '/tmp/thumb.jpg',
      originalBytes: 1000,
      compressedBytes: 400,
      encodeDuration: Duration(seconds: 2),
    );
    expect(result.compressedBytes, 400);
  });
}
