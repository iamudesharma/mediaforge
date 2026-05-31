import 'package:image_forge/image_forge.dart';
import 'package:image_forge/image_forge.dart';

/// User-facing label for a combo swipe look (Dart-side, no FRB hop).
String swipeLookDisplayNameFor(SwipeLookPreset preset) {
  return switch (preset) {
    SwipeLookPreset.cleanGirlGlow => 'Clean Girl Glow',
    SwipeLookPreset.cloudSkin => 'Cloud Skin',
    SwipeLookPreset.goldenAura => 'Golden Aura',
    SwipeLookPreset.softFocus => 'Soft Focus',
    SwipeLookPreset.fauxFilm => 'Faux Film',
    SwipeLookPreset.boldGlamourLite => 'Bold Glamour Lite',
    SwipeLookPreset.neonNight => 'Neon Night',
    SwipeLookPreset.animeAirbrush => 'Anime Airbrush',
  };
}

/// 0 = Original; 1…N = [SwipeLookPreset.values] in order.
int swipeLookIndex(SwipeLookPreset? preset) {
  if (preset == null) return 0;
  return SwipeLookPreset.values.indexOf(preset) + 1;
}

SwipeLookPreset? swipeLookAtIndex(int index) {
  if (index <= 0) return null;
  final presets = SwipeLookPreset.values;
  if (index > presets.length) return null;
  return presets[index - 1];
}

int get swipeLookCount => SwipeLookPreset.values.length + 1;

BeautyParams swipeLookBeautyParamsFor(SwipeLookPreset preset) =>
    swipeLookBeautyParams(preset: preset);
