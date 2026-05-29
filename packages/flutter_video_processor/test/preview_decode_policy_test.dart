import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_video_processor/src/runtime/preview_decode_policy.dart';
import 'package:video_processor_core/video_processor_core.dart';

MediaInfo _info({
  bool hasDolbyVision = false,
  bool preferSoftwarePreview = false,
  String videoCodec = 'hevc',
}) =>
    MediaInfo(
      durationMs: BigInt.from(10_000),
      width: 1920,
      height: 1080,
      rotation: 0,
      fps: 30,
      videoCodec: videoCodec,
      audioCodec: null,
      bitrate: BigInt.from(5_000_000),
      fileSize: BigInt.from(10_000_000),
      hasDolbyVision: hasDolbyVision,
      preferSoftwarePreview: preferSoftwarePreview,
    );

void main() {
  test('probe flags force software RGBA path', () {
    final policy = PreviewDecodePolicy.fromProbe(
      mediaInfo: _info(preferSoftwarePreview: true),
      hwPreviewDisabled: false,
    );
    expect(policy.useSoftwareRgba, isTrue);
    expect(policy.useHwPixelBuffer, isFalse);
  });

  test('isRgbaRedirectError recognizes session fallback', () {
    expect(
      PreviewDecodePolicy.isRgbaRedirectError(
        Exception('PREVIEW_RGBA_ONLY'),
      ),
      isTrue,
    );
  });
}
