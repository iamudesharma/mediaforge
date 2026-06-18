import 'package:flutter/material.dart';

import 'video_text_overlay_style.dart';

/// Instagram-style look presets for video captions.
enum VideoTextLookPreset {
  modern,
  classic,
  strong,
  signature,
  neon,
  threeD,
}

/// Preview animation when a preset is applied or text appears.
enum VideoTextAnimation {
  none,
  popIn,
  bounce,
  typewriter,
  fadeScale,
  slideIn,
  glitch,
}

/// Lumina Edit animation presets shown in the Text Animation panel.
const luminaTextAnimations = <(VideoTextAnimation, String)>[
  (VideoTextAnimation.fadeScale, 'Fade'),
  (VideoTextAnimation.typewriter, 'Typewriter'),
  (VideoTextAnimation.bounce, 'Bounce'),
  (VideoTextAnimation.slideIn, 'Slide In'),
  (VideoTextAnimation.glitch, 'Glitch'),
];

/// Primary style cards in the Text Style / Background panels.
const luminaStylePresets = <(VideoTextLookPreset, String)>[
  (VideoTextLookPreset.modern, 'Modern'),
  (VideoTextLookPreset.strong, 'Bold'),
  (VideoTextLookPreset.signature, 'Script'),
  (VideoTextLookPreset.neon, 'Neon'),
];

/// Instagram-style accent colors users can cycle with a tap.
const videoTextAccentColors = <Color>[
  Color(0xFF00E38A),
  Color(0xFF2AF598),
  Color(0xFF57FFA6),
  Color(0xFF64B5F6),
  Color(0xFFFF4081),
  Color(0xFFFFD54F),
  Color(0xFFE040FB),
  Color(0xFFEDB1FF),
  Colors.white,
  Colors.black,
  Color(0xFF849587),
  Color(0xFFBACBBC),
  Color(0xFF1A1C20),
  Color(0xFF333539),
];

VideoTextLookPreset nextLookPreset(VideoTextLookPreset current) {
  const values = VideoTextLookPreset.values;
  return values[(values.indexOf(current) + 1) % values.length];
}

VideoTextAnimation animationForPreset(VideoTextLookPreset preset) {
  return switch (preset) {
    VideoTextLookPreset.modern => VideoTextAnimation.popIn,
    VideoTextLookPreset.classic => VideoTextAnimation.fadeScale,
    VideoTextLookPreset.strong => VideoTextAnimation.bounce,
    VideoTextLookPreset.signature => VideoTextAnimation.typewriter,
    VideoTextLookPreset.neon => VideoTextAnimation.popIn,
    VideoTextLookPreset.threeD => VideoTextAnimation.bounce,
  };
}

VideoTextOverlayStyle styleForLookPreset(
  VideoTextLookPreset preset, {
  VideoTextOverlayStyle base = VideoTextOverlayStyle.defaults,
  Color? accent,
}) {
  final color = accent ?? base.color;
  return switch (preset) {
    VideoTextLookPreset.modern => base.copyWith(
        lookPreset: preset,
        fontWeight: FontWeight.w700,
        backgroundStyle: VideoTextBackgroundStyle.rounded,
        backgroundColor: const Color(0xE6000000),
        color: Colors.white,
        fillMode: VideoTextFillMode.solid,
        fontStyle: FontStyle.normal,
        animation: VideoTextAnimation.popIn,
      ),
    VideoTextLookPreset.classic => base.copyWith(
        lookPreset: preset,
        fontWeight: FontWeight.w400,
        backgroundStyle: VideoTextBackgroundStyle.none,
        color: color,
        fillMode: VideoTextFillMode.solid,
        fontStyle: FontStyle.normal,
        animation: VideoTextAnimation.fadeScale,
      ),
    VideoTextLookPreset.strong => base.copyWith(
        lookPreset: preset,
        fontWeight: FontWeight.w900,
        backgroundStyle: VideoTextBackgroundStyle.solid,
        backgroundColor: Colors.black,
        color: Colors.white,
        fillMode: VideoTextFillMode.solid,
        animation: VideoTextAnimation.bounce,
      ),
    VideoTextLookPreset.signature => base.copyWith(
        lookPreset: preset,
        fontWeight: FontWeight.w600,
        backgroundStyle: VideoTextBackgroundStyle.none,
        fillMode: VideoTextFillMode.gradient,
        color: const Color(0xFF00E38A),
        gradientEnd: const Color(0xFFFF4081),
        fontStyle: FontStyle.italic,
        animation: VideoTextAnimation.typewriter,
      ),
    VideoTextLookPreset.neon => base.copyWith(
        lookPreset: preset,
        fontWeight: FontWeight.w800,
        backgroundStyle: VideoTextBackgroundStyle.none,
        color: const Color(0xFF00E38A),
        fillMode: VideoTextFillMode.solid,
        animation: VideoTextAnimation.popIn,
      ),
    VideoTextLookPreset.threeD => base.copyWith(
        lookPreset: preset,
        fontWeight: FontWeight.w900,
        backgroundStyle: VideoTextBackgroundStyle.none,
        color: Colors.white,
        fillMode: VideoTextFillMode.solid,
        useThreeD: true,
        animation: VideoTextAnimation.bounce,
      ),
  };
}

Color nextAccentColor(Color current) {
  final idx = videoTextAccentColors.indexWhere((c) => c.value == current.value);
  final next = idx < 0 ? 0 : (idx + 1) % videoTextAccentColors.length;
  return videoTextAccentColors[next];
}

String labelForLookPreset(VideoTextLookPreset preset) {
  return switch (preset) {
    VideoTextLookPreset.modern => 'Modern',
    VideoTextLookPreset.classic => 'Classic',
    VideoTextLookPreset.strong => 'Strong',
    VideoTextLookPreset.signature => 'Signature',
    VideoTextLookPreset.neon => 'Neon',
    VideoTextLookPreset.threeD => '3D',
  };
}
