import 'package:flutter/material.dart';

import '../editor_session.dart';
import '../layout/editor_overlay_state.dart';
import '../models/overlay_layer.dart';
import '../panels/blank_canvas_sheet.dart';
import '../widgets/control_widgets.dart';
import '../panels/shape_mask_sheet.dart';
import '../panels/text_layer_edit_sheet.dart';
import '../theme/lumina_tokens.dart';

/// In-stack overlays (mobile) — keeps the canvas visible behind controls.
class EditorOverlayPanel extends StatelessWidget {
  const EditorOverlayPanel({
    super.key,
    required this.state,
    required this.session,
    required this.onDismiss,
  });

  final EditorOverlayState state;
  final EditorSession session;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return switch (state.kind) {
      EditorOverlayKind.none => const SizedBox.shrink(),
      EditorOverlayKind.textEdit when state.textLayer != null =>
        _OverlayScaffold(
          onDismiss: onDismiss,
          maxHeightFraction: 0.62,
          child: TextLayerEditPanel(
            key: ValueKey(state.textLayer!.id),
            session: session,
            layer: state.textLayer!,
            onDismiss: onDismiss,
          ),
        ),
      EditorOverlayKind.shapeMask => _OverlayScaffold(
          onDismiss: onDismiss,
          child: ShapeMaskPanel(
            imageCount: state.shapeMaskImageCount,
            title: state.shapeMaskTitle,
            initial: state.shapeMaskInitial,
            onSelected: (mask) {
              state.onShapeMaskSelected?.call(mask);
              onDismiss();
            },
            onDismiss: onDismiss,
          ),
        ),
      EditorOverlayKind.blankCanvas => _OverlayScaffold(
          onDismiss: onDismiss,
          maxHeightFraction: 0.55,
          child: SingleChildScrollView(
            child: BlankCanvasSheet(
              session: session,
              onDismiss: onDismiss,
            ),
          ),
        ),
      _ => const SizedBox.shrink(),
    };
  }
}

class _OverlayScaffold extends StatelessWidget {
  const _OverlayScaffold({
    required this.onDismiss,
    required this.child,
    this.maxHeightFraction = 0.45,
  });

  final VoidCallback onDismiss;
  final Widget child;
  final double maxHeightFraction;

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.sizeOf(context).height * maxHeightFraction;

    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          onTap: onDismiss,
          behavior: HitTestBehavior.opaque,
          child: ColoredBox(
            color: Colors.black.withValues(alpha: 0.35),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Material(
            color: Colors.transparent,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxH),
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  color: LuminaTokens.surfaceContainerHigh,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(LuminaTokens.radiusXl),
                  ),
                  border: Border(
                    top: BorderSide(color: LuminaTokens.outlineVariant),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 8),
                    Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: LuminaTokens.outline.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Flexible(child: child),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Shape mask picker body (no Navigator).
class ShapeMaskPanel extends StatelessWidget {
  const ShapeMaskPanel({
    super.key,
    required this.imageCount,
    this.title,
    this.initial,
    required this.onSelected,
    required this.onDismiss,
  });

  final int imageCount;
  final String? title;
  final StickerShapeMask? initial;
  final ValueChanged<StickerShapeMask> onSelected;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(LuminaTokens.padMd),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title ??
                        'Shape for $imageCount image${imageCount == 1 ? '' : 's'}',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: onDismiss,
                ),
              ],
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
            ActionChipRow<StickerShapeMask>(
              items: StickerShapeMask.values,
              label: ShapeMaskSheet.label,
              selected: initial ?? StickerShapeMask.none,
              onSelected: onSelected,
            ),
          ],
        ),
      ),
    );
  }
}
