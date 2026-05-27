import 'package:rust_image_core/rust_image_core.dart';

/// Helpers for [BeautyParams] (Nexus B + swipe look warps).
extension BeautyParamsX on BeautyParams {
  static const zero = BeautyParams(
    skinSmooth: 0,
    eyeBrighten: 0,
    lipTint: LipTintPreset.none,
    lipTintStrength: 0,
    lipPlump: 0,
    blush: 0,
    underEye: 0,
    teethWhiten: 0,
    skinPreserveDetail: 0,
    eyeEnlarge: 0,
    jawSlim: 0,
    noseSlim: 0,
    faceSlim: 0,
    chinVshape: 0,
  );

  bool get hasEffect =>
      skinSmooth > 0.001 ||
      eyeBrighten > 0.001 ||
      (lipTint != LipTintPreset.none && lipTintStrength > 0.001) ||
      lipPlump > 0.001 ||
      blush > 0.001 ||
      underEye > 0.001 ||
      teethWhiten > 0.001 ||
      eyeEnlarge > 0.001 ||
      jawSlim > 0.001 ||
      noseSlim > 0.001 ||
      faceSlim > 0.001 ||
      chinVshape > 0.001;

  BeautyParams copyWith({
    double? skinSmooth,
    double? eyeBrighten,
    LipTintPreset? lipTint,
    double? lipTintStrength,
    double? lipPlump,
    double? blush,
    double? underEye,
    double? teethWhiten,
    double? skinPreserveDetail,
    double? eyeEnlarge,
    double? jawSlim,
    double? noseSlim,
    double? faceSlim,
    double? chinVshape,
  }) {
    return BeautyParams(
      skinSmooth: skinSmooth ?? this.skinSmooth,
      eyeBrighten: eyeBrighten ?? this.eyeBrighten,
      lipTint: lipTint ?? this.lipTint,
      lipTintStrength: lipTintStrength ?? this.lipTintStrength,
      lipPlump: lipPlump ?? this.lipPlump,
      blush: blush ?? this.blush,
      underEye: underEye ?? this.underEye,
      teethWhiten: teethWhiten ?? this.teethWhiten,
      skinPreserveDetail: skinPreserveDetail ?? this.skinPreserveDetail,
      eyeEnlarge: eyeEnlarge ?? this.eyeEnlarge,
      jawSlim: jawSlim ?? this.jawSlim,
      noseSlim: noseSlim ?? this.noseSlim,
      faceSlim: faceSlim ?? this.faceSlim,
      chinVshape: chinVshape ?? this.chinVshape,
    );
  }

  BeautyParams clamped() {
    return BeautyParams(
      skinSmooth: skinSmooth.clamp(0.0, 1.0),
      eyeBrighten: eyeBrighten.clamp(0.0, 1.0),
      lipTint: lipTint,
      lipTintStrength: lipTintStrength.clamp(0.0, 1.0),
      lipPlump: lipPlump.clamp(0.0, 1.0),
      blush: blush.clamp(0.0, 1.0),
      underEye: underEye.clamp(0.0, 1.0),
      teethWhiten: teethWhiten.clamp(0.0, 1.0),
      skinPreserveDetail: skinPreserveDetail.clamp(0.0, 1.0),
      eyeEnlarge: eyeEnlarge.clamp(0.0, 1.0),
      jawSlim: jawSlim.clamp(0.0, 1.0),
      noseSlim: noseSlim.clamp(0.0, 1.0),
      faceSlim: faceSlim.clamp(0.0, 1.0),
      chinVshape: chinVshape.clamp(0.0, 1.0),
    );
  }
}

List<int> regionCountsForAnalysis(FaceAnalysisResult analysis) {
  if (analysis.regionCounts.isEmpty) return const [];
  final raw = analysis.regionCounts.toList();
  // Legacy native payloads included face contour as regionCounts[0].
  if (raw.length == 12) return raw.sublist(1);
  return raw;
}
