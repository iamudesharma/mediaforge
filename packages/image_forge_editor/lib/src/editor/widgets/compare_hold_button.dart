import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/lumina_tokens.dart';

/// Compare control: press (mobile) or hover (desktop) to peek at the original image.
class CompareHoldButton extends StatelessWidget {
  const CompareHoldButton({
    super.key,
    required this.enabled,
    required this.active,
    required this.onHoldStart,
    required this.onHoldEnd,
    this.iconSize = 22,
  });

  final bool enabled;
  final bool active;
  final VoidCallback onHoldStart;
  final VoidCallback onHoldEnd;
  final double iconSize;

  static bool _hoverPeekSupported() {
    if (kIsWeb) return true;
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
      case TargetPlatform.android:
        return false;
      default:
        return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget button = IconButton(
      icon: Icon(
        active ? Icons.compare : Icons.compare_outlined,
        size: iconSize,
      ),
      tooltip: _hoverPeekSupported()
          ? 'Hover to see original'
          : 'Hold to see original',
      color: active ? LuminaTokens.primary : null,
      onPressed: enabled ? () {} : null,
    );

    button = Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: enabled ? (_) => onHoldStart() : null,
      onPointerUp: enabled ? (_) => onHoldEnd() : null,
      onPointerCancel: enabled ? (_) => onHoldEnd() : null,
      child: button,
    );

    if (_hoverPeekSupported()) {
      button = MouseRegion(
        onEnter: enabled ? (_) => onHoldStart() : null,
        onExit: enabled ? (_) => onHoldEnd() : null,
        child: button,
      );
    }

    return button;
  }
}
