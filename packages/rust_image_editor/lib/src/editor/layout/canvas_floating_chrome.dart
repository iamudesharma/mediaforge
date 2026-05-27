import 'package:flutter/material.dart';
import 'package:rust_image_editor/src/rust_image_editor.dart';

import '../editor_session.dart';
import '../panels/layers_panel.dart';
import '../services/rust_worker.dart';
import '../theme/lumina_tokens.dart';

/// Instagram-style controls over the canvas: flip + compact layers (no bottom sheet).
class CanvasFloatingChrome extends StatefulWidget {
  const CanvasFloatingChrome({
    super.key,
    required this.session,
    this.showFlip = true,
    this.showLayers = true,
  });

  final EditorSession session;
  final bool showFlip;
  final bool showLayers;

  @override
  State<CanvasFloatingChrome> createState() => _CanvasFloatingChromeState();
}

class _CanvasFloatingChromeState extends State<CanvasFloatingChrome> {
  bool _layersOpen = false;

  Future<void> _flip(Rotation rotation) async {
    final s = widget.session;
    if (!s.hasImage || s.busy) return;
    await s.runBytes(
      rotation == Rotation.flipHorizontal ? 'Flip H' : 'Flip V',
      (input) => RustWorker.bytesTransform(
        bytes: input,
        op: 'rotate',
        params: {
          'rotation': rotation.index,
          'format': s.outputFormat.index,
          'quality': s.quality,
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    if (!s.hasImage) return const SizedBox.shrink();

    return ListenableBuilder(
      listenable: s.layerListenable,
      builder: (context, _) {
        final layerCount = s.layerStack.layers.length;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.showFlip) ...[
                  _ChromeIconButton(
                    icon: Icons.flip,
                    tooltip: 'Flip horizontal',
                    onPressed: s.busy
                        ? null
                        : () => _flip(Rotation.flipHorizontal),
                  ),
                  const SizedBox(width: 6),
                  _ChromeIconButton(
                    icon: Icons.flip_camera_android_outlined,
                    tooltip: 'Flip vertical',
                    onPressed: s.busy
                        ? null
                        : () => _flip(Rotation.flipVertical),
                  ),
                  if (widget.showLayers) const SizedBox(width: 6),
                ],
                if (widget.showLayers)
                  _ChromeIconButton(
                    icon: Icons.layers_outlined,
                    tooltip: 'Layers',
                    selected: _layersOpen,
                    badge: layerCount > 0 ? '$layerCount' : null,
                    onPressed: s.busy
                        ? null
                        : () => setState(() => _layersOpen = !_layersOpen),
                  ),
              ],
            ),
            if (_layersOpen && widget.showLayers) ...[
              const SizedBox(height: 8),
              _LayersPopover(
                session: s,
                onClose: () => setState(() => _layersOpen = false),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _ChromeIconButton extends StatelessWidget {
  const _ChromeIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
    this.badge,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool selected;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: LuminaTokens.surfaceContainerHighest.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(LuminaTokens.radiusMd),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(LuminaTokens.radiusMd),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(LuminaTokens.radiusMd),
            border: Border.all(
              color: selected
                  ? LuminaTokens.primary
                  : LuminaTokens.outline.withValues(alpha: 0.35),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(
                icon,
                size: 22,
                color: selected
                    ? LuminaTokens.primary
                    : LuminaTokens.onSurface,
              ),
              if (badge != null)
                Positioned(
                  top: 4,
                  right: 4,
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      color: LuminaTokens.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Text(
                        badge!,
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: LuminaTokens.onPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LayersPopover extends StatelessWidget {
  const _LayersPopover({
    required this.session,
    required this.onClose,
  });

  final EditorSession session;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.sizeOf(context);
    return Material(
      elevation: 8,
      color: LuminaTokens.surfaceContainer.withValues(alpha: 0.98),
      borderRadius: BorderRadius.circular(LuminaTokens.radiusMd),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: media.width * 0.78,
          maxHeight: media.height * 0.32,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
              child: Row(
                children: [
                  const Icon(
                    Icons.layers_outlined,
                    size: 18,
                    color: LuminaTokens.primary,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'LAYERS',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: LuminaTokens.onSurface,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: onClose,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: LayersPanel(session: session, compact: true),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
