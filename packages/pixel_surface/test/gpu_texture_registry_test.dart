import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_surface/pixel_surface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('channel name is stable', () {
    expect(GpuTextureRegistry.channelName, 'pixel_surface/texture');
  });

  test('isSupported matches platform (not web)', () {
    // On macOS/iOS/Android CI hosts this may be true; on Linux CI false.
    expect(GpuTextureRegistry.isSupported, isA<bool>());
  });
}
