import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'video_text_overlay_content.dart';
import 'video_text_overlay_style.dart';
import 'video_text_presets.dart';

/// Caption with Instagram-style entrance animation when style/preset changes.
class AnimatedVideoTextOverlayContent extends StatefulWidget {
  const AnimatedVideoTextOverlayContent({
    super.key,
    required this.spec,
    this.replayToken = 0,
  });

  final VideoTextOverlaySpec spec;

  /// Increment to replay the current preset animation (e.g. user tapped style chip).
  final int replayToken;

  @override
  State<AnimatedVideoTextOverlayContent> createState() =>
      _AnimatedVideoTextOverlayContentState();
}

class _AnimatedVideoTextOverlayContentState
    extends State<AnimatedVideoTextOverlayContent>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late VideoTextAnimation _animation;

  @override
  void initState() {
    super.initState();
    _animation = widget.spec.style.animation;
    _controller = AnimationController(
      vsync: this,
      duration: _durationFor(_animation),
    )..forward();
  }

  @override
  void didUpdateWidget(covariant AnimatedVideoTextOverlayContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    final styleChanged = oldWidget.spec.style.lookPreset !=
            widget.spec.style.lookPreset ||
        oldWidget.spec.style.color != widget.spec.style.color ||
        oldWidget.replayToken != widget.replayToken;
    final animChanged = oldWidget.spec.style.animation != widget.spec.style.animation;
    if (styleChanged || animChanged) {
      _animation = widget.spec.style.animation;
      _controller
        ..duration = _durationFor(_animation)
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Duration _durationFor(VideoTextAnimation anim) {
    final scale = widget.spec.style.animationDurationScale.clamp(0.35, 2.5);
    Duration base = switch (anim) {
      VideoTextAnimation.none => Duration.zero,
      VideoTextAnimation.popIn => const Duration(milliseconds: 420),
      VideoTextAnimation.bounce => const Duration(milliseconds: 700),
      VideoTextAnimation.typewriter => Duration(
          milliseconds: (widget.spec.label.length * 45).clamp(300, 1800),
        ),
      VideoTextAnimation.fadeScale => const Duration(milliseconds: 380),
      VideoTextAnimation.slideIn => const Duration(milliseconds: 450),
      VideoTextAnimation.glitch => const Duration(milliseconds: 520),
    };
    if (base == Duration.zero) return base;
    return Duration(milliseconds: (base.inMilliseconds / scale).round());
  }

  @override
  Widget build(BuildContext context) {
    if (_animation == VideoTextAnimation.none) {
      return VideoTextOverlayContent(spec: widget.spec);
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = Curves.easeOutCubic.transform(_controller.value);
        return switch (_animation) {
          VideoTextAnimation.popIn => Transform.scale(
              scale: t,
              child: Opacity(opacity: t.clamp(0.0, 1.0), child: child),
            ),
          VideoTextAnimation.bounce => Transform.scale(
              scale: 0.6 + 0.5 * math.sin(t * math.pi),
              child: child,
            ),
          VideoTextAnimation.fadeScale => Opacity(
              opacity: t,
              child: Transform.scale(scale: 0.85 + 0.15 * t, child: child),
            ),
          VideoTextAnimation.typewriter => _TypewriterReveal(
              progress: t,
              child: child!,
            ),
          VideoTextAnimation.slideIn => Transform.translate(
              offset: Offset((1 - t) * -48, 0),
              child: Opacity(opacity: t.clamp(0.0, 1.0), child: child),
            ),
          VideoTextAnimation.glitch => _GlitchReveal(
              progress: t,
              child: child!,
            ),
          VideoTextAnimation.none => child!,
        };
      },
      child: VideoTextOverlayContent(spec: widget.spec),
    );
  }
}

class _TypewriterReveal extends StatelessWidget {
  const _TypewriterReveal({required this.progress, required this.child});

  final double progress;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Align(
        alignment: Alignment.centerLeft,
        widthFactor: progress.clamp(0.05, 1.0),
        child: child,
      ),
    );
  }
}

class _GlitchReveal extends StatelessWidget {
  const _GlitchReveal({required this.progress, required this.child});

  final double progress;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final jitter = progress < 0.85 ? math.sin(progress * 42) * 3 : 0.0;
    final rgb = progress < 0.7 ? (1 - progress) * 4 : 0.0;
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        if (rgb > 0.1)
          Transform.translate(
            offset: Offset(-rgb * 2, jitter),
            child: Opacity(opacity: 0.45 * rgb, child: child),
          ),
        if (rgb > 0.1)
          Transform.translate(
            offset: Offset(rgb * 2, -jitter),
            child: Opacity(opacity: 0.35 * rgb, child: child),
          ),
        Opacity(opacity: progress.clamp(0.0, 1.0), child: child),
      ],
    );
  }
}
