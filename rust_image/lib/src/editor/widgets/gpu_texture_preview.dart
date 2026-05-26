import 'package:flutter/material.dart';

import '../services/gpu_texture_registry.dart';

/// Displays a platform [Texture] fed from GPU preview readback (macOS first).
class GpuTexturePreview extends StatelessWidget {
  const GpuTexturePreview({
    super.key,
    required this.textureId,
    required this.width,
    required this.height,
    this.fit = BoxFit.contain,
  });

  final int textureId;
  final int width;
  final int height;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    if (textureId <= 0 || width <= 0 || height <= 0) {
      return const SizedBox.shrink();
    }
    return FittedBox(
      fit: fit,
      child: SizedBox(
        width: width.toDouble(),
        height: height.toDouble(),
        child: Texture(textureId: textureId),
      ),
    );
  }
}

/// Returns true when GPU texture preview can be used on this platform.
bool gpuTexturePreviewSupported() =>
    GpuTextureRegistry.isSupported;
