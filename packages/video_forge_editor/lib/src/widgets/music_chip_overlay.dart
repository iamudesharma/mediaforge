import 'package:flutter/material.dart';

import '../theme/lumina_tokens.dart';

/// On-canvas music chip (Instagram-style audio sticker).
class MusicChipOverlay extends StatelessWidget {
  const MusicChipOverlay({
    super.key,
    required this.displayName,
    required this.onTap,
    this.anchor = const Offset(0.08, 0.12),
  });

  final String displayName;
  final VoidCallback onTap;
  final Offset anchor;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: anchor.dx * MediaQuery.sizeOf(context).width,
      top: anchor.dy * MediaQuery.sizeOf(context).height,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 220),
          padding: const EdgeInsets.symmetric(
            horizontal: LuminaTokens.space3,
            vertical: LuminaTokens.space2,
          ),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(LuminaTokens.radius2xl),
            border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.music_note,
                color: LuminaTokens.accent,
                size: 18,
              ),
              const SizedBox(width: LuminaTokens.space2),
              Flexible(
                child: Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: LuminaTokens.onSurface,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
