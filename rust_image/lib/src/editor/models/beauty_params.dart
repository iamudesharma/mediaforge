import 'package:rust_image/src/rust/api/face.dart';

/// Helpers for [BeautyParams] (Nexus B).
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
  );

  bool get hasEffect =>
      skinSmooth > 0.001 ||
      eyeBrighten > 0.001 ||
      (lipTint != LipTintPreset.none && lipTintStrength > 0.001) ||
      lipPlump > 0.001 ||
      blush > 0.001 ||
      underEye > 0.001 ||
      teethWhiten > 0.001;

  BeautyParams copyWith({
    double? skinSmooth,
    double? eyeBrighten,
    LipTintPreset? lipTint,
    double? lipTintStrength,
    double? lipPlump,
    double? blush,
    double? underEye,
    double? teethWhiten,
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
