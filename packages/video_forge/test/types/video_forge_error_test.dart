import 'package:flutter_test/flutter_test.dart';
import 'package:video_forge/video_forge.dart';

void main() {
  group('VideoForgeError', () {
    group('invalidInput', () {
      test('construction', () {
        final err = VideoForgeError.invalidInput('empty path');
        expect(err, isA<VideoForgeError_InvalidInput>());
        expect((err as VideoForgeError_InvalidInput).field0, 'empty path');
      });

      test('equality', () {
        final a = VideoForgeError.invalidInput('bad');
        final b = VideoForgeError.invalidInput('bad');
        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });
    });

    group('fileNotFound', () {
      test('construction and equality', () {
        final a = VideoForgeError.fileNotFound('/missing.mp4');
        final b = VideoForgeError.fileNotFound('/missing.mp4');
        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });
    });

    group('unsupportedCodec', () {
      test('construction', () {
        final err = VideoForgeError.unsupportedCodec('vp9');
        expect(err, isA<VideoForgeError_UnsupportedCodec>());
        expect((err as VideoForgeError_UnsupportedCodec).field0, 'vp9');
      });
    });

    group('jobNotFound', () {
      test('construction', () {
        final err = VideoForgeError.jobNotFound('job-xyz');
        expect(err, isA<VideoForgeError_JobNotFound>());
        expect((err as VideoForgeError_JobNotFound).field0, 'job-xyz');
      });
    });

    group('cancelled', () {
      test('construction and equality', () {
        final a = VideoForgeError.cancelled();
        final b = VideoForgeError.cancelled();
        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });
    });

    group('ioError', () {
      test('construction', () {
        final err = VideoForgeError.ioError('disk full');
        expect(err, isA<VideoForgeError_IoError>());
        expect((err as VideoForgeError_IoError).field0, 'disk full');
      });
    });

    group('ffmpegError', () {
      test('construction', () {
        final err = VideoForgeError.ffmpegError('encoder not found');
        expect(err, isA<VideoForgeError_FfmpegError>());
        expect((err as VideoForgeError_FfmpegError).field0, 'encoder not found');
      });
    });

    group('queueFull', () {
      test('construction and equality', () {
        final a = VideoForgeError.queueFull();
        final b = VideoForgeError.queueFull();
        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });
    });

    group('internal', () {
      test('construction', () {
        final err = VideoForgeError.internal('panic');
        expect(err, isA<VideoForgeError_Internal>());
        expect((err as VideoForgeError_Internal).field0, 'panic');
      });
    });

    test('all 9 variants exist', () {
      expect(VideoForgeError_InvalidInput, isA<Type>());
      expect(VideoForgeError_FileNotFound, isA<Type>());
      expect(VideoForgeError_UnsupportedCodec, isA<Type>());
      expect(VideoForgeError_JobNotFound, isA<Type>());
      expect(VideoForgeError_Cancelled, isA<Type>());
      expect(VideoForgeError_IoError, isA<Type>());
      expect(VideoForgeError_FfmpegError, isA<Type>());
      expect(VideoForgeError_QueueFull, isA<Type>());
      expect(VideoForgeError_Internal, isA<Type>());
    });

    test('different variants not equal', () {
      final a = VideoForgeError.cancelled();
      final b = VideoForgeError.queueFull();
      expect(a, isNot(equals(b)));
    });

    group('when pattern matching', () {
      test('matches correct variant', () {
        final err = VideoForgeError.cancelled();
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
        final err = VideoForgeError.fileNotFound('/x.mp4');
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
      final err = VideoForgeError.ffmpegError('broken pipe');
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
      final err = VideoForgeError.internal('oops');
      final result = err.maybeWhen(
        internal: (msg) => 'internal: $msg',
        orElse: () => 'not internal',
      );
      expect(result, 'internal: oops');
    });

    test('maybeWhen with orElse fallback', () {
      final err = VideoForgeError.queueFull();
      final result = err.maybeWhen(
        internal: (_) => 'internal',
        orElse: () => 'other',
      );
      expect(result, 'other');
    });

    test('maybeMap with orElse', () {
      final err = VideoForgeError.internal('oh no');
      final result = err.maybeMap(
        internal: (e) => 'in-${e.field0}',
        orElse: () => 'not-internal',
      );
      expect(result, 'in-oh no');
    });
  });
}
