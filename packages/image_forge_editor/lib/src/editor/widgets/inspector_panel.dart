import 'package:flutter/material.dart';

import '../panels/tool_panels.dart';
import '../theme/editor_icons.dart';
import '../theme/editor_motion.dart';
import '../theme/lumina_tokens.dart';
import 'editor_animations.dart';
import 'frosted_bar.dart';

/// Modernized inspector panel — titled header with the active tool name and
/// Reset / Done buttons, scrollable body, and an optional status footer.
///
/// Body content is a [child] (typically the tool-specific panel) wrapped in
/// a cross-fade [AnimatedPanelSwitcher] keyed on the tool.
class InspectorPanel extends StatelessWidget {
  const InspectorPanel({
    super.key,
    required this.tool,
    required this.child,
    this.onReset,
    this.onDone,
    this.canReset = true,
    this.canDone = true,
    this.statusText,
    this.width = LuminaTokens.desktopInspectorWidth,
  });

  final EditorTool tool;
  final Widget child;
  final VoidCallback? onReset;
  final VoidCallback? onDone;
  final bool canReset;
  final bool canDone;
  final String? statusText;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: LuminaTokens.surfaceContainerLow,
          border: const Border(
            left: BorderSide(color: LuminaTokens.outlineVariant, width: 0.5),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _InspectorHeader(
              tool: tool,
              onReset: canReset ? onReset : null,
              onDone: canDone ? onDone : null,
            ),
            const Divider(height: 1, thickness: 1, color: LuminaTokens.outlineVariant),
            Expanded(
              child: ClipRect(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(
                          LuminaTokens.space4,
                          LuminaTokens.space3,
                          LuminaTokens.space4,
                          LuminaTokens.space4,
                        ),
                        physics: const ClampingScrollPhysics(),
                        child: AnimatedPanelSwitcher(
                          switchKey: tool,
                          child: child,
                        ),
                      ),
                    ),
                    const Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: IgnorePointer(child: _TopFade()),
                    ),
                    const Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: IgnorePointer(child: _BottomFade()),
                    ),
                  ],
                ),
              ),
            ),
            if (statusText != null) ...[
              const Divider(
                height: 1,
                thickness: 1,
                color: LuminaTokens.outlineVariant,
              ),
              FrostedBar(
                height: 32,
                borderTop: false,
                color: LuminaTokens.surfaceContainerLow,
                padding: const EdgeInsets.symmetric(
                  horizontal: LuminaTokens.space4,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    statusText!,
                    style: const TextStyle(
                      fontSize: 11,
                      color: LuminaTokens.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InspectorHeader extends StatelessWidget {
  const _InspectorHeader({
    required this.tool,
    this.onReset,
    this.onDone,
  });

  final EditorTool tool;
  final VoidCallback? onReset;
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: FrostedBar(
        height: 56,
        borderBottom: true,
        color: LuminaTokens.surfaceContainerLow,
        padding: const EdgeInsets.symmetric(horizontal: LuminaTokens.space2),
        child: Row(
          children: [
            Icon(
              EditorIcons.filled(tool),
              size: 18,
              color: LuminaTokens.accent,
            ),
            const SizedBox(width: LuminaTokens.space2),
            Expanded(
              child: AnimatedSwitcher(
                duration: EditorMotion.medium,
                transitionBuilder: (child, animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.05),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  );
                },
                child: Text(
                  tool.label,
                  key: ValueKey(tool),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: LuminaTokens.onSurface,
                  ),
                ),
              ),
            ),
            if (onReset != null)
              TextButton(
                onPressed: onReset,
                child: const Text('Reset'),
              ),
            if (onDone != null)
              FilledButton(
                onPressed: onDone,
                child: const Text('Done'),
              ),
          ],
        ),
      ),
    );
  }
}

class _TopFade extends StatelessWidget {
  const _TopFade();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 24,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              LuminaTokens.surfaceContainerLow,
              LuminaTokens.surfaceContainerLow.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomFade extends StatelessWidget {
  const _BottomFade();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 24,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              LuminaTokens.surfaceContainerLow,
              LuminaTokens.surfaceContainerLow.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}
