import 'package:flutter/material.dart';

import '../theme/editor_motion.dart';

/// Fade + slight slide for panel content and sections.
class FadeSlideTransition extends StatelessWidget {
  const FadeSlideTransition({
    super.key,
    required this.animation,
    required this.child,
    this.offset = const Offset(0, 0.03),
  });

  final Animation<double> animation;
  final Widget child;
  final Offset offset;

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(begin: offset, end: Offset.zero).animate(
          CurvedAnimation(parent: animation, curve: EditorMotion.enter),
        ),
        child: child,
      ),
    );
  }
}

/// Switches child with a polished cross-fade and slide.
class AnimatedPanelSwitcher extends StatelessWidget {
  const AnimatedPanelSwitcher({
    super.key,
    required this.child,
    required this.switchKey,
  });

  final Widget child;
  final Object switchKey;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: EditorMotion.medium,
      switchInCurve: EditorMotion.enter,
      switchOutCurve: EditorMotion.exit,
      transitionBuilder: (child, animation) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: EditorMotion.enter,
          reverseCurve: EditorMotion.exit,
        );
        return FadeSlideTransition(animation: curved, child: child);
      },
      child: KeyedSubtree(
        key: ValueKey(switchKey),
        child: child,
      ),
    );
  }
}

/// Subtle breathing scale for empty states and loaders.
class PulseWidget extends StatefulWidget {
  const PulseWidget({
    super.key,
    required this.child,
    this.minScale = 0.94,
    this.maxScale = 1.0,
  });

  final Widget child;
  final double minScale;
  final double maxScale;

  @override
  State<PulseWidget> createState() => _PulseWidgetState();
}

class _PulseWidgetState extends State<PulseWidget> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween<double>(begin: widget.minScale, end: widget.maxScale).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: widget.child,
    );
  }
}

/// Shimmer bar used while Rust work is in progress.
class ShimmerProgressBar extends StatefulWidget {
  const ShimmerProgressBar({super.key, required this.color, this.height = 3});

  final Color color;
  final double height;

  @override
  State<ShimmerProgressBar> createState() => _ShimmerProgressBarState();
}

class _ShimmerProgressBarState extends State<ShimmerProgressBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return ClipRRect(
          child: SizedBox(
            height: widget.height,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                final band = w * 0.35;
                final left = (w + band) * _controller.value - band;
                return Stack(
                  children: [
                    ColoredBox(
                      color: widget.color.withValues(alpha: 0.15),
                      child: const SizedBox.expand(),
                    ),
                    Positioned(
                      left: left,
                      width: band,
                      top: 0,
                      bottom: 0,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              widget.color.withValues(alpha: 0.0),
                              widget.color,
                              widget.color.withValues(alpha: 0.0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}
