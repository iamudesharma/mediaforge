import 'dart:typed_data';

/// One decoded preview frame with media timestamp.
///
/// V1.1: [rgba] CPU path. V1.4 (Apple): [pixelBufferPtr]. V1.6 (Android): [presentedToSurface].
final class PreviewFrame {
  const PreviewFrame({
    required this.ptsMs,
    required this.width,
    required this.height,
    this.rgba,
    this.pixelBufferPtr,
    this.presentedToSurface = false,
  }) : assert(
          rgba != null ||
              (pixelBufferPtr != null && pixelBufferPtr > 0) ||
              presentedToSurface,
        );

  final int ptsMs;
  final int width;
  final int height;
  final Uint8List? rgba;

  /// Native `CVPixelBuffer*` (+1 retained); released by texture plugin on present.
  final int? pixelBufferPtr;

  /// Android MediaCodec rendered into the pool SurfaceTexture before present.
  final bool presentedToSurface;

  bool get isHwPixelBuffer =>
      pixelBufferPtr != null && pixelBufferPtr! > 0;
}
