import 'dart:typed_data';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show Uint64List;
import 'package:flutter_test/flutter_test.dart';
import 'package:video_forge/video_forge.dart';

void main() {
  group('AudioTrackInput', () {
    test('construction and equality', () {
      final a = AudioTrackInput(
        sourcePath: '/path/to/audio.mp3',
        sourceStartMs: BigInt.from(0),
        durationMs: BigInt.from(5000),
        timelineStartMs: BigInt.from(1000),
        volume: 0.8,
        muted: false,
      );
      final b = AudioTrackInput(
        sourcePath: '/path/to/audio.mp3',
        sourceStartMs: BigInt.from(0),
        durationMs: BigInt.from(5000),
        timelineStartMs: BigInt.from(1000),
        volume: 0.8,
        muted: false,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('field access', () {
      final track = AudioTrackInput(
        sourcePath: '/audio/test.mp3',
        sourceStartMs: BigInt.from(500),
        durationMs: BigInt.from(30000),
        timelineStartMs: BigInt.from(0),
        volume: 1.0,
        muted: true,
      );
      expect(track.sourcePath, '/audio/test.mp3');
      expect(track.sourceStartMs, BigInt.from(500));
      expect(track.durationMs, BigInt.from(30000));
      expect(track.volume, 1.0);
      expect(track.muted, isTrue);
    });
  });

  group('BatchThumbnailBytesOptions', () {
    test('construction and equality', () {
      final positions = Uint64List.fromList([1000, 2000, 3000]);
      final a = BatchThumbnailBytesOptions(
        inputPath: '/video.mp4',
        positionsMs: positions,
        format: ThumbnailFormat.jpeg,
      );
      final b = BatchThumbnailBytesOptions(
        inputPath: '/video.mp4',
        positionsMs: positions,
        format: ThumbnailFormat.jpeg,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('optional width and height', () {
      final opts = BatchThumbnailBytesOptions(
        inputPath: '/v.mp4',
        positionsMs: Uint64List.fromList([0]),
        width: 320,
        height: 240,
        format: ThumbnailFormat.webp,
      );
      expect(opts.width, 320);
      expect(opts.height, 240);
    });

    test('nullable width and height default to null', () {
      final opts = BatchThumbnailBytesOptions(
        inputPath: '/v.mp4',
        positionsMs: Uint64List.fromList([0]),
        format: ThumbnailFormat.jpeg,
      );
      expect(opts.width, isNull);
      expect(opts.height, isNull);
    });
  });

  group('BatchThumbnailBytesResult', () {
    test('construction and equality', () {
      final frames = [Uint8List(100), Uint8List(200)];
      final a = BatchThumbnailBytesResult(
        frames: frames,
        decodedStatus: const [ThumbnailDecodeStatus.exact, ThumbnailDecodeStatus.exact],
      );
      final b = BatchThumbnailBytesResult(
        frames: frames,
        decodedStatus: const [ThumbnailDecodeStatus.exact, ThumbnailDecodeStatus.exact],
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a.frames, hasLength(2));
    });
  });

  group('BatchThumbnailOptions', () {
    test('construction and equality', () {
      final positions = Uint64List.fromList([5000]);
      final a = BatchThumbnailOptions(
        inputPath: '/video.mp4',
        outputDir: '/thumbs/',
        positionsMs: positions,
        format: ThumbnailFormat.jpeg,
      );
      final b = BatchThumbnailOptions(
        inputPath: '/video.mp4',
        outputDir: '/thumbs/',
        positionsMs: positions,
        format: ThumbnailFormat.jpeg,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('with optional outputPaths', () {
      final opts = BatchThumbnailOptions(
        inputPath: '/v.mp4',
        outputDir: '/out/',
        outputPaths: ['/out/thumb_0000.jpg'],
        positionsMs: Uint64List.fromList([0]),
        format: ThumbnailFormat.jpeg,
      );
      expect(opts.outputPaths, hasLength(1));
    });
  });

  group('BatchThumbnailResult', () {
    test('construction and equality', () {
      final paths = ['/a.jpg', '/b.jpg'];
      final a = BatchThumbnailResult(
        paths: paths,
        decodedStatus: const [ThumbnailDecodeStatus.exact, ThumbnailDecodeStatus.exact],
      );
      final b = BatchThumbnailResult(
        paths: paths,
        decodedStatus: const [ThumbnailDecodeStatus.exact, ThumbnailDecodeStatus.exact],
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a.paths, hasLength(2));
    });

    test('decodedStatus round-trips per-position', () {
      // PR #3 graceful-degrade: a batch whose positions are mostly
      // exact but one is past the last PTS should report
      // NearestKeyframe for the trailing positions.
      final a = BatchThumbnailResult(
        paths: ['/a.jpg', '/b.jpg', '/c.jpg'],
        decodedStatus: const [
          ThumbnailDecodeStatus.exact,
          ThumbnailDecodeStatus.exact,
          ThumbnailDecodeStatus.nearestKeyframe,
        ],
      );
      expect(a.decodedStatus, hasLength(3));
      expect(a.decodedStatus[0], ThumbnailDecodeStatus.exact);
      expect(a.decodedStatus[2], ThumbnailDecodeStatus.nearestKeyframe);
    });
  });

  group('ThumbnailDecodeStatus', () {
    test('has 2 variants', () {
      expect(ThumbnailDecodeStatus.values, hasLength(2));
    });

    test('variants are exact and nearestKeyframe', () {
      expect(ThumbnailDecodeStatus.exact, isA<ThumbnailDecodeStatus>());
      expect(
        ThumbnailDecodeStatus.nearestKeyframe,
        isA<ThumbnailDecodeStatus>(),
      );
    });
  });

  group('BurnInOverlay', () {
    test('construction and equality', () {
      final a = BurnInOverlay(
        imagePath: '/overlay.png',
        startMs: BigInt.from(0),
        endMs: BigInt.from(5000),
        anchorX: 0.5,
        anchorY: 0.5,
        fadeInMs: BigInt.from(500),
        fadeOutMs: BigInt.from(500),
      );
      final b = BurnInOverlay(
        imagePath: '/overlay.png',
        startMs: BigInt.from(0),
        endMs: BigInt.from(5000),
        anchorX: 0.5,
        anchorY: 0.5,
        fadeInMs: BigInt.from(500),
        fadeOutMs: BigInt.from(500),
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });

  group('CompressOptions', () {
    test('construction with required fields', () {
      final opts = CompressOptions(
        inputPath: '/video.mp4',
        quality: VideoQuality.high,
        codec: VideoCodec.h264,
        includeAudio: true,
        fastStart: true,
        fragmentedMp4: false,
        preferHardwareEncoder: true,
        burnInOverlays: [],
        audioTracks: [],
        muteOriginalAudio: false,
      );
      expect(opts.inputPath, '/video.mp4');
      expect(opts.quality, VideoQuality.high);
      expect(opts.burnInOverlays, isEmpty);
      expect(opts.audioTracks, isEmpty);
    });

    test('construction with all optional fields', () {
      final opts = CompressOptions(
        inputPath: '/v.mp4',
        outputPath: '/out.mp4',
        quality: VideoQuality.custom,
        codec: VideoCodec.hevc,
        crf: 23,
        targetBitrate: BigInt.from(5000000),
        maxWidth: 1920,
        maxHeight: 1080,
        maxFps: 30.0,
        includeAudio: true,
        fastStart: true,
        fragmentedMp4: true,
        preferHardwareEncoder: false,
        startMs: BigInt.from(1000),
        endMs: BigInt.from(10000),
        burnInOverlays: [],
        audioTracks: [],
        muteOriginalAudio: true,
      );
      expect(opts.crf, 23);
      expect(opts.maxWidth, 1920);
      expect(opts.startMs, BigInt.from(1000));
      expect(opts.muteOriginalAudio, isTrue);
    });

    test('equality', () {
      final overlays = <BurnInOverlay>[];
      final tracks = <AudioTrackInput>[];
      final a = CompressOptions(
        inputPath: '/v.mp4',
        quality: VideoQuality.instagram,
        codec: VideoCodec.h264,
        includeAudio: false,
        fastStart: false,
        fragmentedMp4: false,
        preferHardwareEncoder: false,
        burnInOverlays: overlays,
        audioTracks: tracks,
        muteOriginalAudio: false,
      );
      final b = CompressOptions(
        inputPath: '/v.mp4',
        quality: VideoQuality.instagram,
        codec: VideoCodec.h264,
        includeAudio: false,
        fastStart: false,
        fragmentedMp4: false,
        preferHardwareEncoder: false,
        burnInOverlays: overlays,
        audioTracks: tracks,
        muteOriginalAudio: false,
      );
      expect(a, equals(b));
    });
  });

  group('CompressResult', () {
    test('construction and equality', () {
      final a = CompressResult(
        outputPath: '/output.mp4',
        durationMs: BigInt.from(30000),
        fileSize: BigInt.from(5000000),
        usedHardwareAcceleration: true,
        encoderName: 'h264_videotoolbox',
        pipelineMode: 'vt_zero_copy',
      );
      final b = CompressResult(
        outputPath: '/output.mp4',
        durationMs: BigInt.from(30000),
        fileSize: BigInt.from(5000000),
        usedHardwareAcceleration: true,
        encoderName: 'h264_videotoolbox',
        pipelineMode: 'vt_zero_copy',
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('field access', () {
      final result = CompressResult(
        outputPath: '/out.mp4',
        durationMs: BigInt.from(10000),
        fileSize: BigInt.from(1000000),
        usedHardwareAcceleration: false,
        encoderName: 'libx264',
        pipelineMode: 'direct',
      );
      expect(result.outputPath, '/out.mp4');
      expect(result.usedHardwareAcceleration, isFalse);
      expect(result.encoderName, 'libx264');
    });
  });

  group('MediaInfo', () {
    test('construction with all fields', () {
      final info = MediaInfo(
        durationMs: BigInt.from(60000),
        width: 1920,
        height: 1080,
        rotation: 0,
        fps: 30.0,
        videoCodec: 'h264',
        audioCodec: 'aac',
        bitrate: BigInt.from(5000000),
        fileSize: BigInt.from(50000000),
        hasDolbyVision: false,
        preferSoftwarePreview: false,
      );
      expect(info.durationMs, BigInt.from(60000));
      expect(info.width, 1920);
      expect(info.height, 1080);
      expect(info.fps, 30.0);
      expect(info.videoCodec, 'h264');
      expect(info.audioCodec, 'aac');
    });

    test('nullable audioCodec', () {
      final info = MediaInfo(
        durationMs: BigInt.from(1000),
        width: 640,
        height: 480,
        rotation: 0,
        fps: 24.0,
        videoCodec: 'hevc',
        bitrate: BigInt.from(1000000),
        fileSize: BigInt.from(10000000),
        hasDolbyVision: true,
        preferSoftwarePreview: true,
      );
      expect(info.audioCodec, isNull);
      expect(info.hasDolbyVision, isTrue);
      expect(info.preferSoftwarePreview, isTrue);
    });

    test('equality', () {
      final a = MediaInfo(
        durationMs: BigInt.from(100),
        width: 10, height: 10, rotation: 0, fps: 30.0,
        videoCodec: 'h264', bitrate: BigInt.from(1000),
        fileSize: BigInt.from(1000),
        hasDolbyVision: false, preferSoftwarePreview: false,
      );
      final b = MediaInfo(
        durationMs: BigInt.from(100),
        width: 10, height: 10, rotation: 0, fps: 30.0,
        videoCodec: 'h264', bitrate: BigInt.from(1000),
        fileSize: BigInt.from(1000),
        hasDolbyVision: false, preferSoftwarePreview: false,
      );
      expect(a, equals(b));
    });
  });

  group('PreviewFramePixelBuffer', () {
    test('construction and equality', () {
      final a = PreviewFramePixelBuffer(
        ptsMs: BigInt.from(1000),
        width: 1920,
        height: 1080,
        pixelBufferPtr: BigInt.from(0x12345678),
      );
      final b = PreviewFramePixelBuffer(
        ptsMs: BigInt.from(1000),
        width: 1920,
        height: 1080,
        pixelBufferPtr: BigInt.from(0x12345678),
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });

  group('PreviewFrameRgba', () {
    test('construction and equality', () {
      final rgba = Uint8List(1920 * 1080 * 4);
      final a = PreviewFrameRgba(
        ptsMs: BigInt.from(500),
        width: 1920,
        height: 1080,
        rgba: rgba,
      );
      final b = PreviewFrameRgba(
        ptsMs: BigInt.from(500),
        width: 1920,
        height: 1080,
        rgba: rgba,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('different frames not equal', () {
      final a = PreviewFrameRgba(
        ptsMs: BigInt.from(100),
        width: 100, height: 100,
        rgba: Uint8List(40000),
      );
      final b = PreviewFrameRgba(
        ptsMs: BigInt.from(200),
        width: 100, height: 100,
        rgba: Uint8List(40000),
      );
      expect(a, isNot(equals(b)));
    });
  });

  group('ProgressEvent', () {
    test('construction and equality', () {
      final a = ProgressEvent(
        jobId: 'job-123',
        phase: ProcessingPhase.encoding,
        percent: 50.0,
        frame: BigInt.from(150),
        fps: 30.0,
        etaMs: BigInt.from(5000),
      );
      final b = ProgressEvent(
        jobId: 'job-123',
        phase: ProcessingPhase.encoding,
        percent: 50.0,
        frame: BigInt.from(150),
        fps: 30.0,
        etaMs: BigInt.from(5000),
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });

  group('ThumbnailBytesOptions', () {
    test('construction and equality', () {
      final a = ThumbnailBytesOptions(
        inputPath: '/vid.mp4',
        positionMs: BigInt.from(1000),
        format: ThumbnailFormat.jpeg,
      );
      final b = ThumbnailBytesOptions(
        inputPath: '/vid.mp4',
        positionMs: BigInt.from(1000),
        format: ThumbnailFormat.jpeg,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });

  group('ThumbnailOptions', () {
    test('construction and equality', () {
      final a = ThumbnailOptions(
        inputPath: '/v.mp4',
        positionMs: BigInt.from(3000),
        format: ThumbnailFormat.webp,
      );
      final b = ThumbnailOptions(
        inputPath: '/v.mp4',
        positionMs: BigInt.from(3000),
        format: ThumbnailFormat.webp,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('with optional outputPath', () {
      final opts = ThumbnailOptions(
        inputPath: '/v.mp4',
        outputPath: '/thumb.jpg',
        positionMs: BigInt.from(500),
        width: 320,
        height: 240,
        format: ThumbnailFormat.jpeg,
      );
      expect(opts.outputPath, '/thumb.jpg');
      expect(opts.width, 320);
      expect(opts.height, 240);
    });
  });
}
