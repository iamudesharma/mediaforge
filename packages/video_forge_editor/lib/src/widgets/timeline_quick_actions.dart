import 'package:flutter/material.dart';

import '../theme/lumina_tokens.dart';

/// Split / Delete / Speed quick actions above the timeline (Lumina Edit).
class TimelineQuickActions extends StatelessWidget {
  const TimelineQuickActions({
    super.key,
    this.onSplit,
    this.onDelete,
    this.onSpeed,
    this.canSplit = true,
    this.canDelete = false,
  });

  final VoidCallback? onSplit;
  final VoidCallback? onDelete;
  final VoidCallback? onSpeed;
  final bool canSplit;
  final bool canDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: LuminaTokens.space4,
        vertical: LuminaTokens.space2,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _ActionPill(
            icon: Icons.content_cut,
            label: 'Split',
            enabled: canSplit,
            onTap: onSplit,
          ),
          const SizedBox(width: LuminaTokens.space2),
          _ActionPill(
            icon: Icons.delete_outline,
            label: 'Delete',
            enabled: canDelete,
            onTap: onDelete,
          ),
          const SizedBox(width: LuminaTokens.space2),
          _ActionPill(
            icon: Icons.speed,
            label: 'Speed',
            enabled: onSpeed != null,
            onTap: onSpeed,
          ),
        ],
      ),
    );
  }
}

class _ActionPill extends StatelessWidget {
  const _ActionPill({
    required this.icon,
    required this.label,
    required this.enabled,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: LuminaTokens.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(LuminaTokens.radiusLg),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(LuminaTokens.radiusLg),
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: LuminaTokens.space4,
              vertical: LuminaTokens.space2,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: LuminaTokens.accent),
                const SizedBox(width: LuminaTokens.space1),
                Text(
                  label,
                  style: const TextStyle(
                    color: LuminaTokens.onSurface,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
