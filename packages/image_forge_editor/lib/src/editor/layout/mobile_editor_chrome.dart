import 'dart:async';

import 'package:flutter/material.dart';

import '../crop_controller.dart';
import '../editor_session.dart';
import '../image_forge_editor_config.dart';
import '../panels/tool_panels.dart';
import '../theme/app_typography.dart';
import '../theme/lumina_tokens.dart';
import '../widgets/compare_hold_button.dart';
import '../widgets/frosted_bar.dart';
import '../widgets/tool_button.dart';
import 'editor_layout.dart';
import 'mobile_chrome_metrics.dart';

/// Modernized mobile layout: 5 curated tools + "More" overflow sheet,
/// draggable tool sheet with grabber, and a frosted title bar that shows
/// the active tool name (no more all-caps "LUMINA" title).
class MobileEditorLayout extends StatefulWidget {
  const MobileEditorLayout({
    super.key,
    required this.config,
    required this.session,
    required this.tools,
    required this.selectedTool,
    required this.onToolSelected,
    required this.previewBuilder,
    required this.toolPanelBuilder,
    required this.compareHeld,
    required this.onCompareHoldStart,
    required this.onCompareHoldEnd,
    this.onExport,
    this.cropController,
    this.toolBarPlacement = EditorToolBarPlacement.auto,
    this.showMobileMetaOverlay = false,
    this.contextStripBuilder,
    this.overlay,
    this.onMetricsChanged,
    this.canvasChrome,
  });

  final RustImageEditorConfig config;
  final EditorSession session;
  final List<EditorTool> tools;
  final EditorTool selectedTool;
  final ValueChanged<EditorTool> onToolSelected;
  final Widget Function(MobileChromeMetrics metrics) previewBuilder;
  final Widget Function() toolPanelBuilder;
  final bool compareHeld;
  final VoidCallback onCompareHoldStart;
  final VoidCallback onCompareHoldEnd;
  final Future<void> Function()? onExport;
  final CropController? cropController;
  final EditorToolBarPlacement toolBarPlacement;
  final bool showMobileMetaOverlay;
  final Widget Function(EditorTool tool)? contextStripBuilder;
  final Widget? overlay;
  final ValueChanged<MobileChromeMetrics>? onMetricsChanged;
  final Widget? canvasChrome;

  @override
  State<MobileEditorLayout> createState() => _MobileEditorLayoutState();
}

class _MobileEditorLayoutState extends State<MobileEditorLayout> {
  bool _sheetOpen = false;
  EditorTool _displayedTool = EditorTool.adjust;

  /// Curated primary tools (5) — match CapCut / Instagram / Apple Photos.
  static const List<EditorTool> _primaryTools = <EditorTool>[
    EditorTool.transform,
    EditorTool.filters,
    EditorTool.adjust,
    EditorTool.stickers,
    EditorTool.paint,
  ];

  /// Tools surfaced in the "More" overflow sheet.
  List<EditorTool> get _moreTools {
    final all = widget.tools
        .where((t) => !_primaryTools.contains(t) && t != EditorTool.export_)
        .toList();
    return all;
  }

  bool get _showContextStrip =>
      widget.contextStripBuilder != null && _sheetOpen;

  @override
  void didUpdateWidget(covariant MobileEditorLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedTool != widget.selectedTool) {
      _displayedTool = widget.selectedTool;
    }
  }

  @override
  void initState() {
    super.initState();
    _displayedTool = widget.selectedTool;
  }

  void _onToolTap(EditorTool tool) {
    if (tool != widget.selectedTool) {
      widget.onToolSelected(tool);
      setState(() {
        _displayedTool = tool;
        _sheetOpen = true;
      });
      return;
    }
    setState(() {
      _sheetOpen = !_sheetOpen;
    });
  }

  void _openMoreSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => _MoreToolsSheet(
        tools: _moreTools,
        current: widget.selectedTool,
        onSelected: (tool) {
          Navigator.of(sheetCtx).pop();
          _onToolTap(tool);
        },
      ),
    );
  }

  void _closeSheet() {
    if (!_sheetOpen) return;
    setState(() {
      _sheetOpen = false;
    });
  }

  Future<void> _onApply() async {
    final s = widget.session;
    if (widget.selectedTool == EditorTool.transform && widget.cropController != null) {
      await s.applyCrop(crop: widget.cropController!);
    } else if (widget.selectedTool == EditorTool.paint ||
        widget.selectedTool == EditorTool.draw ||
        widget.selectedTool == EditorTool.overlay) {
      if (s.hasUncommittedLayers) {
        await s.commitLayersToCanvas();
      }
    }
    _closeSheet();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final bottomPad = media.padding.bottom;
    final topPad = media.padding.top;
    final navTotal = LuminaTokens.mobileBottomBarHeight + bottomPad;
    final topTotal = LuminaTokens.mobileTopBarHeight + topPad;
    final sheetH = _sheetOpen ? 320.0 : 0.0;
    final bottomInset = _sheetOpen ? (sheetH + bottomPad) : navTotal;

    final metrics = MobileChromeMetrics(
      topInset: topTotal,
      bottomInset: bottomInset,
      stripHeight: 0,
      sheetHeight: sheetH,
    );
    widget.onMetricsChanged?.call(metrics);

    final preview = widget.previewBuilder(metrics);
    final topBar = _MobileTopBar(
      title: _displayedTool.mobileNavLabel,
      session: widget.session,
      showCompare: widget.config.showCompare,
      compareHeld: widget.compareHeld,
      onCompareHoldStart: widget.onCompareHoldStart,
      onCompareHoldEnd: widget.onCompareHoldEnd,
      onExport: widget.onExport,
      onBack: widget.session.hasImage
          ? () => Navigator.maybeOf(context)?.pop()
          : () => Navigator.maybeOf(context)?.pop(),
    );

    final bottomNav = _MobileBottomNav(
      primaryTools: _primaryTools,
      moreTools: _moreTools,
      selected: widget.selectedTool,
      onToolTap: _onToolTap,
      onMoreTap: _openMoreSheet,
    );

    final sheet = _sheetOpen
        ? _MobileToolSheetHost(
            key: ValueKey('${widget.selectedTool}_edit'),
            tool: widget.selectedTool,
            onCancel: _closeSheet,
            onApply: _onApply,
            child: widget.toolPanelBuilder(),
            contextStrip: _showContextStrip
                ? widget.contextStripBuilder!(widget.selectedTool)
                : null,
          )
        : null;

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          top: topTotal,
          left: 0,
          right: 0,
          bottom: bottomInset,
          child: preview,
        ),
        if (widget.canvasChrome != null)
          Positioned(
            top: topTotal + LuminaTokens.space2,
            left: LuminaTokens.space2,
            child: widget.canvasChrome!,
          ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: topTotal,
          child: topBar,
        ),
        if (sheet != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: sheet,
          )
        else
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: bottomNav,
          ),
        if (widget.overlay != null) Positioned.fill(child: widget.overlay!),
        if (widget.showMobileMetaOverlay)
          Positioned(
            top: topTotal + 8,
            right: LuminaTokens.space3,
            child: _MobileMetaOverlay(session: widget.session),
          ),
      ],
    );
  }
}

class _MobileTopBar extends StatelessWidget {
  const _MobileTopBar({
    required this.title,
    required this.session,
    required this.showCompare,
    required this.compareHeld,
    required this.onCompareHoldStart,
    required this.onCompareHoldEnd,
    this.onExport,
    this.onBack,
  });

  final String title;
  final EditorSession session;
  final bool showCompare;
  final bool compareHeld;
  final VoidCallback onCompareHoldStart;
  final VoidCallback onCompareHoldEnd;
  final Future<void> Function()? onExport;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: FrostedBar(
        height: LuminaTokens.mobileTopBarHeight,
        borderBottom: true,
        color: LuminaTokens.surfaceContainerLow.withValues(alpha: 0.85),
        padding: const EdgeInsets.symmetric(horizontal: LuminaTokens.space2),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
              tooltip: 'Back',
              onPressed: onBack,
            ),
            const SizedBox(width: LuminaTokens.space2),
            Expanded(
              child: Center(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.toolName(context),
                ),
              ),
            ),
            if (showCompare)
              CompareHoldButton(
                enabled: session.hasImage,
                active: compareHeld,
                onHoldStart: onCompareHoldStart,
                onHoldEnd: onCompareHoldEnd,
              ),
            IconButton(
              icon: const Icon(Icons.save_alt_rounded, size: 22),
              tooltip: 'Export',
              onPressed: session.hasImage && !session.busy && onExport != null
                  ? () => onExport!()
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileBottomNav extends StatelessWidget {
  const _MobileBottomNav({
    required this.primaryTools,
    required this.moreTools,
    required this.selected,
    required this.onToolTap,
    required this.onMoreTap,
  });

  final List<EditorTool> primaryTools;
  final List<EditorTool> moreTools;
  final EditorTool selected;
  final ValueChanged<EditorTool> onToolTap;
  final VoidCallback onMoreTap;

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    return SafeArea(
      top: false,
      child: FrostedBar(
        height: LuminaTokens.mobileBottomBarHeight + bottomPad,
        borderTop: true,
        color: LuminaTokens.surfaceContainerLow.withValues(alpha: 0.85),
        padding: EdgeInsets.only(
          left: LuminaTokens.space2,
          right: LuminaTokens.space2,
          bottom: bottomPad,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final tool in primaryTools)
              ToolButton(
                tool: tool,
                selected: tool == selected,
                onTap: () => onToolTap(tool),
              ),
            if (moreTools.isNotEmpty)
              ToolButton(
                tool: EditorTool.advanced,
                selected: moreTools.contains(selected),
                onTap: onMoreTap,
                tooltip: 'More',
              ),
          ],
        ),
      ),
    );
  }
}

class _MoreToolsSheet extends StatelessWidget {
  const _MoreToolsSheet({
    required this.tools,
    required this.current,
    required this.onSelected,
  });

  final List<EditorTool> tools;
  final EditorTool current;
  final ValueChanged<EditorTool> onSelected;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Material(
          color: LuminaTokens.surfaceContainer,
          elevation: 12,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(LuminaTokens.radiusXl),
          ),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                const SizedBox(height: LuminaTokens.space2),
                Container(
                  width: LuminaTokens.sheetGrabberWidth,
                  height: LuminaTokens.sheetGrabberHeight,
                  decoration: BoxDecoration(
                    color: LuminaTokens.outline.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: LuminaTokens.space2),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: LuminaTokens.space4,
                    vertical: LuminaTokens.space2,
                  ),
                  child: Row(
                    children: [
                      const Text(
                        'More tools',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: LuminaTokens.onSurface,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: GridView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(
                      horizontal: LuminaTokens.space4,
                      vertical: LuminaTokens.space3,
                    ),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      childAspectRatio: 0.95,
                      crossAxisSpacing: LuminaTokens.space3,
                      mainAxisSpacing: LuminaTokens.space3,
                    ),
                    itemCount: tools.length,
                    itemBuilder: (context, i) {
                      final tool = tools[i];
                      return ToolButton(
                        tool: tool,
                        selected: tool == current,
                        onTap: () => onSelected(tool),
                        showLabel: true,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MobileToolSheetHost extends StatelessWidget {
  const _MobileToolSheetHost({
    super.key,
    required this.tool,
    required this.child,
    required this.onCancel,
    required this.onApply,
    this.contextStrip,
  });

  final EditorTool tool;
  final Widget child;
  final VoidCallback onCancel;
  final VoidCallback onApply;
  final Widget? contextStrip;

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    return Material(
      color: LuminaTokens.surfaceContainer,
      elevation: 12,
      shadowColor: Colors.black.withValues(alpha: 0.45),
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(LuminaTokens.radiusXl),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: LuminaTokens.space2),
          Container(
            width: LuminaTokens.sheetGrabberWidth,
            height: LuminaTokens.sheetGrabberHeight,
            decoration: BoxDecoration(
              color: LuminaTokens.outline.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          if (contextStrip != null) ...[
            const SizedBox(height: LuminaTokens.space2),
            contextStrip!,
            const Divider(height: 1, thickness: 1, color: LuminaTokens.outlineVariant),
          ],
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.55,
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                LuminaTokens.space4,
                LuminaTokens.space3,
                LuminaTokens.space4,
                LuminaTokens.space4 + bottomPad,
              ),
              child: child,
            ),
          ),
          const Divider(height: 1, thickness: 1, color: LuminaTokens.outlineVariant),
          _MobileEditBar(tool: tool, onCancel: onCancel, onApply: onApply),
        ],
      ),
    );
  }
}

class _MobileEditBar extends StatelessWidget {
  const _MobileEditBar({
    required this.tool,
    required this.onCancel,
    required this.onApply,
  });

  final EditorTool tool;
  final VoidCallback onCancel;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      color: LuminaTokens.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: LuminaTokens.space2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TextButton.icon(
            onPressed: onCancel,
            icon: const Icon(Icons.close_rounded, size: 18),
            label: const Text('Cancel'),
          ),
          Text(
            tool.mobileNavLabel,
            style: AppTypography.sectionCaps(context).copyWith(
              color: LuminaTokens.onSurface,
              fontSize: 11,
            ),
          ),
          TextButton.icon(
            onPressed: onApply,
            icon: const Icon(Icons.check_rounded, size: 18, color: LuminaTokens.accent),
            label: const Text(
              'Apply',
              style: TextStyle(color: LuminaTokens.accent),
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileMetaOverlay extends StatelessWidget {
  const _MobileMetaOverlay({required this.session});

  final EditorSession session;

  @override
  Widget build(BuildContext context) {
    if (!session.hasImage) return const SizedBox.shrink();

    final gpu = session.gpuInfo;
    final labels = <String>[
      session.dimensionsLabel,
      if (session.rgbaPipeline) 'RGBA',
      if (gpu?.available == true) gpu!.api,
    ];

    return Material(
      color: Colors.transparent,
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (final label in labels)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: LuminaTokens.surfaceContainerHighest
                    .withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: LuminaTokens.outline.withValues(alpha: 0.2),
                ),
              ),
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: LuminaTokens.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
