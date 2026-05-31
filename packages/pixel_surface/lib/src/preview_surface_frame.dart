/// Result of Android MediaCodec → SurfaceTexture preview decode (Sprint V1.6).
final class PreviewSurfaceFrame {
  const PreviewSurfaceFrame({
    required this.ptsMs,
    required this.width,
    required this.height,
  });

  final int ptsMs;
  final int width;
  final int height;
}
