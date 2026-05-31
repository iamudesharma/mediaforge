import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../editor_session.dart';
import '../services/beauty_look_names.dart';
import '../theme/editor_motion.dart';
import '../theme/lumina_tokens.dart';

/// Horizontal swipe on preview to browse beauty looks (Beauty tool only).
class SwipeBeautyLookLayer extends StatefulWidget {
  const SwipeBeautyLookLayer({
    super.key,
    required this.session,
    required this.enabled,
    required this.viewerScale,
    required this.child,
  });

  final EditorSession session;
  final bool enabled;
  final double viewerScale;
  final Widget child;

  @override
  State<SwipeBeautyLookLayer> createState() => _SwipeBeautyLookLayerState();
}

class _SwipeBeautyLookLayerState extends State<SwipeBeautyLookLayer> {
  static const _stepPx = 72.0;
  static const _zoomSwipeThreshold = 1.05;

  int _dragStartIndex = 0;
  double _dragAccum = 0;
  int _previewIndex = 0;
  bool _dragging = false;
  bool _labelVisible = false;
  Timer? _hideLabelTimer;

  bool get _swipeActive =>
      widget.enabled &&
      widget.viewerScale <= _zoomSwipeThreshold &&
      widget.session.hasImage &&
      !widget.session.busy &&
      !widget.session.faceAnalyzing &&
      widget.session.skinMask != null;

  @override
  void dispose() {
    _hideLabelTimer?.cancel();
    super.dispose();
  }

  void _showLabel() {
    _hideLabelTimer?.cancel();
    if (!_labelVisible) setState(() => _labelVisible = true);
    _hideLabelTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted && !_dragging) {
        setState(() => _labelVisible = false);
      }
    });
  }

  void _applyIndex(int index, {required bool commit}) {
    final look = beautyLookAtIndex(index);
    unawaited(
      widget.session.setBeautyLook(
        look,
        livePreview: !commit,
        commit: commit,
      ),
    );
  }

  String _labelForIndex(int index) {
    if (index <= 0) return 'Original';
    final look = beautyLookAtIndex(index);
    return look == null ? 'Original' : beautyLookLabel(look);
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    return ListenableBuilder(
      listenable: Listenable.merge([
        session.beautyPreviewListenable,
        session.processingListenable,
        session.faceChromeListenable,
      ]),
      builder: (context, _) {
        final look = widget.session.previewBeautyLook ??
            widget.session.committedBeautyLook;
        final label = look == null ? 'Original' : beautyLookLabel(look);

        return Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragStart: _swipeActive
                  ? (_) {
                      _dragging = true;
                      _dragAccum = 0;
                      _dragStartIndex = beautyLookIndex(
                        widget.session.committedBeautyLook,
                      );
                      _previewIndex = _dragStartIndex;
                      _showLabel();
                    }
                  : null,
              onHorizontalDragUpdate: _swipeActive
                  ? (details) {
                      _dragAccum += details.delta.dx;
                      final steps = (-_dragAccum / _stepPx).round();
                      final next = (_dragStartIndex + steps)
                          .clamp(0, beautyLookCount - 1);
                      if (next != _previewIndex) {
                        _previewIndex = next;
                        HapticFeedback.selectionClick();
                        _applyIndex(next, commit: false);
                        _showLabel();
                      }
                    }
                  : null,
              onHorizontalDragEnd: _swipeActive
                  ? (_) {
                      _dragging = false;
                      _applyIndex(_previewIndex, commit: true);
                      _showLabel();
                    }
                  : null,
              onHorizontalDragCancel: _swipeActive
                  ? () {
                      _dragging = false;
                      unawaited(widget.session.cancelBeautyLookPreview());
                    }
                  : null,
              child: widget.child,
            ),
            if (_labelVisible && _swipeActive)
              Positioned(
                top: 16,
                left: 0,
                right: 0,
                child: Center(
                  child: AnimatedOpacity(
                    opacity: _labelVisible ? 1 : 0,
                    duration: EditorMotion.fast,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: LuminaTokens.surfaceContainerHigh
                            .withValues(alpha: 0.88),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: LuminaTokens.outlineVariant,
                        ),
                      ),
                      child: Text(
                        _dragging ? _labelForIndex(_previewIndex) : label,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: LuminaTokens.onSurface,
                            ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
