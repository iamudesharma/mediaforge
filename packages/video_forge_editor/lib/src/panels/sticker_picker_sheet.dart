import 'package:flutter/material.dart';

import '../theme/lumina_tokens.dart';
import 'lumina_sticker_panel.dart';

/// Expanded emoji / sticker picker for Stories mode.
class StickerPickerSheet extends StatelessWidget {
  const StickerPickerSheet({
    super.key,
    required this.onEmojiSelected,
  });

  final ValueChanged<String> onEmojiSelected;

  static Future<void> show(
    BuildContext context, {
    required ValueChanged<String> onEmojiSelected,
  }) {
    debugPrint('[StickerPicker] open');
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: LuminaTokens.surfaceContainer,
      showDragHandle: true,
      builder: (ctx) => StickerPickerSheet(onEmojiSelected: onEmojiSelected),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(LuminaTokens.space4),
        child: LuminaStickerPanel(onEmojiSelected: (emoji) {
          onEmojiSelected(emoji);
          Navigator.pop(context);
        }),
      ),
    );
  }
}
