import 'package:image_forge/image_forge.dart' as frb;

/// Primary looks shown in the beauty strip (Nexus C core set).
const primaryBeautyLooks = [
  frb.BeautyLookPreset.natural,
  frb.BeautyLookPreset.soft,
  frb.BeautyLookPreset.glow,
  frb.BeautyLookPreset.glam,
  frb.BeautyLookPreset.clear,
];

/// Extended looks (optional chips after primary set).
const extendedBeautyLooks = [
  frb.BeautyLookPreset.peach,
  frb.BeautyLookPreset.bold,
];

List<frb.BeautyLookPreset> get allBeautyLooks => [
      ...primaryBeautyLooks,
      ...extendedBeautyLooks,
    ];

String beautyLookLabel(frb.BeautyLookPreset preset) =>
    frb.beautyLookDisplayName(preset: preset);

/// 0 = Original (no look); 1…N = [allBeautyLooks] in order.
int beautyLookIndex(frb.BeautyLookPreset? preset) {
  if (preset == null) return 0;
  final i = allBeautyLooks.indexOf(preset);
  return i < 0 ? 0 : i + 1;
}

frb.BeautyLookPreset? beautyLookAtIndex(int index) {
  if (index <= 0) return null;
  final looks = allBeautyLooks;
  if (index > looks.length) return null;
  return looks[index - 1];
}

int get beautyLookCount => allBeautyLooks.length + 1;

frb.BeautyParams beautyParamsForLookPreset(frb.BeautyLookPreset preset) =>
    frb.beautyParamsForLook(preset: preset);

/// Match committed params to a preset recipe (for chip highlight after undo).
frb.BeautyLookPreset? beautyLookMatching(
  frb.BeautyParams params, {
  double eps = 0.02,
}) {
  for (final look in allBeautyLooks) {
    if (_paramsMatch(params, beautyParamsForLookPreset(look), eps)) {
      return look;
    }
  }
  return null;
}

bool _paramsMatch(frb.BeautyParams a, frb.BeautyParams b, double eps) {
  bool close(double x, double y) => (x - y).abs() <= eps;
  return close(a.skinSmooth, b.skinSmooth) &&
      close(a.eyeBrighten, b.eyeBrighten) &&
      a.lipTint == b.lipTint &&
      close(a.lipTintStrength, b.lipTintStrength) &&
      close(a.lipPlump, b.lipPlump) &&
      close(a.blush, b.blush);
}
