import 'dart:math' as math;

import 'package:image_forge_editor/src/image_forge_editor.dart';

import 'filter_descriptor.dart';

/// Shared buffer helpers for the editor pipeline.
abstract final class ImageBufferUtils {
  /// Downscale so the longest edge is at most [maxEdge]. Returns [buffer] unchanged if already smaller.
  static RgbaImageBuffer fitMaxEdge(RgbaImageBuffer buffer, int maxEdge) {
    if (maxEdge <= 0) return buffer;
    final maxDim = math.max(buffer.width, buffer.height);
    if (maxDim <= maxEdge) return buffer;

    final scale = maxEdge / maxDim;
    final w = math.max(1, (buffer.width * scale).round());
    final h = math.max(1, (buffer.height * scale).round());

    return RustImageEditor.resizeRgba(
      buffer,
      width: w,
      height: h,
      algorithm: ResizeAlgorithm.mitchell,
      backend: ProcessingBackend.auto,
    );
  }

  /// Heuristic label for where a filter will run (Phase 0 path audit).
  static String describeFilterPath({
    required FilterDescriptor descriptor,
    required ProcessingBackend backend,
    required bool gpuAvailable,
  }) {
    if (backend == ProcessingBackend.cpu || !gpuAvailable) {
      return 'cpu_photon';
    }
    switch (descriptor.kind) {
      case 'brightness':
      case 'contrast':
      case 'saturation':
        return 'gpu_adjust';
      default:
        return 'cpu_photon';
    }
  }
}
