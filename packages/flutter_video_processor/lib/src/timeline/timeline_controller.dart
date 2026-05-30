import 'package:flutter/foundation.dart';

import '../compositor/video_overlay_item.dart';
import 'timeline_models.dart';

/// Editable multi-track timeline for Sprint 20 (clips, audio metadata, overlays).
class TimelineController extends ChangeNotifier {
  TimelineController();

  final List<VideoTimelineClip> _videoClips = [];
  final List<AudioTimelineClip> _audioClips = [];
  final List<VideoOverlayItem> _overlays = [];

  String? _primarySourcePath;
  int _sourceDurationMs = 0;
  String? _selectedVideoClipId;
  String? _selectedAudioClipId;
  String? _selectedOverlayId;

  List<VideoTimelineClip> get videoClips => List.unmodifiable(_videoClips);
  List<AudioTimelineClip> get audioClips => List.unmodifiable(_audioClips);
  List<VideoOverlayItem> get overlays => List.unmodifiable(_overlays);

  String? get primarySourcePath => _primarySourcePath;
  int get sourceDurationMs => _sourceDurationMs;
  String? get selectedVideoClipId => _selectedVideoClipId;
  String? get selectedAudioClipId => _selectedAudioClipId;
  String? get selectedOverlayId => _selectedOverlayId;

  /// Master timeline length (video + overlays). Audio never extends this.
  int get durationMs {
    if (_videoClips.isEmpty) return _sourceDurationMs;
    var maxMs = 0;
    for (final c in _videoClips) {
      if (c.timelineEndMs > maxMs) maxMs = c.timelineEndMs;
    }
    for (final o in _overlays) {
      if (o.endMs > maxMs) maxMs = o.endMs;
    }
    return maxMs;
  }

  int get videoDurationMs => durationMs;

  bool get hasVideoClips => _videoClips.isNotEmpty;

  /// Initialize one full-length clip from a probed asset.
  void loadPrimaryVideo({
    required String sourcePath,
    required int durationMs,
  }) {
    _primarySourcePath = sourcePath;
    _sourceDurationMs = durationMs > 0 ? durationMs : 1;
    _videoClips
      ..clear()
      ..add(
        VideoTimelineClip(
          id: 'clip_0',
          sourcePath: sourcePath,
          sourceStartMs: 0,
          sourceEndMs: _sourceDurationMs,
          timelineStartMs: 0,
        ),
      );
    _selectedVideoClipId = _videoClips.first.id;
    notifyListeners();
  }

  VideoTimelineClip? clipById(String id) {
    for (final c in _videoClips) {
      if (c.id == id) return c;
    }
    return null;
  }

  VideoTimelineClip? clipAtTimelineMs(int timelineMs) {
    for (final c in _videoClips) {
      if (c.containsTimelineMs(timelineMs)) return c;
    }
    return null;
  }

  /// Master playhead → decode seek target for [MediaRuntime].
  TimelineSeekTarget? seekTargetAt(int timelineMs) {
    final clip = clipAtTimelineMs(timelineMs);
    if (clip == null) return null;
    final rel = timelineMs - clip.timelineStartMs;
    return TimelineSeekTarget(
      sourcePath: clip.sourcePath,
      sourceMs: clip.sourceStartMs + rel,
      clipId: clip.id,
    );
  }

  /// Contiguous export range on the primary lane (first→last clip on same file).
  TimelineExportRange? exportRangeForPrimarySource() {
    if (_videoClips.isEmpty || _primarySourcePath == null) return null;
    final same = _videoClips.where((c) => c.sourcePath == _primarySourcePath);
    if (same.isEmpty) return null;
    var minSource = same.first.sourceStartMs;
    var maxSource = same.first.sourceEndMs;
    for (final c in same) {
      if (c.sourceStartMs < minSource) minSource = c.sourceStartMs;
      if (c.sourceEndMs > maxSource) maxSource = c.sourceEndMs;
    }
    return TimelineExportRange(
      sourcePath: _primarySourcePath!,
      startMs: minSource,
      endMs: maxSource,
    );
  }

  void selectVideoClip(String? id) {
    _selectedVideoClipId = id;
    notifyListeners();
  }

  void selectAudioClip(String? id) {
    _selectedAudioClipId = id;
    notifyListeners();
  }

  void selectOverlay(String? id) {
    _selectedOverlayId = id;
    notifyListeners();
  }

  /// Split the video clip under [timelineMs] at the playhead.
  bool splitVideoAt(int timelineMs) {
    final clip = clipAtTimelineMs(timelineMs);
    if (clip == null) return false;
    final rel = timelineMs - clip.timelineStartMs;
    if (rel <= 0 || rel >= clip.durationMs) return false;

    final splitSource = clip.sourceStartMs + rel;
    final left = clip.copyWith(
      id: '${clip.id}_a',
      sourceEndMs: splitSource,
    );
    final right = clip.copyWith(
      id: '${clip.id}_b',
      sourcePath: clip.sourcePath,
      sourceStartMs: splitSource,
      sourceEndMs: clip.sourceEndMs,
      timelineStartMs: clip.timelineStartMs + rel,
    );

    final index = _videoClips.indexWhere((c) => c.id == clip.id);
    if (index < 0) return false;
    _videoClips
      ..removeAt(index)
      ..insert(index, left)
      ..insert(index + 1, right);
    normalizeVideoTimelineOffsets();
    _selectedVideoClipId = right.id;
    notifyListeners();
    return true;
  }

  /// Merge [clipId] with the next adjacent clip on the timeline (same source, contiguous).
  bool mergeWithNext(String clipId) {
    final index = _videoClips.indexWhere((c) => c.id == clipId);
    if (index < 0 || index >= _videoClips.length - 1) return false;
    final a = _videoClips[index];
    final b = _videoClips[index + 1];
    if (a.sourcePath != b.sourcePath) return false;
    if (a.sourceEndMs != b.sourceStartMs) return false;
    if (a.timelineStartMs + a.durationMs != b.timelineStartMs) return false;

    final merged = a.copyWith(
      id: '${a.id}_merged',
      sourceEndMs: b.sourceEndMs,
    );
    _videoClips
      ..removeAt(index + 1)
      ..[index] = merged;
    normalizeVideoTimelineOffsets();
    _selectedVideoClipId = merged.id;
    notifyListeners();
    return true;
  }

  void updateVideoClip(VideoTimelineClip clip) {
    final i = _videoClips.indexWhere((c) => c.id == clip.id);
    if (i < 0) return;
    _videoClips[i] = clip;
    normalizeVideoTimelineOffsets();
    notifyListeners();
  }

  bool deleteVideoClip(String clipId) {
    if (_videoClips.length <= 1) return false;
    final before = _videoClips.length;
    _videoClips.removeWhere((c) => c.id == clipId);
    final removed = _videoClips.length < before;
    if (!removed) return false;
    normalizeVideoTimelineOffsets();
    _selectedVideoClipId = _videoClips.isNotEmpty ? _videoClips.first.id : null;
    notifyListeners();
    return true;
  }

  void normalizeVideoTimelineOffsets() {
    _videoClips.sort((a, b) => a.timelineStartMs.compareTo(b.timelineStartMs));
    var cursor = 0;
    for (var i = 0; i < _videoClips.length; i++) {
      final c = _videoClips[i];
      _videoClips[i] = c.copyWith(timelineStartMs: cursor);
      cursor += c.durationMs;
    }
  }

  AudioTimelineClip addAudioClip({
    required String sourcePath,
    required int sourceDurationMs,
    int? timelineStartMs,
    int? videoDurationMs,
    double volume = 1.0,
  }) {
    final videoMs = videoDurationMs ?? durationMs;
    final fullMs = sourceDurationMs > 0 ? sourceDurationMs : 1;
    final windowMs = fullMs < videoMs ? fullMs : videoMs;
    final start = timelineStartMs ?? 0;
    final id = 'audio_${DateTime.now().millisecondsSinceEpoch}';
    final clip = AudioTimelineClip.clamped(
      AudioTimelineClip(
        id: id,
        sourcePath: sourcePath,
        timelineStartMs: start,
        sourceDurationMs: fullMs,
        sourceStartMs: 0,
        durationMs: windowMs.clamp(1, videoMs),
        volume: volume,
      ),
      videoDurationMs: videoMs,
    );
    _audioClips.add(clip);
    _selectedAudioClipId = id;
    notifyListeners();
    return clip;
  }

  void updateAudioClip(AudioTimelineClip clip) {
    final i = _audioClips.indexWhere((c) => c.id == clip.id);
    if (i < 0) return;
    _audioClips[i] = AudioTimelineClip.clamped(
      clip,
      videoDurationMs: videoDurationMs,
    );
    notifyListeners();
  }

  /// Re-clamp all audio clips after video trim or duration change.
  void clampAudioClipsToVideo() {
    if (_audioClips.isEmpty) return;
    final videoMs = videoDurationMs;
    for (var i = 0; i < _audioClips.length; i++) {
      _audioClips[i] = AudioTimelineClip.clamped(
        _audioClips[i],
        videoDurationMs: videoMs,
      );
    }
    notifyListeners();
  }

  bool removeAudioClip(String id) {
    final before = _audioClips.length;
    _audioClips.removeWhere((c) => c.id == id);
    final removed = _audioClips.length < before;
    if (removed && _selectedAudioClipId == id) {
      _selectedAudioClipId =
          _audioClips.isNotEmpty ? _audioClips.first.id : null;
    }
    if (removed) notifyListeners();
    return removed;
  }

  void addOverlay(VideoOverlayItem item) {
    _overlays.add(item);
    _selectedOverlayId = item.id;
    notifyListeners();
  }

  void updateOverlay(VideoOverlayItem item) {
    final i = _overlays.indexWhere((o) => o.id == item.id);
    if (i < 0) return;
    _overlays[i] = item;
    notifyListeners();
  }

  bool removeOverlay(String id) {
    final before = _overlays.length;
    _overlays.removeWhere((o) => o.id == id);
    final removed = _overlays.length < before;
    if (removed && _selectedOverlayId == id) {
      _selectedOverlayId = _overlays.isNotEmpty ? _overlays.first.id : null;
    }
    if (removed) notifyListeners();
    return removed;
  }

  void clearOverlays() {
    _overlays.clear();
    _selectedOverlayId = null;
    notifyListeners();
  }

  void setOverlays(List<VideoOverlayItem> items) {
    _overlays
      ..clear()
      ..addAll(items);
    notifyListeners();
  }
}
