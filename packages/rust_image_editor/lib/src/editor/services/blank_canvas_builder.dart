import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Instagram-style canvas aspect presets (pixel dimensions).
enum BlankAspect {
  square1x1,
  story9x16,
  portrait4x5,
  landscape16x9,
}

extension BlankAspectX on BlankAspect {
  String get label => switch (this) {
        BlankAspect.square1x1 => 'Square',
        BlankAspect.story9x16 => 'Story',
        BlankAspect.portrait4x5 => 'Portrait',
        BlankAspect.landscape16x9 => 'Landscape',
      };

  String get subtitle => switch (this) {
        BlankAspect.square1x1 => '1:1 · 1080×1080',
        BlankAspect.story9x16 => '9:16 · 1080×1920',
        BlankAspect.portrait4x5 => '4:5 · 1080×1350',
        BlankAspect.landscape16x9 => '16:9 · 1920×1080',
      };

  Size get pixelSize => switch (this) {
        BlankAspect.square1x1 => const Size(1080, 1080),
        BlankAspect.story9x16 => const Size(1080, 1920),
        BlankAspect.portrait4x5 => const Size(1080, 1350),
        BlankAspect.landscape16x9 => const Size(1920, 1080),
      };
}

/// Background fill for a blank canvas.
sealed class BlankBackground {
  const BlankBackground();
}

final class SolidBlankBackground extends BlankBackground {
  const SolidBlankBackground(this.color);
  final Color color;
}

final class LinearGradientBlankBackground extends BlankBackground {
  const LinearGradientBlankBackground({
    required this.colors,
    this.begin = Alignment.topLeft,
    this.end = Alignment.bottomRight,
  });
  final List<Color> colors;
  final Alignment begin;
  final Alignment end;
}

final class RadialGradientBlankBackground extends BlankBackground {
  const RadialGradientBlankBackground({
    required this.colors,
    this.center = Alignment.center,
    this.radius = 1.2,
  });
  final List<Color> colors;
  final Alignment center;
  final double radius;
}

/// Curated swatches and gradients for blank canvas (Sprint 8).
abstract final class BlankCanvasPresets {
  static const solidColors = [
    Color(0xFFFFFFFF),
    Color(0xFF000000),
    Color(0xFFF5F5F5),
    Color(0xFFEAE6DC),
    Color(0xFF1E1E1E),
    Color(0xFF2D2D2D),
    Color(0xFF4EDEA3),
    Color(0xFF1FAA6C),
    Color(0xFF0D7377),
    Color(0xFF48A9FE),
    Color(0xFF3D5AFE),
    Color(0xFF7C3AED),
    Color(0xFFF7B267),
    Color(0xFFF4845F),
    Color(0xFFF25C54),
    Color(0xFFFF6B9D),
    Color(0xFFFFB4C2),
    Color(0xFFB8E994),
    Color(0xFF95E1D3),
    Color(0xFFFCE38A),
    Color(0xFFF38181),
    Color(0xFFAA96DA),
    Color(0xFFFCBAD3),
    Color(0xFFA8D8EA),
  ];

  static const gradients = <BlankBackground>[
    LinearGradientBlankBackground(
      colors: [Color(0xFFFF9A56), Color(0xFFFF6B9D)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    LinearGradientBlankBackground(
      colors: [Color(0xFF48C6EF), Color(0xFF6F86D6)],
    ),
    LinearGradientBlankBackground(
      colors: [Color(0xFF11998E), Color(0xFF38EF7D)],
    ),
    LinearGradientBlankBackground(
      colors: [Color(0xFFFFB347), Color(0xFFFFCC33)],
    ),
    LinearGradientBlankBackground(
      colors: [Color(0xFFFC466B), Color(0xFF3F5EFB)],
    ),
    LinearGradientBlankBackground(
      colors: [Color(0xFF834D9B), Color(0xFFD04ED6)],
    ),
    RadialGradientBlankBackground(
      colors: [Color(0xFF1A1A2E), Color(0xFF16213E), Color(0xFF0F3460)],
    ),
    LinearGradientBlankBackground(
      colors: [Color(0xFF00C9FF), Color(0xFF92FE9D)],
    ),
    LinearGradientBlankBackground(
      colors: [Color(0xFFFFECD2), Color(0xFFFCB69F)],
    ),
    LinearGradientBlankBackground(
      colors: [Color(0xFFA8EDEA), Color(0xFFFED6E3)],
    ),
    LinearGradientBlankBackground(
      colors: [Color(0xFFD299C2), Color(0xFFFEF9D7)],
    ),
    LinearGradientBlankBackground(
      colors: [Color(0xFF232526), Color(0xFF414345)],
    ),
  ];
}

/// Renders a blank canvas to PNG bytes for [EditorSession.loadSource].
abstract final class BlankCanvasBuilder {
  static Future<Uint8List> render({
    required BlankAspect aspect,
    required BlankBackground background,
  }) async {
    final size = aspect.pixelSize;
    final w = size.width.round();
    final h = size.height.round();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);

    final paint = Paint();
    switch (background) {
      case SolidBlankBackground(:final color):
        paint.color = color;
        canvas.drawRect(rect, paint);
      case LinearGradientBlankBackground(
          :final colors,
          :final begin,
          :final end,
        ):
        paint.shader = LinearGradient(
          begin: begin,
          end: end,
          colors: colors,
        ).createShader(rect);
        canvas.drawRect(rect, paint);
      case RadialGradientBlankBackground(
          :final colors,
          :final center,
          :final radius,
        ):
        paint.shader = RadialGradient(
          center: center,
          radius: radius,
          colors: colors,
        ).createShader(rect);
        canvas.drawRect(rect, paint);
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(w, h);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (byteData == null) {
      throw StateError('Failed to encode blank canvas PNG');
    }
    return byteData.buffer.asUint8List();
  }
}
