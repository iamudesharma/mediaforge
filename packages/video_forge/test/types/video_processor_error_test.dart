import 'package:flutter_test/flutter_test.dart';
import 'package:video_forge/video_forge.dart';

void main() {
  group('VideoProcessorError', () {
    group('invalidInput', () {
      test('construction', () {
        final err = VideoProcessorError.invalidInput('empty path');
        expect(err, isA<VideoProcessorError_InvalidInput>());
        expect((err as VideoProcessorError_InvalidInput).field0, 'empty path');
      });

      test('equality', () {
        final a = VideoProcessorError.invalidInput('bad');
        final b = VideoProcessorError.invalidInput('bad');
        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });
    });

    group('fileNotFound', () {
      test('construction and equality', () {
        final a = VideoProcessorError.fileNotFound('/missing.mp4');
        final b = VideoProcessorError.fileNotFound('/missing.mp4');
        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });
    });

    group('unsupportedCodec', () {
      test('construction', () {
        final err = VideoProcessorError.unsupportedCodec('vp9');
        expect(err, isA<VideoProcessorError_UnsupportedCodec>());
        expect((err as VideoProcessorError_UnsupportedCodec).field0, 'vp9');
      });
    });

    group('jobNotFound', () {
      test('construction', () {
        final err = VideoProcessorError.jobNotFound('job-xyz');
        expect(err, isA<VideoProcessorError_JobNotFound>());
        expect((err as VideoProcessorError_JobNotFound).field0, 'job-xyz');
      });
    });

    group('cancelled', () {
      test('construction and equality', () {
        final a = VideoProcessorError.cancelled();
        final b = VideoProcessorError.cancelled();
        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });
    });

    group('ioError', () {
      test('construction', () {
        final err = VideoProcessorError.ioError('disk full');
        expect(err, isA<VideoProcessorError_IoError>());
        expect((err as VideoProcessorError_IoError).field0, 'disk full');
      });
    });

    group('ffmpegError', () {
      test('construction', () {
        final err = VideoProcessorError.ffmpegError('encoder not found');
        expect(err, isA<VideoProcessorError_FfmpegError>());
        expect((err as VideoProcessorError_FfmpegError).field0, 'encoder not found');
      });
    });

    group('queueFull', () {
      test('construction and equality', () {
        final a = VideoProcessorError.queueFull();
        final b = VideoProcessorError.queueFull();
        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });
    });

    group('internal', () {
      test('construction', () {
        final err = VideoProcessorError.internal('panic');
        expect(err, isA<VideoProcessorError_Internal>());
        expect((err as VideoProcessorError_Internal).field0, 'panic');
      });
    });

    test('all 9 variants exist', () {
      expect(VideoProcessorError_InvalidInput, isA<Type>());
      expect(VideoProcessorError_FileNotFound, isA<Type>());
      expect(VideoProcessorError_UnsupportedCodec, isA<Type>());
      expect(VideoProcessorError_JobNotFound, isA<Type>());
      expect(VideoProcessorError_Cancelled, isA<Type>());
      expect(VideoProcessorError_IoError, isA<Type>());
      expect(VideoProcessorError_FfmpegError, isA<Type>());
      expect(VideoProcessorError_QueueFull, isA<Type>());
      expect(VideoProcessorError_Internal, isA<Type>());
    });

    test('different variants not equal', () {
      final a = VideoProcessorError.cancelled();
      final b = VideoProcessorError.queueFull();
      expect(a, isNot(equals(b)));
    });

    group('when pattern matching', () {
      test('matches correct variant', () {
        final err = VideoProcessorError.cancelled();
        final result = err.when(
          invalidInput: (_) => 'invalidInput',
          fileNotFound: (_) => 'fileNotFound',
          unsupportedCodec: (_) => 'unsupportedCodec',
          jobNotFound: (_) => 'jobNotFound',
          cancelled: () => 'cancelled',
          ioError: (_) => 'ioError',
          ffmpegError: (_) => 'ffmpegError',
          queueFull: () => 'queueFull',
          internal: (_) => 'internal',
        );
        expect(result, 'cancelled');
      });

      test('all branches exhaustive', () {
        final err = VideoProcessorError.fileNotFound('/x.mp4');
        final result = err.when(
          invalidInput: (_) => 'ii',
          fileNotFound: (_) => 'fn',
          unsupportedCodec: (_) => 'uc',
          jobNotFound: (_) => 'jn',
          cancelled: () => 'c',
          ioError: (_) => 'io',
          ffmpegError: (_) => 'fe',
          queueFull: () => 'qf',
          internal: (_) => 'i',
        );
        expect(result, 'fn');
      });
    });

    test('map pattern matching', () {
      final err = VideoProcessorError.ffmpegError('broken pipe');
      final result = err.map(
        invalidInput: (_) => 'II',
        fileNotFound: (_) => 'FN',
        unsupportedCodec: (_) => 'UC',
        jobNotFound: (_) => 'JN',
        cancelled: (_) => 'C',
        ioError: (_) => 'IO',
        ffmpegError: (_) => 'FE',
        queueFull: (_) => 'QF',
        internal: (_) => 'I',
      );
      expect(result, 'FE');
    });

    test('maybeWhen with specific variant', () {
      final err = VideoProcessorError.internal('oops');
      final result = err.maybeWhen(
        internal: (msg) => 'internal: $msg',
        orElse: () => 'not internal',
      );
      expect(result, 'internal: oops');
    });

    test('maybeWhen with orElse fallback', () {
      final err = VideoProcessorError.queueFull();
      final result = err.maybeWhen(
        internal: (_) => 'internal',
        orElse: () => 'other',
      );
      expect(result, 'other');
    });

    test('maybeMap with orElse', () {
      final err = VideoProcessorError.internal('oh no');
      final result = err.maybeMap(
        internal: (e) => 'in-${e.field0}',
        orElse: () => 'not-internal',
      );
      expect(result, 'in-oh no');
    });
  });
}
