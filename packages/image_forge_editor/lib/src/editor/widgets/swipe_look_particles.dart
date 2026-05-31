import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/swipe_look_names.dart';
import 'package:image_forge/image_forge.dart';

/// Snow / sparkle particles for [SwipeLookPreset.animeAirbrush] combo look.
class SwipeLookParticleOverlay extends StatefulWidget {
  const SwipeLookParticleOverlay({
    super.key,
    required this.active,
    required this.child,
  });

  final bool active;
  final Widget child;

  @override
  State<SwipeLookParticleOverlay> createState() =>
      _SwipeLookParticleOverlayState();
}

class _SwipeLookParticleOverlayState extends State<SwipeLookParticleOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_Particle> _particles;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
    final rng = math.Random(42);
    _particles = List.generate(28, (i) {
      return _Particle(
        x: rng.nextDouble(),
        y: rng.nextDouble(),
        size: 1.5 + rng.nextDouble() * 2.5,
        speed: 0.08 + rng.nextDouble() * 0.12,
        phase: rng.nextDouble(),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return widget.child;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        IgnorePointer(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              return CustomPaint(
                painter: _ParticlePainter(
                  t: _controller.value,
                  particles: _particles,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Particle {
  _Particle({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.phase,
  });

  final double x;
  final double y;
  final double size;
  final double speed;
  final double phase;
}

class _ParticlePainter extends CustomPainter {
  _ParticlePainter({required this.t, required this.particles});

  final double t;
  final List<_Particle> particles;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.55);
    for (final p in particles) {
      final y = ((p.y + t * p.speed + p.phase) % 1.0) * size.height;
      final x = p.x * size.width + math.sin(t * 6.28 + p.phase * 12) * 6;
      paint.maskFilter = MaskFilter.blur(BlurStyle.normal, p.size * 0.4);
      canvas.drawCircle(Offset(x, y), p.size, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter oldDelegate) =>
      oldDelegate.t != t;
}

bool swipeLookUsesParticles(SwipeLookPreset? preset) =>
    preset == SwipeLookPreset.animeAirbrush;
