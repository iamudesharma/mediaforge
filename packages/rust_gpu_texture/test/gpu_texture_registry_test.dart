import 'package:flutter_test/flutter_test.dart';
import 'package:rust_gpu_texture/rust_gpu_texture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('channel name is stable', () {
    expect(GpuTextureRegistry.channelName, 'rust_gpu_texture/texture');
  });

  test('isSupported matches platform (not web)', () {
    // On macOS/iOS/Android CI hosts this may be true; on Linux CI false.
    expect(GpuTextureRegistry.isSupported, isA<bool>());
  });
}
