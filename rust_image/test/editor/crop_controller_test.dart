import 'package:flutter_test/flutter_test.dart';
import 'package:rust_image/src/editor/crop_controller.dart';

void main() {
  test('applyAspect story 9:16 centers crop', () {
    final c = CropController();
    c.syncImageSize(1080, 1920);
    c.setAspect(CropAspect.story9x16);
    expect(c.cropW, 1080);
    expect(c.cropH, 1920);
    expect(c.cropX, 0);
    expect(c.cropY, 0);
  });

  test('applyAspect portrait 4:5', () {
    final c = CropController();
    c.syncImageSize(1080, 1350);
    c.setAspect(CropAspect.portrait4x5);
    expect(c.cropW, 1080);
    expect(c.cropH, 1350);
  });

  test('original uses full image', () {
    final c = CropController();
    c.syncImageSize(800, 600);
    c.setAspect(CropAspect.original);
    expect(c.cropW, 800);
    expect(c.cropH, 600);
  });
}
