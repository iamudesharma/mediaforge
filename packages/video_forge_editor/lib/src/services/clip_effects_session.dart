import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:video_forge_kit/video_forge_kit.dart';

/// Live clip-effects editing (image-forge style): preview updates via [preview],
/// timeline commit is debounced so sliders/gestures do not rebuild the whole editor.
@immutable
class ClipEffectsPreview {
  const ClipEffectsPreview({
    required this.clipId,
    required this.effects,
  });

  final String clipId;
  final ClipEffects effects;
}

class ClipEffectsSession {
  ClipEffectsSession({
    required this.timeline,
    this.onCommitted,
  });

  final TimelineController timeline;
  final VoidCallback? onCommitted;

  final ValueNotifier<ClipEffectsPreview?> preview =
      ValueNotifier<ClipEffectsPreview?>(null);

  Timer? _commitTimer;
  int _commitGeneration = 0;
  bool _isLiveEditing = false;

  /// True while a slider/gesture is actively previewing (timeline not yet committed).
  bool get isLiveEditing => _isLiveEditing;

  ClipEffects effectsForClip(VideoTimelineClip clip) {
    final live = preview.value;
    if (live != null && live.clipId == clip.id) {
      return live.effects;
    }
    return ClipEffectsKit.forClip(clip);
  }

  /// Fast preview path — does not touch [TimelineController] or Rust audio sync.
  void previewEffects(String clipId, ClipEffects effects) {
    _isLiveEditing = true;
    preview.value = ClipEffectsPreview(clipId: clipId, effects: effects);
    _scheduleCommit(clipId, effects);
  }

  /// Immediate commit (presets, reset, gesture end).
  void commitNow(String clipId, ClipEffects effects) {
    _commitTimer?.cancel();
    _commitGeneration++;
    _flush(clipId, effects);
  }

  void clearPreview({String? clipId}) {
    final live = preview.value;
    if (clipId != null && live?.clipId != clipId) return;
    preview.value = null;
    _isLiveEditing = false;
  }

  void dispose() {
    _commitTimer?.cancel();
    preview.dispose();
  }

  void _scheduleCommit(String clipId, ClipEffects effects) {
    final gen = ++_commitGeneration;
    _commitTimer?.cancel();
    _commitTimer = Timer(const Duration(milliseconds: 150), () {
      if (gen != _commitGeneration) return;
      _flush(clipId, effects);
    });
  }

  void _flush(String clipId, ClipEffects effects) {
    _isLiveEditing = false;
    timeline.updateVideoClipEffects(clipId, effects);
    preview.value = ClipEffectsPreview(clipId: clipId, effects: effects);
    onCommitted?.call();
    debugPrint(
      '[ClipEffects] committed clip=$clipId scale=${effects.base.scale} '
      'rotation=${effects.base.rotation} speed=${effects.speed}',
    );
  }
}
