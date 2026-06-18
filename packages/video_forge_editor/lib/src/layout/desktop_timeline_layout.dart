import 'package:flutter/material.dart';

import '../theme/lumina_tokens.dart';

/// Desktop CapCut-style layout: preview column + resizable inspector.
class DesktopTimelineLayout extends StatelessWidget {
  const DesktopTimelineLayout({
    super.key,
    required this.leftPanel,
    required this.inspectorPanel,
    required this.inspectorWidth,
    required this.onInspectorResize,
  });

  final Widget leftPanel;
  final Widget inspectorPanel;
  final double inspectorWidth;
  final ValueChanged<double> onInspectorResize;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          left: 0,
          right: inspectorWidth,
          top: 0,
          bottom: 0,
          child: leftPanel,
        ),
        Positioned(
          top: 0,
          bottom: 0,
          right: 0,
          width: inspectorWidth,
          child: Row(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragUpdate: (details) {
                  onInspectorResize(
                    (inspectorWidth - details.delta.dx).clamp(
                      LuminaTokens.desktopInspectorMinWidth,
                      LuminaTokens.desktopInspectorMaxWidth,
                    ),
                  );
                },
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeLeftRight,
                  child: Container(
                    width: 8,
                    color: Colors.transparent,
                    child: Center(
                      child: Container(
                        width: 2,
                        height: 32,
                        color: LuminaTokens.outlineVariant,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(child: inspectorPanel),
            ],
          ),
        ),
      ],
    );
  }
}
