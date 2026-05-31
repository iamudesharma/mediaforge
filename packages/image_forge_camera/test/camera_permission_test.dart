import 'package:flutter_test/flutter_test.dart';
import 'package:image_forge_camera/image_forge_camera.dart';

void main() {
  test('LiveCameraService.isSupported is false on VM test host', () {
    expect(LiveCameraService.isSupported, isFalse);
  });
}
