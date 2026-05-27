import 'package:video_processor_core/video_processor_core.dart';

/// App-style compression presets mapped to [VideoQuality] + sensible defaults.
enum CompressionPreset {
  standard,
  instagram,
  whatsapp,
  telegram,
  youtube,
  lossless,
  lowBandwidth;

  VideoQuality get quality => switch (this) {
        CompressionPreset.standard => VideoQuality.medium,
        CompressionPreset.instagram => VideoQuality.instagram,
        CompressionPreset.whatsapp => VideoQuality.whatsapp,
        CompressionPreset.telegram => VideoQuality.telegram,
        CompressionPreset.youtube => VideoQuality.youtube,
        CompressionPreset.lossless => VideoQuality.lossless,
        CompressionPreset.lowBandwidth => VideoQuality.low,
      };

  /// Prefer platform hardware encoders (VideoToolbox / MediaCodec) when available.
  bool get preferHardwareEncoder => this != CompressionPreset.lossless;

  String get label => switch (this) {
        CompressionPreset.standard => 'Standard',
        CompressionPreset.instagram => 'Instagram',
        CompressionPreset.whatsapp => 'WhatsApp',
        CompressionPreset.telegram => 'Telegram',
        CompressionPreset.youtube => 'YouTube',
        CompressionPreset.lossless => 'Lossless',
        CompressionPreset.lowBandwidth => 'Low bandwidth',
      };
}
