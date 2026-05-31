import 'package:flutter/material.dart';

/// Horizontal scrubber: full audio length with a fixed-width selection window.
class AudioRangeScrubber extends StatelessWidget {
  const AudioRangeScrubber({
    super.key,
    required this.sourceDurationMs,
    required this.windowDurationMs,
    required this.sourceStartMs,
    required this.onSourceStartChanged,
    this.height = 36,
  });

  final int sourceDurationMs;
  final int windowDurationMs;
  final int sourceStartMs;
  final ValueChanged<int> onSourceStartChanged;
  final double height;

  @override
  Widget build(BuildContext context) {
    final total = sourceDurationMs.clamp(1, 1 << 30);
    final window = windowDurationMs.clamp(1, total);
    final maxStart = (total - window).clamp(0, total);

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final windowW = (w * window / total).clamp(24.0, w);
        final maxLeft = (w - windowW).clamp(0.0, w);
        final left = maxStart > 0
            ? maxLeft * (sourceStartMs / maxStart)
            : 0.0;

        return SizedBox(
          height: height,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.white12),
                ),
                child: CustomPaint(
                  size: Size(w, height),
                  painter: _BarPainter(barCount: (w / 4).round().clamp(8, 80)),
                ),
              ),
              Positioned(
                left: left,
                width: windowW,
                height: height,
                child: GestureDetector(
                  onHorizontalDragUpdate: (d) {
                    if (maxStart <= 0) return;
                    final nextLeft =
                        (left + d.delta.dx).clamp(0.0, maxLeft);
                    final ms = ((nextLeft / maxLeft) * maxStart).round();
                    onSourceStartChanged(ms.clamp(0, maxStart));
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF43A047).withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFF66BB6A), width: 1.5),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter({required this.barCount});

  final int barCount;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFF4A4A4A);
    final step = size.width / barCount;
    for (var i = 0; i < barCount; i++) {
      final h = size.height * (0.25 + 0.55 * ((i * 7 + 3) % 11) / 10);
      final x = i * step + step * 0.15;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, (size.height - h) / 2, step * 0.5, h),
          const Radius.circular(1),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BarPainter oldDelegate) =>
      oldDelegate.barCount != barCount;
}
