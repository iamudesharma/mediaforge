import 'package:video_forge/video_forge.dart';

/// Quality presets for video compression.
typedef VideoQualityPreset = VideoQuality;

/// Alias for generated [VideoQuality] enum.
enum VideoQualityLevel {
  low(VideoQuality.low),
  medium(VideoQuality.medium),
  high(VideoQuality.high),
  custom(VideoQuality.custom),
  instagram(VideoQuality.instagram),
  whatsapp(VideoQuality.whatsapp),
  telegram(VideoQuality.telegram),
  youtube(VideoQuality.youtube),
  lossless(VideoQuality.lossless);

  const VideoQualityLevel(this.value);
  final VideoQuality value;
}
