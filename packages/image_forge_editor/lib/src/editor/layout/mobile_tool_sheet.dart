import 'package:flutter/material.dart';

import '../panels/tool_panels.dart';
import '../theme/lumina_tokens.dart';

/// Scroll padding for tool panels inside the mobile bottom sheet.
EdgeInsets mobileToolSheetContentPadding({bool compact = true}) {
  return EdgeInsets.fromLTRB(
    compact ? LuminaTokens.space4 : LuminaTokens.space4,
    compact ? LuminaTokens.space1 : LuminaTokens.space2,
    compact ? LuminaTokens.space4 : LuminaTokens.space4,
    compact ? LuminaTokens.space6 : LuminaTokens.space4,
  );
}

/// Legacy helper widget preserved for back-compat. The live mobile layout
/// uses [_MobileEditorLayoutState] which builds its own draggable sheet
/// host. This class still exists so older host apps embedding it directly
/// keep working.
class MobileToolSheet extends StatelessWidget {
  const MobileToolSheet({
    super.key,
    required this.tool,
    required this.onClose,
    required this.child,
    this.contextStrip,
    this.sheetController,
    this.minSheetFraction = 0.38,
    this.maxSheetFraction = 1.0,
  });

  final EditorTool tool;
  final VoidCallback onClose;
  final Widget child;
  final Widget? contextStrip;
  final DraggableScrollableController? sheetController;
  final double minSheetFraction;
  final double maxSheetFraction;

  @override
  Widget build(BuildContext context) {
    final hasStrip = contextStrip != null;
    final pad = mobileToolSheetContentPadding();
    final bottomSafe = MediaQuery.paddingOf(context).bottom;

    return Material(
      color: LuminaTokens.surfaceContainer,
      elevation: 12,
      shadowColor: Colors.black.withValues(alpha: 0.45),
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(LuminaTokens.radiusXl),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 0, 0, 4),
            child: Column(
              children: [
                const SizedBox(height: 8),
                Center(
                  child: Container(
                    width: LuminaTokens.sheetGrabberWidth,
                    height: LuminaTokens.sheetGrabberHeight,
                    decoration: BoxDecoration(
                      color: LuminaTokens.outline.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Collapse',
                    onPressed: onClose,
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  ),
                ),
              ],
            ),
          ),
          if (hasStrip) ...[
            Flexible(
              child: SingleChildScrollView(
                child: contextStrip!,
              ),
            ),
            const Divider(
              height: 1,
              thickness: 1,
              color: LuminaTokens.outlineVariant,
            ),
          ],
          Flexible(
            child: SingleChildScrollView(
              padding: pad.copyWith(bottom: pad.bottom + bottomSafe),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}
