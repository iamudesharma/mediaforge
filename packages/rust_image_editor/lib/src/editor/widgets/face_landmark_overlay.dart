import 'package:flutter/material.dart';
import 'package:rust_image_core/rust_image_core.dart';

/// Debug overlay — draws normalized face landmarks (Nexus A dev flag).
class FaceLandmarkOverlay extends StatelessWidget {
  const FaceLandmarkOverlay({
    super.key,
    required this.landmarks,
    required this.imageWidth,
    required this.imageHeight,
    this.color = const Color(0xFF00E5FF),
  });

  final List<Landmark2D> landmarks;
  final int imageWidth;
  final int imageHeight;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (landmarks.isEmpty || imageWidth <= 0 || imageHeight <= 0) {
      return const SizedBox.shrink();
    }
    return CustomPaint(
      painter: _LandmarkPainter(
        landmarks: landmarks,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        color: color,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _LandmarkPainter extends CustomPainter {
  _LandmarkPainter({
    required this.landmarks,
    required this.imageWidth,
    required this.imageHeight,
    required this.color,
  });

  final List<Landmark2D> landmarks;
  final int imageWidth;
  final int imageHeight;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final sx = size.width / imageWidth;
    final sy = size.height / imageHeight;
    final scale = sx < sy ? sx : sy;
    final ox = (size.width - imageWidth * scale) / 2;
    final oy = (size.height - imageHeight * scale) / 2;

    Offset? prev;
    for (final lm in landmarks) {
      final pt = Offset(
        ox + lm.x * imageWidth * scale,
        oy + lm.y * imageHeight * scale,
      );
      canvas.drawCircle(pt, 2.2, paint);
      if (prev != null) {
        canvas.drawLine(prev, pt, stroke);
      }
      prev = pt;
    }
  }

  @override
  bool shouldRepaint(covariant _LandmarkPainter oldDelegate) =>
      oldDelegate.landmarks != landmarks ||
      oldDelegate.imageWidth != imageWidth ||
      oldDelegate.imageHeight != imageHeight;
}
