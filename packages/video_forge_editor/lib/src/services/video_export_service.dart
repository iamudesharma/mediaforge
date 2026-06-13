import 'package:video_forge_kit/video_forge_kit.dart';

import 'editor_output_paths.dart';

/// Export helpers — rasterize overlays and run [VideoProcessor.compressJob].
abstract final class VideoExportService {
  static String phaseLabel(ProcessingPhase phase) {
    return switch (phase) {
      ProcessingPhase.probing => 'Probing',
      ProcessingPhase.decoding => 'Decoding',
      ProcessingPhase.encoding => 'Encoding',
      ProcessingPhase.muxing => 'Muxing',
      ProcessingPhase.thumbnail => 'Thumbnailing',
      ProcessingPhase.done => 'Done',
      ProcessingPhase.cancelled => 'Cancelled',
      ProcessingPhase.failed => 'Failed',
    };
  }

  static String? overlayExportHint(String raw) {
    final lower = raw.toLowerCase();
    if (!lower.contains('burn-in') &&
        !lower.contains('libx264') &&
        !lower.contains('libx265') &&
        !lower.contains('software encoder')) {
      return null;
    }
    return 'Tip: rebuild native libs after updating Rust. '
        'If this persists, try export without overlays.';
  }

  static String shortExportError(String raw) {
    var line = raw.split('\n').first.trim();
    final bt = line.indexOf('Stack backtrace');
    if (bt > 0) {
      line = line.substring(0, bt).trim();
    }
    if (line.startsWith('AnyhowException(') && line.endsWith(')')) {
      line = line.substring('AnyhowException('.length, line.length - 1);
    }
    line = line.replaceAll(RegExp(r'\s+'), ' ');
    if (line.length > 200) {
      return '${line.substring(0, 197)}...';
    }
    return line;
  }

  static Future<String> defaultOutputPath({
    required String inputPath,
    required CompressionPreset preset,
  }) async {
    final outputs = await EditorOutputPaths.resolve();
    return '${outputs.compressVideoDir}/${outputs.safeStem(inputPath)}_${preset.name}_export.mp4';
  }
}
