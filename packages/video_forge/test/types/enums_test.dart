import 'package:flutter_test/flutter_test.dart';
import 'package:video_forge/video_forge.dart';

void main() {
  group('ProcessingPhase', () {
    test('has 8 phases', () {
      expect(ProcessingPhase.values, hasLength(8));
    });

    test('all phases accessible', () {
      expect(ProcessingPhase.probing, isA<ProcessingPhase>());
      expect(ProcessingPhase.decoding, isA<ProcessingPhase>());
      expect(ProcessingPhase.encoding, isA<ProcessingPhase>());
      expect(ProcessingPhase.muxing, isA<ProcessingPhase>());
      expect(ProcessingPhase.thumbnail, isA<ProcessingPhase>());
      expect(ProcessingPhase.done, isA<ProcessingPhase>());
      expect(ProcessingPhase.cancelled, isA<ProcessingPhase>());
      expect(ProcessingPhase.failed, isA<ProcessingPhase>());
    });
  });

  group('ThumbnailFormat', () {
    test('has 2 formats', () {
      expect(ThumbnailFormat.values, hasLength(2));
    });

    test('all formats accessible', () {
      expect(ThumbnailFormat.jpeg, isA<ThumbnailFormat>());
      expect(ThumbnailFormat.webp, isA<ThumbnailFormat>());
    });
  });

  group('VideoCodec', () {
    test('has 2 codecs', () {
      expect(VideoCodec.values, hasLength(2));
    });

    test('all codecs accessible', () {
      expect(VideoCodec.h264, isA<VideoCodec>());
      expect(VideoCodec.hevc, isA<VideoCodec>());
    });
  });

  group('VideoQuality', () {
    test('has 9 quality levels', () {
      expect(VideoQuality.values, hasLength(9));
    });

    test('all quality levels accessible', () {
      expect(VideoQuality.low, isA<VideoQuality>());
      expect(VideoQuality.medium, isA<VideoQuality>());
      expect(VideoQuality.high, isA<VideoQuality>());
      expect(VideoQuality.custom, isA<VideoQuality>());
      expect(VideoQuality.instagram, isA<VideoQuality>());
      expect(VideoQuality.whatsapp, isA<VideoQuality>());
      expect(VideoQuality.telegram, isA<VideoQuality>());
      expect(VideoQuality.youtube, isA<VideoQuality>());
      expect(VideoQuality.lossless, isA<VideoQuality>());
    });
  });
}
