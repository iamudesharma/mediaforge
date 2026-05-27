import 'package:flutter_test/flutter_test.dart';
import 'package:rust_image_editor/rust_image_editor.dart';
import 'package:rust_image_editor/src/editor/services/image_buffer_utils.dart';

void main() {
  group('ImageBufferUtils.describeFilterPath', () {
    test('forces cpu_photon when backend is explicitly cpu', () {
      final path = ImageBufferUtils.describeFilterPath(
        descriptor: FilterDescriptor.brightness(amount: 10),
        backend: ProcessingBackend.cpu,
        gpuAvailable: true,
      );
      expect(path, 'cpu_photon');
    });

    test('returns gpu_adjust for brightness on auto when GPU is available',
        () {
      final path = ImageBufferUtils.describeFilterPath(
        descriptor: FilterDescriptor.brightness(amount: 10),
        backend: ProcessingBackend.auto,
        gpuAvailable: true,
      );
      expect(path, 'gpu_adjust');
    });

    test('falls back to cpu_photon for brightness when GPU is unavailable',
        () {
      final path = ImageBufferUtils.describeFilterPath(
        descriptor: FilterDescriptor.brightness(amount: 10),
        backend: ProcessingBackend.auto,
        gpuAvailable: false,
      );
      expect(path, 'cpu_photon');
    });

    test('falls back to cpu_photon for non-adjust filters on auto', () {
      final path = ImageBufferUtils.describeFilterPath(
        descriptor: FilterDescriptor.blur(radius: 4),
        backend: ProcessingBackend.auto,
        gpuAvailable: true,
      );
      expect(path, 'cpu_photon');
    });

    test('returns gpu_adjust for saturation on auto with GPU available', () {
      final path = ImageBufferUtils.describeFilterPath(
        descriptor: FilterDescriptor.saturation(amount: 0.5),
        backend: ProcessingBackend.auto,
        gpuAvailable: true,
      );
      expect(path, 'gpu_adjust');
    });
  });
}
