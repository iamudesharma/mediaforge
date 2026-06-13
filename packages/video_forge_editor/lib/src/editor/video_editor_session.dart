import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:video_forge_kit/video_forge_kit.dart';

import '../playback/playback_backend.dart';
import '../playback/rust_playback_backend.dart';

/// Domain state for the video editor (timeline, trim, export settings).
class VideoEditorSession extends ChangeNotifier {
  VideoEditorSession({
    TimelineController? timeline,
  }) : timeline = timeline ?? TimelineController();

  final TimelineController timeline;

  PlaybackBackend? backend;
  double startSec = 0;
  double endSec = 0;
  double playheadSec = 0;
  CompressionPreset exportPreset = CompressionPreset.instagram;
  bool preferHw = true;
  bool muteOriginalAudio = false;
  double playbackRate = 1.0;

  bool get hasRustBackend => backend is RustPlaybackBackend;

  RustPlaybackBackend? get rustBackend =>
      backend is RustPlaybackBackend ? backend! as RustPlaybackBackend : null;

  (int startMs, int endMs) exportTrimMs() {
    final range = timeline.exportRangeForPrimarySource();
    var startMs = (startSec * 1000).round();
    var endMs = (endSec * 1000).round();
    if (range != null) {
      startMs = math.max(startMs, range.startMs);
      endMs = math.min(endMs, range.endMs);
    }
    if (endMs <= startMs) {
      endMs = startMs + 1;
    }
    return (startMs, endMs);
  }

  List<AudioTrackInput> exportAudioTracks() {
    return timeline.audioClips
        .where((c) => !c.muted)
        .map(
          (c) => AudioTrackInput(
            sourcePath: c.sourcePath,
            sourceStartMs: BigInt.from(c.sourceStartMs),
            durationMs: BigInt.from(c.durationMs),
            timelineStartMs: BigInt.from(c.timelineStartMs),
            volume: c.volume,
            muted: c.muted,
          ),
        )
        .toList();
  }

  List<AudioClipInfo> overlayAudioClips() {
    return timeline.audioClips
        .map(
          (c) => AudioClipInfo(
            id: c.id,
            sourcePath: c.sourcePath,
            volume: c.volume,
            timelineStartMs: c.timelineStartMs,
            durationMs: c.durationMs,
            sourceStartMs: c.sourceStartMs,
            muted: c.muted,
          ),
        )
        .toList();
  }

  @override
  void dispose() {
    backend?.dispose();
    timeline.dispose();
    super.dispose();
  }
}
