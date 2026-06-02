// Tests for the OutputProfile enum and the CompressOptions wiring.

import 'package:flutter_test/flutter_test.dart';
import 'package:video_forge/video_forge.dart';

void main() {
  group('OutputProfile', () {
    test('ProgressiveMp4 is reachable', () {
      final p = OutputProfile.progressiveMp4(fastStart: true);
      expect(p, isA<OutputProfile>());
      expect(p, isA<OutputProfile_ProgressiveMp4>());
    });

    test('FragmentedMp4 is reachable', () {
      final p = OutputProfile.fragmentedMp4(fragmentDurationMs: 2000);
      expect(p, isA<OutputProfile>());
      expect(p, isA<OutputProfile_FragmentedMp4>());
    });

    test('Hls is reachable', () {
      final p = OutputProfile.hls(
        segmentDurationMs: 6000,
        masterPlaylist: true,
        hlsVersion: 6,
      );
      expect(p, isA<OutputProfile>());
      expect(p, isA<OutputProfile_Hls>());
    });
  });

  group('CompressOptions.outputProfile', () {
    test('default has no output profile set', () {
      final opts = CompressOptions(
        inputPath: '/x.mp4',
        quality: VideoQuality.medium,
        codec: VideoCodec.h264,
        includeAudio: true,
        fastStart: true,
        fragmentedMp4: false,
        preferHardwareEncoder: true,
        burnInOverlays: const [],
        audioTracks: const [],
        muteOriginalAudio: false,
      );
      expect(opts.outputProfile, isNull);
    });

    test('round-trips a ProgressiveMp4 profile', () {
      final opts = CompressOptions(
        inputPath: '/x.mp4',
        quality: VideoQuality.medium,
        codec: VideoCodec.h264,
        includeAudio: true,
        fastStart: true,
        fragmentedMp4: false,
        preferHardwareEncoder: true,
        burnInOverlays: const [],
        audioTracks: const [],
        muteOriginalAudio: false,
        outputProfile: OutputProfile.progressiveMp4(fastStart: false),
      );
      expect(opts.outputProfile, isNotNull);
      expect(opts.fastStart, isTrue); // legacy field unchanged
    });
  });
}
