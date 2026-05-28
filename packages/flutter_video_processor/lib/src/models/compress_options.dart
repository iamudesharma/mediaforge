import 'package:video_processor_core/video_processor_core.dart';

/// Dart-side compression options builder wrapping the FRB [CompressOptions].
class CompressOptionsBuilder {
  CompressOptionsBuilder({
    required this.inputPath,
    this.outputPath,
    this.quality = VideoQuality.medium,
    this.codec = VideoCodec.h264,
    this.crf,
    this.targetBitrate,
    this.maxWidth,
    this.maxHeight,
    this.maxFps,
    this.includeAudio = true,
    this.fastStart = true,
    this.fragmentedMp4 = false,
    this.preferHardwareEncoder = true,
    this.startMs,
    this.endMs,
    this.burnInOverlays = const [],
  });

  final String inputPath;
  String? outputPath;
  VideoQuality quality;
  VideoCodec codec;
  int? crf;
  int? targetBitrate;
  int? maxWidth;
  int? maxHeight;
  double? maxFps;
  bool includeAudio;
  bool fastStart;
  bool fragmentedMp4;
  bool preferHardwareEncoder;
  int? startMs;
  int? endMs;
  List<BurnInOverlay> burnInOverlays;

  CompressOptions build() => CompressOptions(
        inputPath: inputPath,
        outputPath: outputPath,
        quality: quality,
        codec: codec,
        crf: crf,
        targetBitrate: targetBitrate != null ? BigInt.from(targetBitrate!) : null,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        maxFps: maxFps,
        includeAudio: includeAudio,
        fastStart: fastStart,
        fragmentedMp4: fragmentedMp4,
        preferHardwareEncoder: preferHardwareEncoder,
        startMs: startMs != null ? BigInt.from(startMs!) : null,
        endMs: endMs != null ? BigInt.from(endMs!) : null,
        burnInOverlays: burnInOverlays,
      );
}
