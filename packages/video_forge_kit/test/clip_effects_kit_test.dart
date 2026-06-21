import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_forge_kit/video_forge_kit.dart';

void main() {
  group('ClipEffectsKit', () {
    test('mergeMotionPreset keeps base and speed', () {
      final current = ClipEffectsKit.copyWithBase(
        ClipEffectsKit.withSpeed(ClipEffectsKit.identity(), 2.0),
        scale: 1.5,
      );
      final preset = ClipEffectsKit.kenBurnsZoomIn(durationMs: 3000);
      final merged = ClipEffectsKit.mergeMotionPreset(current, preset);

      expect(merged.base.scale, 1.5);
      expect(merged.speed, 2.0);
      expect(merged.motion.tracks.length, 1);
    });

    test('effectiveSpeedAt honours speed segments', () {
      final fx = ClipEffectsKit.withFullClipSpeedRamp(
        ClipEffectsKit.identity(),
        4000,
        rate: 2.0,
      );
      expect(ClipEffectsKit.effectiveSpeedAt(fx, 0), 2.0);
      expect(ClipEffectsKit.effectiveSpeedAt(fx, 3999), 2.0);
      expect(ClipEffectsKit.effectiveSpeedAt(fx, 4000), closeTo(1.0, 0.001));
    });

    test('needsSegmentedExport', () {
      expect(ClipEffectsKit.needsSegmentedExport([]), false);
      expect(
        ClipEffectsKit.needsSegmentedExport([
          VideoTimelineClip(
            id: 'a',
            sourcePath: '/a.mp4',
            sourceStartMs: 0,
            sourceEndMs: 1000,
            timelineStartMs: 0,
          ),
        ]),
        false,
      );
      expect(
        ClipEffectsKit.needsSegmentedExport([
          VideoTimelineClip(
            id: 'a',
            sourcePath: '/a.mp4',
            sourceStartMs: 0,
            sourceEndMs: 1000,
            timelineStartMs: 0,
          ),
          VideoTimelineClip(
            id: 'b',
            sourcePath: '/a.mp4',
            sourceStartMs: 1000,
            sourceEndMs: 2000,
            timelineStartMs: 1000,
          ),
        ]),
        true,
      );
    });

    test('TimelineExportService overlaysForClip shifts timeline', () {
      final clip = VideoTimelineClip(
        id: 'c',
        sourcePath: '/v.mp4',
        sourceStartMs: 0,
        sourceEndMs: 5000,
        timelineStartMs: 2000,
      );
      final overlays = [
        VideoOverlayItem.emoji(
          id: 'e1',
          startMs: 2500,
          endMs: 4500,
          anchor: const Offset(0.5, 0.5),
          emoji: '🎬',
        ),
        VideoOverlayItem.emoji(
          id: 'e2',
          startMs: 0,
          endMs: 1500,
          anchor: const Offset(0.5, 0.5),
          emoji: '❌',
        ),
      ];
      final clipped = TimelineExportService.overlaysForClip(overlays, clip);
      expect(clipped.length, 1);
      expect(clipped.first.startMs, 500);
      expect(clipped.first.endMs, 2500);
    });
  });
}
