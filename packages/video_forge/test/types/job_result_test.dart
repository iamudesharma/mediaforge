import 'package:flutter_test/flutter_test.dart';
import 'package:video_forge/video_forge.dart';

void main() {
  group('JobResult', () {
    group('compress variant', () {
      test('construction', () {
        final result = CompressResult(
          outputPath: '/out.mp4',
          durationMs: BigInt.from(30000),
          fileSize: BigInt.from(5000000),
          usedHardwareAcceleration: true,
          encoderName: 'h264_videotoolbox',
          pipelineMode: 'vt_zero_copy',
        );
        final job = JobResult.compress(result);

        expect(job, isA<JobResult_Compress>());
        final compress = job as JobResult_Compress;
        expect(compress.field0.outputPath, '/out.mp4');
      });

      test('equality', () {
        final r1 = CompressResult(
          outputPath: '/a.mp4', durationMs: BigInt.from(1000),
          fileSize: BigInt.from(1000), usedHardwareAcceleration: false,
          encoderName: 'x264', pipelineMode: 'direct',
        );
        final r2 = CompressResult(
          outputPath: '/a.mp4', durationMs: BigInt.from(1000),
          fileSize: BigInt.from(1000), usedHardwareAcceleration: false,
          encoderName: 'x264', pipelineMode: 'direct',
        );
        final a = JobResult.compress(r1);
        final b = JobResult.compress(r2);

        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });
    });

    group('empty variant', () {
      test('construction', () {
        final job = JobResult.empty();
        expect(job, isA<JobResult_Empty>());
      });

      test('equality', () {
        final a = JobResult.empty();
        final b = JobResult.empty();
        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });
    });

    test('different variants not equal', () {
      final result = CompressResult(
        outputPath: '/out.mp4', durationMs: BigInt.from(1000),
        fileSize: BigInt.from(1000), usedHardwareAcceleration: false,
        encoderName: 'libx264', pipelineMode: 'direct',
      );
      final a = JobResult.compress(result);
      final b = JobResult.empty();
      expect(a, isNot(equals(b)));
    });

    test('when pattern matching', () {
      final job = JobResult.empty();
      final text = job.when(
        compress: (_) => 'compress',
        empty: () => 'empty',
      );
      expect(text, 'empty');
    });

    test('map pattern matching', () {
      final result = CompressResult(
        outputPath: '/o.mp4', durationMs: BigInt.from(1000),
        fileSize: BigInt.from(1000), usedHardwareAcceleration: false,
        encoderName: 'h264_videotoolbox', pipelineMode: 'vt_zero_copy',
      );
      final job = JobResult.compress(result);
      final text = job.map(
        compress: (_) => 'C',
        empty: (_) => 'E',
      );
      expect(text, 'C');
    });

    test('maybeWhen with orElse', () {
      final job = JobResult.empty();
      final result = job.maybeWhen(
        empty: () => 'got empty',
        orElse: () => 'other',
      );
      expect(result, 'got empty');
    });

    test('maybeMap with orElse', () {
      final result = CompressResult(
        outputPath: '/o.mp4', durationMs: BigInt.from(1000),
        fileSize: BigInt.from(1000), usedHardwareAcceleration: true,
        encoderName: 'h264_vt', pipelineMode: 'vt_zero_copy',
      );
      final job = JobResult.compress(result);
      final text = job.maybeMap(
        compress: (c) => 'compressed-${c.field0.outputPath}',
        orElse: () => 'not-compress',
      );
      expect(text, 'compressed-/o.mp4');
    });
  });
}
