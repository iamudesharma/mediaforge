import 'package:flutter/material.dart';

import '../panels/tool_panels.dart';
import '../theme/app_typography.dart';
import '../theme/lumina_tokens.dart';

/// Scroll padding for tool panels inside the mobile bottom sheet.
EdgeInsets mobileToolSheetContentPadding({bool compact = true}) {
  return EdgeInsets.fromLTRB(
    compact ? 16 : LuminaTokens.padMd,
    compact ? 4 : 8,
    compact ? 16 : LuminaTokens.padMd,
    compact ? 24 : LuminaTokens.padMd,
  );
}

/// Lumina mobile tool sheet — fixed header/strip, independently scrollable panel body.
class MobileToolSheet extends StatefulWidget {
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
  State<MobileToolSheet> createState() => _MobileToolSheetState();
}

class _MobileToolSheetState extends State<MobileToolSheet> {
  final _panelScroll = ScrollController();

  @override
  void dispose() {
    _panelScroll.dispose();
    super.dispose();
  }

  void _onSheetDrag(DragUpdateDetails details) {
    final ctrl = widget.sheetController;
    if (ctrl == null || !ctrl.isAttached) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || box.size.height <= 0) return;
    final delta = -details.delta.dy / box.size.height;
    ctrl.jumpTo(
      (ctrl.size + delta).clamp(widget.minSheetFraction, widget.maxSheetFraction),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasStrip = widget.contextStrip != null;
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
        children: [
          GestureDetector(
            onVerticalDragUpdate: _onSheetDrag,
            behavior: HitTestBehavior.translucent,
            child: _SheetDragHeader(
              tool: widget.tool,
              onClose: widget.onClose,
              showTitle: !hasStrip,
            ),
          ),
          if (hasStrip) ...[
            Flexible(
              child: SingleChildScrollView(
                child: widget.contextStrip!,
              ),
            ),
            const Divider(
              height: 1,
              thickness: 1,
              color: LuminaTokens.outlineVariant,
            ),
          ],
          Expanded(
            child: ListView(
              controller: _panelScroll,
              primary: false,
              physics: const AlwaysScrollableScrollPhysics(
                parent: ClampingScrollPhysics(),
              ),
              padding: pad.copyWith(bottom: pad.bottom + bottomSafe),
              children: [widget.child],
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetDragHeader extends StatelessWidget {
  const _SheetDragHeader({
    required this.tool,
    required this.onClose,
    required this.showTitle,
  });

  final EditorTool tool;
  final VoidCallback onClose;
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 4),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: LuminaTokens.outline.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              if (showTitle) ...[
                Icon(tool.navIcon, size: 18, color: LuminaTokens.primary),
                const SizedBox(width: 8),
                Text(
                  tool.mobileNavLabel.toUpperCase(),
                  style: AppTypography.sectionCaps(context),
                ),
              ],
              const Spacer(),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Collapse',
                onPressed: onClose,
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
