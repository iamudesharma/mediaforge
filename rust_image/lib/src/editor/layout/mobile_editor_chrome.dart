import 'dart:ui';

import 'package:flutter/material.dart';
import '../editor_session.dart';
import '../panels/tool_panels.dart';
import '../rust_image_editor_config.dart';
import '../theme/app_typography.dart';
import '../theme/editor_motion.dart';
import '../theme/lumina_tokens.dart';
import '../panels/blank_canvas_sheet.dart';
import '../services/sticker_image_import.dart';
import '../widgets/compare_hold_button.dart';
import 'editor_layout.dart';

/// Lumina-style mobile layout: full-bleed canvas, bottom nav, floating tool sheet (≤40% height).
class MobileEditorLayout extends StatefulWidget {
  const MobileEditorLayout({
    super.key,
    required this.config,
    required this.session,
    required this.tools,
    required this.selectedTool,
    required this.onToolSelected,
    required this.preview,
    required this.toolPanelBuilder,
    required this.compareHeld,
    required this.onCompareHoldStart,
    required this.onCompareHoldEnd,
    this.onExport,
    this.toolBarPlacement = EditorToolBarPlacement.auto,
  });

  final RustImageEditorConfig config;
  final EditorSession session;
  final List<EditorTool> tools;
  final EditorTool selectedTool;
  final ValueChanged<EditorTool> onToolSelected;
  final Widget preview;
  final Widget Function(ScrollController scrollController) toolPanelBuilder;
  final bool compareHeld;
  final VoidCallback onCompareHoldStart;
  final VoidCallback onCompareHoldEnd;
  final Future<void> Function()? onExport;
  final EditorToolBarPlacement toolBarPlacement;

  @override
  State<MobileEditorLayout> createState() => _MobileEditorLayoutState();
}

class _MobileEditorLayoutState extends State<MobileEditorLayout> {
  bool _sheetOpen = false;

  List<EditorTool> get _navTools =>
      widget.tools.where((t) => t.showInBottomNav).toList();

  static const _navBarHeight = 72.0;
  static const _topBarHeight = 52.0;

  void _onToolTap(EditorTool tool) {
    final same = tool == widget.selectedTool && _sheetOpen;
    setState(() => _sheetOpen = !same);
    widget.onToolSelected(tool);
  }

  void _closeSheet() {
    if (!_sheetOpen) return;
    setState(() => _sheetOpen = false);
  }

  Future<void> _addImageSticker(BuildContext context) async {
    await StickerImageImport.importFromGallery(context, widget.session);
    if (!mounted) return;
    widget.onToolSelected(EditorTool.stickers);
    setState(() => _sheetOpen = true);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final bottomPad = media.padding.bottom;
    final topPad = media.padding.top;
    final navTotal = _navBarHeight + bottomPad;
    final topTotal = _topBarHeight + topPad;
    final maxSheetH = media.size.height * LuminaTokens.sheetMaxViewportFraction;

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(child: widget.preview),
        Positioned(
          top: topPad,
          left: 0,
          right: 0,
          height: _topBarHeight,
          child: _LuminaTopBar(
            title: widget.config.title,
            session: widget.session,
            showCompare: widget.config.showCompare,
            compareHeld: widget.compareHeld,
            onCompareHoldStart: widget.onCompareHoldStart,
            onCompareHoldEnd: widget.onCompareHoldEnd,
            onExport: widget.onExport,
            allowBlankCanvas: widget.config.allowBlankCanvas,
            onImportPhoto: widget.tools.contains(EditorTool.import)
                ? () {
                    widget.onToolSelected(EditorTool.import);
                    setState(() => _sheetOpen = true);
                  }
                : null,
            onCreateBlank: widget.config.allowBlankCanvas
                ? () => BlankCanvasSheet.show(context, widget.session)
                : null,
            onAddImageSticker: widget.session.hasImage && !widget.session.busy
                ? () => _addImageSticker(context)
                : null,
          ),
        ),
        if (_sheetOpen) ...[
          Positioned(
            top: topTotal,
            left: 0,
            right: 0,
            bottom: navTotal,
            child: GestureDetector(
              onTap: _closeSheet,
              behavior: HitTestBehavior.opaque,
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: LuminaTokens.sheetBlurSigma,
                  sigmaY: LuminaTokens.sheetBlurSigma,
                ),
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.25),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: navTotal,
            height: maxSheetH,
            child: _MobileDraggableToolPanel(
              key: ValueKey(widget.selectedTool),
              tool: widget.selectedTool,
              onClose: _closeSheet,
              toolPanelBuilder: widget.toolPanelBuilder,
            ),
          ),
        ],
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _LuminaBottomNav(
            tools: _navTools,
            selected: widget.selectedTool,
            sheetOpen: _sheetOpen,
            onToolTap: _onToolTap,
          ),
        ),
      ],
    );
  }
}

class _MobileDraggableToolPanel extends StatefulWidget {
  const _MobileDraggableToolPanel({
    super.key,
    required this.tool,
    required this.onClose,
    required this.toolPanelBuilder,
  });

  final EditorTool tool;
  final VoidCallback onClose;
  final Widget Function(ScrollController scrollController) toolPanelBuilder;

  @override
  State<_MobileDraggableToolPanel> createState() => _MobileDraggableToolPanelState();
}

class _MobileDraggableToolPanelState extends State<_MobileDraggableToolPanel> {
  final _controller = DraggableScrollableController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.isAttached) return;
      _controller.animateTo(
        0.92,
        duration: EditorMotion.medium,
        curve: EditorMotion.enter,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      controller: _controller,
      initialChildSize: 0.92,
      minChildSize: 0.45,
      maxChildSize: 1.0,
      snap: true,
      snapSizes: const [0.45, 0.92, 1.0],
      builder: (context, scrollController) {
        return _LuminaToolSheet(
          tool: widget.tool,
          onClose: widget.onClose,
          child: widget.toolPanelBuilder(scrollController),
        );
      },
    );
  }
}

class _LuminaTopBar extends StatelessWidget {
  const _LuminaTopBar({
    required this.title,
    required this.session,
    required this.showCompare,
    required this.compareHeld,
    required this.onCompareHoldStart,
    required this.onCompareHoldEnd,
    this.onExport,
    this.onImportPhoto,
    this.onCreateBlank,
    this.onAddImageSticker,
    this.allowBlankCanvas = false,
  });

  final String title;
  final EditorSession session;
  final bool showCompare;
  final bool compareHeld;
  final VoidCallback onCompareHoldStart;
  final VoidCallback onCompareHoldEnd;
  final Future<void> Function()? onExport;
  final VoidCallback? onImportPhoto;
  final VoidCallback? onCreateBlank;
  final VoidCallback? onAddImageSticker;
  final bool allowBlankCanvas;

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.maybeOf(context)?.canPop() ?? false;

    return ColoredBox(
      color: LuminaTokens.surfaceContainerLow.withValues(alpha: 0.92),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: LuminaTokens.padSm),
        child: Row(
          children: [
            if (canPop)
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                tooltip: 'Back',
                onPressed: () => Navigator.maybeOf(context)?.pop(),
              )
            else
              const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.undo_rounded, size: 22),
              tooltip: 'Undo',
              onPressed: session.canUndo && !session.busy ? session.undo : null,
            ),
            IconButton(
              icon: const Icon(Icons.redo_rounded, size: 22),
              tooltip: 'Redo',
              onPressed: session.canRedo && !session.busy ? session.redo : null,
            ),
            if (onAddImageSticker != null)
              IconButton(
                icon: const Icon(Icons.add_photo_alternate_outlined, size: 22),
                tooltip: 'Add image sticker',
                onPressed: onAddImageSticker,
              ),
            if (onImportPhoto != null || onCreateBlank != null)
              PopupMenuButton<String>(
                icon: const Icon(Icons.photo_library_outlined, size: 22),
                tooltip: 'Import',
                enabled: !session.busy,
                onSelected: (v) {
                  if (v == 'photo') {
                    onImportPhoto?.call();
                  } else if (v == 'blank') {
                    onCreateBlank?.call();
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'photo',
                    child: ListTile(
                      leading: Icon(Icons.photo_library_outlined),
                      title: Text('Open photo'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  if (allowBlankCanvas && onCreateBlank != null)
                    const PopupMenuItem(
                      value: 'blank',
                      child: ListTile(
                        leading: Icon(Icons.crop_portrait_outlined),
                        title: Text('Blank canvas'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                ],
              ),
            Expanded(
              child: Text(
                title.toUpperCase(),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.brandTitle(context),
              ),
            ),
            if (showCompare)
              CompareHoldButton(
                enabled: session.hasImage,
                active: compareHeld,
                onHoldStart: onCompareHoldStart,
                onHoldEnd: onCompareHoldEnd,
              ),
            _ExportPill(
              enabled: session.hasImage && !session.busy,
              onPressed: onExport,
            ),
          ],
        ),
      ),
    );
  }
}

class _ExportPill extends StatelessWidget {
  const _ExportPill({required this.enabled, this.onPressed});

  final bool enabled;
  final Future<void> Function()? onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: FilledButton(
        onPressed: enabled && onPressed != null ? () => onPressed!() : null,
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          backgroundColor: LuminaTokens.primary,
          foregroundColor: LuminaTokens.onPrimary,
          disabledBackgroundColor: LuminaTokens.surfaceContainerHigh,
          disabledForegroundColor: LuminaTokens.onSurfaceVariant,
        ),
        child: Text(
          'EXPORT',
          style: AppTypography.sectionCaps(context).copyWith(
            fontSize: 11,
            letterSpacing: 0.8,
            color: LuminaTokens.onPrimary,
          ),
        ),
      ),
    );
  }
}

class _LuminaBottomNav extends StatelessWidget {
  const _LuminaBottomNav({
    required this.tools,
    required this.selected,
    required this.sheetOpen,
    required this.onToolTap,
  });

  final List<EditorTool> tools;
  final EditorTool selected;
  final bool sheetOpen;
  final ValueChanged<EditorTool> onToolTap;

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    return ColoredBox(
      color: LuminaTokens.surfaceContainerLow,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomPad, top: 6),
        child: SizedBox(
          height: _MobileEditorLayoutState._navBarHeight - 6,
          child: Row(
            children: [
              for (final t in tools)
                Expanded(
                  child: _LuminaNavItem(
                    icon: t.navIcon,
                    label: t.mobileNavLabel,
                    selected: t == selected,
                    active: t == selected && sheetOpen,
                    onTap: () => onToolTap(t),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LuminaNavItem extends StatelessWidget {
  const _LuminaNavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? LuminaTokens.primary : LuminaTokens.onSurfaceVariant;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: EditorMotion.fast,
              height: 2,
              width: active ? 28 : 0,
              margin: const EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(
                color: LuminaTokens.primary,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
            Icon(icon, size: 24, color: color),
            const SizedBox(height: 4),
            Text(label, style: AppTypography.navLabel(context, selected: selected)),
          ],
        ),
      ),
    );
  }
}

class _LuminaToolSheet extends StatelessWidget {
  const _LuminaToolSheet({
    required this.tool,
    required this.onClose,
    required this.child,
  });

  final EditorTool tool;
  final VoidCallback onClose;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(LuminaTokens.radiusXl)),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: LuminaTokens.sheetBlurSigma,
          sigmaY: LuminaTokens.sheetBlurSigma,
        ),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: Color(0xF2191F31),
            borderRadius: BorderRadius.vertical(top: Radius.circular(LuminaTokens.radiusXl)),
            border: Border(top: BorderSide(color: LuminaTokens.outlineVariant)),
          ),
          child: Column(
            children: [
              GestureDetector(
                onTap: onClose,
                behavior: HitTestBehavior.opaque,
                child: Column(
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: LuminaTokens.outline.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        LuminaTokens.padMd,
                        LuminaTokens.padSm,
                        LuminaTokens.padSm,
                        0,
                      ),
                      child: Row(
                        children: [
                          Icon(tool.navIcon, size: 18, color: LuminaTokens.primary),
                          const SizedBox(width: 8),
                          Text(
                            tool.mobileNavLabel.toUpperCase(),
                            style: AppTypography.sectionCaps(context),
                          ),
                          const Spacer(),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            tooltip: 'Close',
                            onPressed: onClose,
                            icon: const Icon(Icons.keyboard_arrow_down_rounded),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}
