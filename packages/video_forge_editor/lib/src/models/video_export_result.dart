/// Metadata returned after a successful video export.
class VideoExportResult {
  const VideoExportResult({
    required this.outputPath,
    required this.thumbPath,
    required this.originalBytes,
    required this.compressedBytes,
    required this.encodeDuration,
  });

  final String outputPath;
  final String? thumbPath;
  final int originalBytes;
  final int compressedBytes;
  final Duration encodeDuration;
}
