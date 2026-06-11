import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/lumina_tokens.dart';

/// A translucent bar with a [BackdropFilter] blur. Used for the mobile
/// top bar, mobile bottom bar, and the desktop inspector header so the
/// underlying canvas / preview bleeds through the chrome (iOS 18 / Apple
/// Photos aesthetic).
class FrostedBar extends StatelessWidget {
  const FrostedBar({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.color,
    this.borderTop = true,
    this.borderBottom = false,
    this.blurSigma = LuminaTokens.sheetBlurSigma,
    this.height,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final bool borderTop;
  final bool borderBottom;
  final double blurSigma;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final base = color ?? LuminaTokens.surfaceContainerLow.withValues(alpha: 0.78);
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          height: height,
          padding: padding,
          decoration: BoxDecoration(
            color: base,
            border: Border(
              top: borderTop
                  ? const BorderSide(
                      color: LuminaTokens.outlineVariant,
                      width: 0.5,
                    )
                  : BorderSide.none,
              bottom: borderBottom
                  ? const BorderSide(
                      color: LuminaTokens.outlineVariant,
                      width: 0.5,
                    )
                  : BorderSide.none,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
