import 'package:flutter_test/flutter_test.dart';
import 'package:rust_camera_runtime/rust_camera_runtime.dart';

void main() {
  test('LiveCameraService.isSupported is false on VM test host', () {
    expect(LiveCameraService.isSupported, isFalse);
  });
}
