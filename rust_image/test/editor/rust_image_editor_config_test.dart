import 'package:flutter_test/flutter_test.dart';
import 'package:rust_image/rust_image.dart';

void main() {
  group('RustImageEditorConfig defaults', () {
    test('exposes the documented default values', () {
      const config = RustImageEditorConfig();

      expect(config.title, 'Lumina');
      expect(config.defaultBackend, ProcessingBackend.auto);
      expect(config.liveEditMaxEdge, 1280);
      expect(config.previewMaxEdge, 1280);
      expect(config.useRgbaPreview, isTrue);
      expect(config.showPerformanceInStatus, isTrue);
      expect(config.allowBlankCanvas, isTrue);
    });

    test('enables every tool by default', () {
      const config = RustImageEditorConfig();

      expect(config.enabledTools, hasLength(11));
      expect(config.enabledTools, contains(EditorTool.layers));
      expect(config.enabledTools.toSet(), EditorTool.values.toSet());
    });
  });

  group('EditorPipelineDefaults', () {
    test('matches the documented pipeline limits', () {
      expect(EditorPipelineDefaults.liveEditMaxEdge, 1280);
      expect(EditorPipelineDefaults.previewMaxEdge, 1280);
      expect(EditorPipelineDefaults.previewQuality, 82);
    });
  });
}
