import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_video_processor/src/models/compress_options.dart';
import 'package:video_processor_core/video_processor_core.dart';

void main() {
  group('CompressOptionsBuilder', () {
    test('builds FRB compress options', () {
      final opts = CompressOptionsBuilder(
        inputPath: '/tmp/in.mp4',
        outputPath: '/tmp/out.mp4',
        quality: VideoQuality.medium,
        crf: 23,
        targetBitrate: 2000000,
      ).build();

      expect(opts.inputPath, '/tmp/in.mp4');
      expect(opts.quality, VideoQuality.medium);
      expect(opts.crf, 23);
      expect(opts.targetBitrate, BigInt.from(2000000));
    });
  });
}
