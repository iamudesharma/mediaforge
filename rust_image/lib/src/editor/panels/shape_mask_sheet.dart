import 'package:flutter/material.dart';

import '../models/overlay_layer.dart';
import '../theme/lumina_tokens.dart';

/// Pick a clip shape for imported image stickers.
class ShapeMaskSheet extends StatelessWidget {
  const ShapeMaskSheet({
    super.key,
    required this.imageCount,
    this.title,
    this.initial,
  });

  final int imageCount;
  final String? title;
  final StickerShapeMask? initial;

  static Future<StickerShapeMask?> pick(
    BuildContext context, {
    required int imageCount,
    String? title,
    StickerShapeMask? initial,
  }) {
    return showModalBottomSheet<StickerShapeMask>(
      context: context,
      backgroundColor: LuminaTokens.surfaceContainerHigh,
      builder: (ctx) => ShapeMaskSheet(
        imageCount: imageCount,
        title: title,
        initial: initial,
      ),
    );
  }

  static String label(StickerShapeMask mask) => switch (mask) {
        StickerShapeMask.none => 'None',
        StickerShapeMask.roundedRect => 'Rounded',
        StickerShapeMask.circle => 'Circle',
        StickerShapeMask.ellipse => 'Oval',
        StickerShapeMask.heart => 'Heart',
        StickerShapeMask.star => 'Star',
        StickerShapeMask.hexagon => 'Hexagon',
        StickerShapeMask.squircle => 'Squircle',
      };

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(LuminaTokens.padMd),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title ??
                  'Shape for $imageCount image${imageCount == 1 ? '' : 's'}',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            if (imageCount == 1)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Applies only to this sticker',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: LuminaTokens.onSurfaceVariant,
                      ),
                ),
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final mask in StickerShapeMask.values)
                  ChoiceChip(
                    label: Text(label(mask)),
                    selected: initial == mask,
                    onSelected: (_) => Navigator.pop(context, mask),
                  ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
