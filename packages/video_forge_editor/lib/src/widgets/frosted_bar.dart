import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/lumina_tokens.dart';

/// Translucent bar with backdrop blur for Stories-style overlay chrome.
class FrostedBar extends StatelessWidget {
  const FrostedBar({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.color,
    this.borderTop = false,
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
    final base = color ?? LuminaTokens.glassFill;
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
