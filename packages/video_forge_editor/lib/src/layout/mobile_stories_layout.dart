import 'package:flutter/material.dart';

import '../theme/lumina_tokens.dart';
import '../widgets/frosted_bar.dart';
import '../widgets/editor_bottom_nav.dart';
import '../widgets/timeline_quick_actions.dart';

/// Lumina Edit mobile layout — preview, tool panel, timeline, bottom nav.
class MobileStoriesLayout extends StatefulWidget {
  const MobileStoriesLayout({
    super.key,
    required this.isLoaded,
    required this.title,
    required this.preview,
    required this.scrubberRow,
    required this.timelineSection,
    required this.onClose,
    required this.onExport,
    required this.activeNavTool,
    required this.onNavToolChanged,
    this.toolPanel,
    this.onSplit,
    this.onDelete,
    this.onSpeed,
    this.canSplit = true,
    this.canDelete = false,
    this.hasMusic = false,
    this.compactPreview = false,
    this.textEditChrome,
    this.overlayTracksBar,
  });

  final bool isLoaded;
  final String? title;
  final Widget preview;
  final Widget scrubberRow;
  final Widget timelineSection;
  final VoidCallback onClose;
  final VoidCallback onExport;
  final EditorNavTool activeNavTool;
  final ValueChanged<EditorNavTool> onNavToolChanged;
  final Widget? toolPanel;
  final VoidCallback? onSplit;
  final VoidCallback? onDelete;
  final VoidCallback? onSpeed;
  final bool canSplit;
  final bool canDelete;
  final bool hasMusic;
  final bool compactPreview;
  final Widget? textEditChrome;
  final Widget? overlayTracksBar;

  @override
  State<MobileStoriesLayout> createState() => _MobileStoriesLayoutState();
}

class _MobileStoriesLayoutState extends State<MobileStoriesLayout> {
  bool _timelineExpanded = false;

  bool get _showTimeline =>
      widget.activeNavTool == EditorNavTool.media && widget.textEditChrome == null;

  @override
  Widget build(BuildContext context) {
    debugPrint(
      '[LuminaChrome] build loaded=${widget.isLoaded} nav=${widget.activeNavTool}',
    );

    final previewFactor = widget.compactPreview || widget.toolPanel != null
        ? 0.42
        : (_showTimeline && _timelineExpanded ? 0.52 : 1.0);

    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedAlign(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          alignment: previewFactor < 1 ? Alignment.topCenter : Alignment.center,
          heightFactor: previewFactor,
          child: ColoredBox(
            color: LuminaTokens.canvas,
            child: widget.preview,
          ),
        ),

        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: FrostedBar(
            padding: const EdgeInsets.symmetric(
              horizontal: LuminaTokens.space2,
              vertical: LuminaTokens.space1,
            ),
            child: SafeArea(
              bottom: false,
              child: SizedBox(
                height: LuminaTokens.mobileTopBarHeight - LuminaTokens.space2,
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close, color: LuminaTokens.onSurface),
                      onPressed: widget.onClose,
                      tooltip: 'Close',
                    ),
                    if (widget.title != null)
                      Expanded(
                        child: Text(
                          widget.title!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: LuminaTokens.onSurface,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    else
                      const Spacer(),
                    if (widget.isLoaded)
                      DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius:
                              BorderRadius.circular(LuminaTokens.radiusLg),
                          gradient: const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              LuminaTokens.primaryContainer,
                              LuminaTokens.accent,
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: LuminaTokens.selectionGlow,
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: FilledButton.icon(
                          onPressed: widget.onExport,
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            foregroundColor: LuminaTokens.onPrimaryFixed,
                            shadowColor: Colors.transparent,
                            padding: const EdgeInsets.symmetric(
                              horizontal: LuminaTokens.space3,
                            ),
                          ),
                          icon: const Icon(Icons.ios_share, size: 16),
                          label: const Text('Share', style: TextStyle(fontSize: 13)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),

        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.textEditChrome != null)
                widget.textEditChrome!
              else ...[
                if (widget.toolPanel != null)
                  FrostedBar(
                    borderTop: true,
                    padding: const EdgeInsets.all(LuminaTokens.space3),
                    child: SafeArea(
                      top: false,
                      bottom: false,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.sizeOf(context).height * 0.38,
                        ),
                        child: SingleChildScrollView(child: widget.toolPanel!),
                      ),
                    ),
                  ),
                if (_showTimeline) ...[
                  if (widget.overlayTracksBar != null) widget.overlayTracksBar!,
                  widget.scrubberRow,
                  TimelineQuickActions(
                    onSplit: widget.onSplit,
                    onDelete: widget.onDelete,
                    onSpeed: widget.onSpeed,
                    canSplit: widget.canSplit,
                    canDelete: widget.canDelete,
                  ),
                  FrostedBar(
                    borderTop: true,
                    padding: EdgeInsets.zero,
                    child: SafeArea(
                      top: false,
                      bottom: false,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          InkWell(
                            onTap: () {
                              setState(() => _timelineExpanded = !_timelineExpanded);
                              debugPrint(
                                '[LuminaChrome] timeline expanded=$_timelineExpanded',
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: LuminaTokens.space1,
                              ),
                              child: Icon(
                                _timelineExpanded
                                    ? Icons.keyboard_arrow_down
                                    : Icons.keyboard_arrow_up,
                                color: LuminaTokens.onSurfaceVariant,
                                size: 18,
                              ),
                            ),
                          ),
                          AnimatedCrossFade(
                            duration: const Duration(milliseconds: 200),
                            crossFadeState: _timelineExpanded
                                ? CrossFadeState.showSecond
                                : CrossFadeState.showFirst,
                            firstChild: const SizedBox(height: 0),
                            secondChild: SizedBox(
                              height: 200,
                              child: widget.timelineSection,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
              if (widget.isLoaded)
                EditorBottomNav(
                  active: widget.activeNavTool,
                  onChanged: widget.onNavToolChanged,
                  hasMusic: widget.hasMusic,
                ),
            ],
          ),
        ),
      ],
    );
  }
}
