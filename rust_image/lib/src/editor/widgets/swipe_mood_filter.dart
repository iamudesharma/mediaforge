import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../editor_session.dart';
import '../services/mood_filter_names.dart';
import '../theme/editor_motion.dart';
import '../theme/lumina_tokens.dart';

/// Horizontal swipe on the preview to browse Instagram-style mood filters.
class SwipeMoodFilterLayer extends StatefulWidget {
  const SwipeMoodFilterLayer({
    super.key,
    required this.session,
    required this.enabled,
    required this.viewerScale,
    required this.child,
    this.strength = 1.0,
  });

  final EditorSession session;
  final bool enabled;
  final double viewerScale;
  final Widget child;
  final double strength;

  @override
  State<SwipeMoodFilterLayer> createState() => _SwipeMoodFilterLayerState();
}

class _SwipeMoodFilterLayerState extends State<SwipeMoodFilterLayer> {
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
      !widget.session.busy;

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
    final preset = moodFilterAtIndex(index);
    unawaited(
      widget.session.setMoodFilter(
        preset: preset,
        strength: widget.strength,
        livePreview: !commit,
        commit: commit,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.session,
      builder: (context, _) {
        final preset = widget.session.previewMoodPreset;
        final label = preset == null ? 'Original' : moodFilterDisplayName(preset);

        return Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragStart: _swipeActive
                  ? (_) {
                      _dragging = true;
                      _dragAccum = 0;
                      _dragStartIndex =
                          moodFilterIndex(widget.session.committedMoodPreset);
                      _previewIndex = _dragStartIndex;
                      _showLabel();
                    }
                  : null,
              onHorizontalDragUpdate: _swipeActive
                  ? (details) {
                      _dragAccum += details.delta.dx;
                      final steps = (-_dragAccum / _stepPx).round();
                      final next = (_dragStartIndex + steps)
                          .clamp(0, moodFilterCount - 1);
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
                      _previewIndex = moodFilterIndex(
                        widget.session.committedMoodPreset,
                      );
                      unawaited(widget.session.cancelMoodPreview());
                      _showLabel();
                    }
                  : null,
              child: widget.child,
            ),
            IgnorePointer(
              child: AnimatedOpacity(
                opacity: _labelVisible && widget.session.hasImage ? 1 : 0,
                duration: EditorMotion.fast,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 48),
                    child: _MoodFilterNameChip(label: label),
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

class _MoodFilterNameChip extends StatelessWidget {
  const _MoodFilterNameChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(LuminaTokens.radiusMd),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }
}
