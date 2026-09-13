import 'package:flutter/material.dart';

/// Consistent round icon button for player chrome.
///
/// Desktop gets a [Tooltip]; touch targets stay ≥ 44 pt.
class PlayerIconButton extends StatelessWidget {
  const PlayerIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.selected = false,
    this.badge,
    this.size = 44,
    this.iconSize = 22,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool selected;
  final String? badge;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = colorScheme.primary;
    final button = SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          IconButton(
            onPressed: onPressed,
            icon: Icon(icon, size: iconSize),
            color: selected ? accent : Colors.white,
            disabledColor: Colors.white38,
            style: IconButton.styleFrom(
              backgroundColor: selected
                  ? accent.withValues(alpha: 0.18)
                  : Colors.transparent,
              shape: const CircleBorder(),
            ),
          ),
          if (badge != null)
            Positioned(
              right: 2,
              top: 6,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  badge!,
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: Colors.black,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    final tip = tooltip;
    if (tip == null || tip.isEmpty) return button;
    return Tooltip(message: tip, child: button);
  }
}
