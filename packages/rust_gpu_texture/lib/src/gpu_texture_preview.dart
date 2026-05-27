import 'package:flutter/material.dart';

import 'gpu_texture_registry.dart';

/// Displays a platform [Texture] fed from [GpuTextureRegistry] uploads.
class GpuTextureView extends StatelessWidget {
  const GpuTextureView({
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

/// Whether [GpuTextureRegistry] can be used on this platform.
bool gpuTextureSupported() => GpuTextureRegistry.isSupported;

/// @deprecated Use [GpuTextureView]. Kept for rust_image editor migration.
typedef GpuTexturePreview = GpuTextureView;

/// @deprecated Use [gpuTextureSupported].
bool gpuTexturePreviewSupported() => gpuTextureSupported();
