import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_forge/image_forge.dart';

void main() {
  group('Landmark2D', () {
    test('construction and equality', () {
      const a = Landmark2D(x: 0.5, y: 0.3, z: 0.0);
      const b = Landmark2D(x: 0.5, y: 0.3, z: 0.0);
      const c = Landmark2D(x: 0.8, y: 0.3, z: 0.0);

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('field access', () {
      const landmark = Landmark2D(x: 0.25, y: 0.75, z: -0.1);
      expect(landmark.x, 0.25);
      expect(landmark.y, 0.75);
      expect(landmark.z, -0.1);
    });

    test('const construction', () {
      const lm = Landmark2D(x: 0, y: 0, z: 0);
      expect(lm, isA<Landmark2D>());
    });
  });

  group('SegmentationMask', () {
    test('construction and equality', () {
      final pixels = Uint8List.fromList([0, 128, 255]);
      final a = SegmentationMask(width: 100, height: 200, pixels: pixels);
      final b = SegmentationMask(width: 100, height: 200, pixels: pixels);

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a.width, 100);
      expect(a.height, 200);
    });

    test('different masks not equal', () {
      final p1 = Uint8List.fromList([1, 2, 3]);
      final p2 = Uint8List.fromList([4, 5, 6]);
      final a = SegmentationMask(width: 10, height: 10, pixels: p1);
      final b = SegmentationMask(width: 10, height: 10, pixels: p2);

      expect(a, isNot(equals(b)));
    });
  });

  group('BeautyParams', () {
    test('construction and equality', () {
      const a = BeautyParams(
        skinSmooth: 0.5,
        eyeBrighten: 0.3,
        lipTint: LipTintPreset.rose,
        lipTintStrength: 0.8,
        lipPlump: 0.0,
        blush: 0.2,
        underEye: 0.4,
        teethWhiten: 0.1,
        skinPreserveDetail: 0.9,
        eyeEnlarge: 0.0,
        jawSlim: 0.0,
        noseSlim: 0.0,
        faceSlim: 0.0,
        chinVshape: 0.0,
      );
      const b = BeautyParams(
        skinSmooth: 0.5,
        eyeBrighten: 0.3,
        lipTint: LipTintPreset.rose,
        lipTintStrength: 0.8,
        lipPlump: 0.0,
        blush: 0.2,
        underEye: 0.4,
        teethWhiten: 0.1,
        skinPreserveDetail: 0.9,
        eyeEnlarge: 0.0,
        jawSlim: 0.0,
        noseSlim: 0.0,
        faceSlim: 0.0,
        chinVshape: 0.0,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('different params not equal', () {
      const a = BeautyParams(
        skinSmooth: 0.0, eyeBrighten: 0.0, lipTint: LipTintPreset.none,
        lipTintStrength: 0.0, lipPlump: 0.0, blush: 0.0,
        underEye: 0.0, teethWhiten: 0.0, skinPreserveDetail: 0.0,
        eyeEnlarge: 0.0, jawSlim: 0.0, noseSlim: 0.0,
        faceSlim: 0.0, chinVshape: 0.0,
      );
      const b = BeautyParams(
        skinSmooth: 1.0, eyeBrighten: 0.0, lipTint: LipTintPreset.none,
        lipTintStrength: 0.0, lipPlump: 0.0, blush: 0.0,
        underEye: 0.0, teethWhiten: 0.0, skinPreserveDetail: 0.0,
        eyeEnlarge: 0.0, jawSlim: 0.0, noseSlim: 0.0,
        faceSlim: 0.0, chinVshape: 0.0,
      );
      expect(a, isNot(equals(b)));
    });

    test('all 14 fields accessible', () {
      const params = BeautyParams(
        skinSmooth: 1.0, eyeBrighten: 1.0, lipTint: LipTintPreset.nude,
        lipTintStrength: 1.0, lipPlump: 1.0, blush: 1.0,
        underEye: 1.0, teethWhiten: 1.0, skinPreserveDetail: 1.0,
        eyeEnlarge: 1.0, jawSlim: 1.0, noseSlim: 1.0,
        faceSlim: 1.0, chinVshape: 1.0,
      );
      expect(params.skinSmooth, 1.0);
      expect(params.eyeBrighten, 1.0);
      expect(params.lipTint, LipTintPreset.nude);
      expect(params.lipTintStrength, 1.0);
      expect(params.lipPlump, 1.0);
      expect(params.blush, 1.0);
      expect(params.underEye, 1.0);
      expect(params.teethWhiten, 1.0);
      expect(params.skinPreserveDetail, 1.0);
      expect(params.eyeEnlarge, 1.0);
      expect(params.jawSlim, 1.0);
      expect(params.noseSlim, 1.0);
      expect(params.faceSlim, 1.0);
      expect(params.chinVshape, 1.0);
    });
  });

  group('FaceAnalysisResult', () {
    test('construction and equality', () {
      final landmarks = [const Landmark2D(x: 0.5, y: 0.5, z: 0.0)];
      final regionCounts = Uint32List.fromList([10, 5, 3]);
      final a = FaceAnalysisResult(
        landmarks: landmarks,
        confidence: 0.99,
        faceContourCount: 17,
        regionCounts: regionCounts,
      );
      final b = FaceAnalysisResult(
        landmarks: landmarks,
        confidence: 0.99,
        faceContourCount: 17,
        regionCounts: regionCounts,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('nullable segmentation field', () {
      final result = FaceAnalysisResult(
        landmarks: [],
        confidence: 0.5,
        segmentation: null,
        faceContourCount: 0,
        regionCounts: Uint32List(0),
      );
      expect(result.segmentation, isNull);
    });

    test('with segmentation mask', () {
      final mask = SegmentationMask(
        width: 100,
        height: 100,
        pixels: Uint8List(10000),
      );
      final result = FaceAnalysisResult(
        landmarks: [const Landmark2D(x: 0.1, y: 0.1, z: 0.0)],
        confidence: 0.95,
        segmentation: mask,
        faceContourCount: 17,
        regionCounts: Uint32List.fromList([5]),
      );
      expect(result.segmentation, isNotNull);
      expect(result.confidence, 0.95);
    });

    test('field access', () {
      final landmarks = [
        const Landmark2D(x: 0.0, y: 0.0, z: 0.0),
        const Landmark2D(x: 1.0, y: 1.0, z: 0.0),
      ];
      final regionCounts = Uint32List.fromList([3, 4]);
      final result = FaceAnalysisResult(
        landmarks: landmarks,
        confidence: 0.75,
        faceContourCount: 0,
        regionCounts: regionCounts,
      );
      expect(result.landmarks, hasLength(2));
      expect(result.confidence, 0.75);
      expect(result.faceContourCount, 0);
      expect(result.regionCounts, hasLength(2));
    });
  });
}
