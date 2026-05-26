import 'dart:async';

import 'package:flutter/material.dart';

import '../crop_controller.dart';
import '../editor_session.dart';
import '../panels/tool_panels.dart';
import '../rust_image_editor_config.dart';
import '../theme/app_typography.dart';
import '../theme/editor_motion.dart';
import '../theme/lumina_tokens.dart';
import '../widgets/compare_hold_button.dart';
import 'editor_layout.dart';
import 'mobile_chrome_metrics.dart';
import 'mobile_tool_sheet.dart';

/// Lumina-style mobile layout: inset canvas, bottom nav, tool sheet (≤40% viewport).
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

enum _SheetExpansion { closed, peek, expanded }

class _MobileEditorLayoutState extends State<MobileEditorLayout> {
  bool _sheetOpen = false;
  _SheetExpansion _sheetExpansion = _SheetExpansion.expanded;
  double _sheetExtent = 0;

  List<EditorTool> get _navTools =>
      widget.tools.where((t) => t.showInMobileBottomNav).toList();

  static const _navBarHeight = 72.0;
  static const _topBarHeight = 52.0;

  bool get _navOnTop {
    final p = widget.toolBarPlacement;
    if (p == EditorToolBarPlacement.top) return true;
    if (p == EditorToolBarPlacement.bottom) return false;
    return false;
  }

  bool get _showContextStrip =>
      widget.contextStripBuilder != null &&
      _sheetOpen &&
      widget.selectedTool.hasMobileContextStrip;

  void _notifyMetrics({
    required double topTotal,
    required double navTotal,
    required double maxSheetH,
  }) {
    final sheetH = _sheetOpen ? _sheetExtent : 0.0;
    final metrics = MobileChromeMetrics(
      topInset: topTotal,
      bottomInset: navTotal + sheetH,
      stripHeight: 0,
      sheetHeight: sheetH,
    );
    widget.onMetricsChanged?.call(metrics);
  }

  void _onToolTap(EditorTool tool) {
    if (tool != widget.selectedTool) {
      widget.onToolSelected(tool);
      setState(() {
        _sheetOpen = true;
        _sheetExpansion = _SheetExpansion.expanded;
      });
      return;
    }
    if (!_sheetOpen) {
      setState(() {
        _sheetOpen = true;
        _sheetExpansion = _SheetExpansion.expanded;
      });
      return;
    }
    setState(() {
      _sheetExpansion = _sheetExpansion == _SheetExpansion.expanded
          ? _SheetExpansion.peek
          : _SheetExpansion.expanded;
    });
  }

  void _closeSheet() {
    if (!_sheetOpen) return;
    setState(() {
      _sheetOpen = false;
      _sheetExpansion = _SheetExpansion.closed;
      _sheetExtent = 0;
    });
  }

  double _peekChildSize(double maxSheetH) {
    final minPx = _showContextStrip ? 220.0 : 168.0;
    return (minPx / maxSheetH).clamp(
      LuminaTokens.sheetPeekChildSize,
      LuminaTokens.sheetExpandedChildSize - 0.04,
    );
  }

  double _targetSheetChildSize(double maxSheetH) {
    final peek = _peekChildSize(maxSheetH);
    return switch (_sheetExpansion) {
      _SheetExpansion.peek => peek,
      _SheetExpansion.expanded => LuminaTokens.sheetExpandedChildSize,
      _SheetExpansion.closed => peek,
    };
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final bottomPad = media.padding.bottom;
    final topPad = media.padding.top;
    final navTotal = _navBarHeight + bottomPad;
    final topTotal = _topBarHeight + topPad;
    final maxSheetH = media.size.height * LuminaTokens.sheetMaxViewportFraction;

    _notifyMetrics(
      topTotal: topTotal,
      navTotal: navTotal,
      maxSheetH: maxSheetH,
    );

    final sheetH = _sheetOpen ? _sheetExtent : 0.0;
    final metrics = MobileChromeMetrics(
      topInset: topTotal,
      bottomInset: navTotal + sheetH,
      stripHeight: 0,
      sheetHeight: sheetH,
    );

    final preview = widget.previewBuilder(metrics);
    final topBar = _LuminaTopBar(
      title: widget.config.title,
      session: widget.session,
      showCompare: widget.config.showCompare,
      compareHeld: widget.compareHeld,
      onCompareHoldStart: widget.onCompareHoldStart,
      onCompareHoldEnd: widget.onCompareHoldEnd,
      onExport: widget.onExport,
      showCropDone: widget.selectedTool == EditorTool.transform &&
          widget.cropController != null,
      onCropDone: widget.cropController != null
          ? () => widget.session.applyCrop(crop: widget.cropController!)
          : null,
      onAddImageSticker: widget.session.hasImage && !widget.session.busy
          ? () {
              widget.onToolSelected(EditorTool.stickers);
              setState(() {
                _sheetOpen = true;
                _sheetExpansion = _SheetExpansion.expanded;
              });
            }
          : null,
    );

    final bottomNav = _LuminaBottomNav(
      tools: _navTools,
      selected: widget.selectedTool,
      sheetOpen: _sheetOpen,
      onToolTap: _onToolTap,
    );

    final contextStrip = _showContextStrip
        ? widget.contextStripBuilder!(widget.selectedTool)
        : null;

    final sheet = _sheetOpen
        ? _MobileDraggableToolPanel(
            key: ValueKey('${widget.selectedTool}_${_sheetExpansion.name}'),
            tool: widget.selectedTool,
            contextStrip: contextStrip,
            initialChildSize: _targetSheetChildSize(maxSheetH),
            minChildSize: _peekChildSize(maxSheetH),
            onClose: _closeSheet,
            onExtentChanged: (extent) {
              if (!mounted) return;
              setState(() => _sheetExtent = extent);
            },
            toolPanelBuilder: widget.toolPanelBuilder,
          )
        : null;

    final metaOverlay = widget.showMobileMetaOverlay
        ? Positioned(
            top: topTotal + 8,
            right: 8,
            left: 8,
            child: Align(
              alignment: Alignment.topRight,
              child: _MobileMetaOverlay(session: widget.session),
            ),
          )
        : null;

    if (_navOnTop) {
      return _buildStackTopNav(
        preview: preview,
        topBar: topBar,
        bottomNav: bottomNav,
        contextStrip: contextStrip,
        sheet: sheet,
        overlay: widget.overlay,
        metaOverlay: metaOverlay,
        topTotal: topTotal,
        navTotal: navTotal,
        maxSheetH: maxSheetH,
      );
    }

    return _buildStackBottomNav(
      preview: preview,
      topBar: topBar,
      bottomNav: bottomNav,
      contextStrip: contextStrip,
      sheet: sheet,
      overlay: widget.overlay,
      metaOverlay: metaOverlay,
      topTotal: topTotal,
      navTotal: navTotal,
      maxSheetH: maxSheetH,
    );
  }

  Widget _buildStackBottomNav({
    required Widget preview,
    required Widget topBar,
    required Widget bottomNav,
    required Widget? contextStrip,
    required Widget? sheet,
    required Widget? overlay,
    required Widget? metaOverlay,
    required double topTotal,
    required double navTotal,
    required double maxSheetH,
  }) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          top: topTotal,
          left: 0,
          right: 0,
          bottom: navTotal,
          child: preview,
        ),
        if (widget.canvasChrome != null)
          Positioned(
            top: topTotal + 8,
            left: 8,
            child: widget.canvasChrome!,
          ),
        Positioned(
          top: topPadSafe(context),
          left: 0,
          right: 0,
          height: _topBarHeight,
          child: topBar,
        ),
        if (sheet != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: navTotal,
            height: maxSheetH,
            child: sheet,
          ),
        Positioned(left: 0, right: 0, bottom: 0, child: bottomNav),
        if (overlay != null) Positioned.fill(child: overlay),
        if (metaOverlay != null) metaOverlay,
      ],
    );
  }

  Widget _buildStackTopNav({
    required Widget preview,
    required Widget topBar,
    required Widget bottomNav,
    required Widget? contextStrip,
    required Widget? sheet,
    required Widget? overlay,
    required Widget? metaOverlay,
    required double topTotal,
    required double navTotal,
    required double maxSheetH,
  }) {
    final topChrome = _topBarHeight + _navBarHeight + topPadSafe(context);

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          top: topChrome,
          left: 0,
          right: 0,
          bottom: 0,
          child: preview,
        ),
        if (widget.canvasChrome != null)
          Positioned(
            top: topChrome + 8,
            left: 8,
            child: widget.canvasChrome!,
          ),
        Positioned(
          top: topPadSafe(context),
          left: 0,
          right: 0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: _topBarHeight, child: topBar),
              bottomNav,
            ],
          ),
        ),
        if (sheet != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: maxSheetH,
            child: sheet,
          ),
        if (overlay != null) Positioned.fill(child: overlay),
        if (metaOverlay != null)
          Positioned(
            top: topChrome + 8,
            right: 8,
            child: _MobileMetaOverlay(session: widget.session),
          ),
      ],
    );
  }

  double topPadSafe(BuildContext context) => MediaQuery.paddingOf(context).top;
}

class _MobileDraggableToolPanel extends StatefulWidget {
  const _MobileDraggableToolPanel({
    super.key,
    required this.tool,
    required this.initialChildSize,
    required this.minChildSize,
    required this.onClose,
    required this.onExtentChanged,
    required this.toolPanelBuilder,
    this.contextStrip,
  });

  final EditorTool tool;
  final double initialChildSize;
  final double minChildSize;
  final VoidCallback onClose;
  final ValueChanged<double> onExtentChanged;
  final Widget Function() toolPanelBuilder;
  final Widget? contextStrip;

  @override
  State<_MobileDraggableToolPanel> createState() =>
      _MobileDraggableToolPanelState();
}

class _MobileDraggableToolPanelState extends State<_MobileDraggableToolPanel> {
  final _controller = DraggableScrollableController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_reportExtent);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _seedExtent();
      _animateToTarget();
    });
  }

  void _seedExtent() {
    final box = context.findRenderObject() as RenderBox?;
    if (box != null) {
      widget.onExtentChanged(widget.initialChildSize * box.size.height);
    }
  }

  @override
  void didUpdateWidget(covariant _MobileDraggableToolPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialChildSize != widget.initialChildSize) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _animateToTarget());
    }
  }

  void _reportExtent() {
    if (!_controller.isAttached || !mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    widget.onExtentChanged(_controller.size * box.size.height);
  }

  Future<void> _animateToTarget() async {
    if (!mounted || !_controller.isAttached) return;
    await _controller.animateTo(
      widget.initialChildSize,
      duration: EditorMotion.medium,
      curve: EditorMotion.enter,
    );
    _reportExtent();
  }

  @override
  void dispose() {
    _controller.removeListener(_reportExtent);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<DraggableScrollableNotification>(
      onNotification: (n) {
        final parent = context.findRenderObject() as RenderBox?;
        if (parent != null) {
          widget.onExtentChanged(n.extent * parent.size.height);
        }
        return false;
      },
      child: DraggableScrollableSheet(
        expand: true,
        controller: _controller,
        initialChildSize: widget.initialChildSize,
        minChildSize: widget.minChildSize,
        maxChildSize: LuminaTokens.sheetMaxChildSize,
        snap: true,
        snapSizes: [
          widget.minChildSize,
          LuminaTokens.sheetExpandedChildSize,
          LuminaTokens.sheetMaxChildSize,
        ],
        builder: (context, _) {
          return MobileToolSheet(
            tool: widget.tool,
            onClose: widget.onClose,
            contextStrip: widget.contextStrip,
            sheetController: _controller,
            minSheetFraction: widget.minChildSize,
            maxSheetFraction: LuminaTokens.sheetMaxChildSize,
            child: widget.toolPanelBuilder(),
          );
        },
      ),
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
    this.onAddImageSticker,
    this.showCropDone = false,
    this.onCropDone,
  });

  final String title;
  final EditorSession session;
  final bool showCompare;
  final bool compareHeld;
  final VoidCallback onCompareHoldStart;
  final VoidCallback onCompareHoldEnd;
  final Future<void> Function()? onExport;
  final VoidCallback? onAddImageSticker;
  final bool showCropDone;
  final VoidCallback? onCropDone;

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
              onPressed: session.canUndo && !session.busy
                  ? () => unawaited(session.undo())
                  : null,
            ),
            IconButton(
              icon: const Icon(Icons.redo_rounded, size: 22),
              tooltip: 'Redo',
              onPressed: session.canRedo && !session.busy
                  ? () => unawaited(session.redo())
                  : null,
            ),
            if (showCropDone && onCropDone != null)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: FilledButton(
                  onPressed: session.busy ? null : onCropDone,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(64, 36),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                  ),
                  child: const Text('Done'),
                ),
              ),
            if (onAddImageSticker != null)
              IconButton(
                icon: const Icon(Icons.add_photo_alternate_outlined, size: 22),
                tooltip: 'Add image sticker',
                onPressed: onAddImageSticker,
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
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            itemCount: tools.length,
            separatorBuilder: (_, __) => const SizedBox(width: 2),
            itemBuilder: (context, i) {
              final t = tools[i];
              return SizedBox(
                width: 68,
                child: _LuminaNavItem(
                  icon: t.navIcon,
                  label: t.mobileNavLabel,
                  selected: t == selected,
                  active: t == selected && sheetOpen,
                  onTap: () => onToolTap(t),
                ),
              );
            },
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
    final color =
        selected ? LuminaTokens.primary : LuminaTokens.onSurfaceVariant;

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
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.navLabel(context, selected: selected),
            ),
          ],
        ),
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
      session.sizeLabel,
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
            DecoratedBox(
              decoration: BoxDecoration(
                color: LuminaTokens.surfaceContainerHighest.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: LuminaTokens.outline.withValues(alpha: 0.2),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: LuminaTokens.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
